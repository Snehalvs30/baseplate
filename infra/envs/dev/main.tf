# The dev environment: what gets applied. Kept cheap: 2 zones, one shared NAT gateway,
# and spot nodes (several interchangeable ARM types, so a spot shortage of one type
# doesn't stop the group). The API endpoint is reachable only from your IP address.
#
#   terraform init -backend-config="bucket=baseplate-tfstate-<account id>"
#   terraform plan
terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
  backend "s3" {
    key          = "envs/dev/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true # S3-native state locking: two applies can't run at once
  }
}

provider "aws" {
  region = "us-east-2"
  default_tags {
    tags = { Project = "baseplate", Environment = "dev", ManagedBy = "terraform" }
  }
}

data "aws_caller_identity" "current" {}

locals {
  name    = "baseplate-dev"
  tenants = ["ledgerline", "footnote"]
}

module "network" {
  source             = "../../modules/network"
  name               = local.name
  cidr               = "10.20.0.0/16"
  az_count           = 2
  single_nat_gateway = true
}

module "eks" {
  source               = "../../modules/eks"
  cluster_name         = local.name
  kubernetes_version   = var.kubernetes_version
  subnet_ids           = module.network.private_subnet_ids
  public_access_cidrs  = var.admin_cidrs
  admin_principal_arns = [data.aws_caller_identity.current.arn]
  node_instance_types  = ["t4g.medium", "m6g.medium", "m7g.medium"]
  node_capacity_type   = "SPOT"
  node_desired         = 2
  node_min             = 2
  node_max             = 3
  log_retention_days   = 7
}

# One role per tenant for External Secrets: each can read only its own secrets
# (baseplate/dev/<tenant>/*), through a service account in its own namespace.
module "tenant_secrets" {
  source   = "../../modules/irsa-role"
  for_each = toset(local.tenants)

  name              = "${local.name}-${each.key}-secrets"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_issuer       = module.eks.oidc_issuer
  namespace         = "tenant-${each.key}"
  service_account   = "secrets-reader"
  policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      Resource = "arn:aws:secretsmanager:us-east-2:${data.aws_caller_identity.current.account_id}:secret:baseplate/dev/${each.key}/*"
    }]
  })
}
