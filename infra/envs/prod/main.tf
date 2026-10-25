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
    aws    = { source = "hashicorp/aws", version = "~> 6.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
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
  # The key each app's chart expects its database password under.
  password_keys = { ledgerline = "db-password", footnote = "database-password" }
}

module "network" {
  source             = "../../modules/network"
  cluster_name       = local.name
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

# Secrets access with EKS Pod Identity. External Secrets Operator gets its own role,
# which may do one thing: assume a tenant's role. Each tenant role may read only that
# tenant's secrets (baseplate/prod/<tenant>/*). The platform's per-tenant secret stores
# pin a namespace to its role, so one tenant can't read another's secrets.
resource "aws_iam_role" "external_secrets" {
  name = "${local.name}-external-secrets"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_eks_pod_identity_association" "external_secrets" {
  cluster_name    = module.eks.cluster_name
  namespace       = "external-secrets"
  service_account = "platform-external-secrets" # created by the External Secrets chart
  role_arn        = aws_iam_role.external_secrets.arn
}

resource "aws_iam_role" "tenant_secrets" {
  for_each = toset(local.tenants)
  name     = "${local.name}-${each.key}-secrets"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = aws_iam_role.external_secrets.arn }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy" "tenant_secrets" {
  for_each = toset(local.tenants)
  name     = "read-own-secrets"
  role     = aws_iam_role.tenant_secrets[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      Resource = "arn:aws:secretsmanager:us-east-2:${data.aws_caller_identity.current.account_id}:secret:baseplate/prod/${each.key}/*"
    }]
  })
}

resource "aws_iam_role_policy" "external_secrets_assume_tenants" {
  name = "assume-tenant-roles"
  role = aws_iam_role.external_secrets.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sts:AssumeRole", "sts:TagSession"]
      Resource = [for role in aws_iam_role.tenant_secrets : role.arn]
    }]
  })
}

# One PostgreSQL instance per tenant. Production: a standby in another zone (multi-AZ),
# a week of backups, deletion protection, a final snapshot, and a secret recovery window.
module "database" {
  source   = "../../modules/rds"
  for_each = toset(local.tenants)

  name                       = "${local.name}-${each.key}"
  vpc_id                     = module.network.vpc_id
  subnet_ids                 = module.network.private_subnet_ids
  allowed_security_group_ids = [module.eks.cluster_security_group_id]
  db_name                    = each.key
  username                   = each.key
  password_key               = local.password_keys[each.key]
  secret_name                = "baseplate/prod/${each.key}/database"
  instance_class             = "db.t4g.small"
  multi_az                   = true
  backup_retention_days      = 7
  deletion_protection        = true
  final_snapshot             = true
  secret_recovery_days       = 7
}
