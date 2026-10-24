# The production environment: planned to show what it would look like, not applied.
# Same modules as dev; only the inputs differ: 3 zones with a NAT gateway in each (a zone
# outage doesn't cut off the others), on-demand nodes, longer log retention, and a
# private-only API endpoint (reached through a VPN or bastion in the VPC).
#
#   terraform init -backend-config="bucket=baseplate-tfstate-<account id>"
#   terraform plan
terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
  backend "s3" {
    key          = "envs/prod/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true # S3-native state locking: two applies can't run at once
  }
}

provider "aws" {
  region = "us-east-2"
  default_tags {
    tags = { Project = "baseplate", Environment = "prod", ManagedBy = "terraform" }
  }
}

data "aws_caller_identity" "current" {}

locals {
  name    = "baseplate-prod"
  tenants = ["ledgerline", "footnote"]
}

module "network" {
  source             = "../../modules/network"
  name               = local.name
  cidr               = "10.30.0.0/16"
  az_count           = 3
  single_nat_gateway = false
}

module "eks" {
  source               = "../../modules/eks"
  cluster_name         = local.name
  kubernetes_version   = var.kubernetes_version
  subnet_ids           = module.network.private_subnet_ids
  public_access_cidrs  = []
  admin_principal_arns = [data.aws_caller_identity.current.arn]
  node_instance_types  = ["t4g.large"]
  node_capacity_type   = "ON_DEMAND"
  node_desired         = 3
  node_min             = 3
  node_max             = 6
  log_retention_days   = 30
}

# One role per tenant for External Secrets: each can read only its own secrets
# (baseplate/prod/<tenant>/*), through a service account in its own namespace.
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
      Resource = "arn:aws:secretsmanager:us-east-2:${data.aws_caller_identity.current.account_id}:secret:baseplate/prod/${each.key}/*"
    }]
  })
}
