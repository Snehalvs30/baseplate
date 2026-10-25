# The dev environment: what gets applied. Kept cheap: 2 zones, one shared NAT gateway,
# and spot nodes (several interchangeable ARM types, so a spot shortage of one type
# doesn't stop the group). The API endpoint is reachable only from your IP address.
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
  # The key each app's chart expects its database password under.
  password_keys = { ledgerline = "db-password", footnote = "database-password" }
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
  node_instance_types  = ["m7i-flex.large"] # free-plan accounts may only use Free Tier-eligible types
  node_capacity_type   = "ON_DEMAND"
  node_ami_type        = "AL2023_x86_64_STANDARD" # matches the Intel instance type
  node_desired         = 2
  node_min             = 2
  node_max             = 3
  log_retention_days   = 7
}

# Secrets access with EKS Pod Identity. External Secrets Operator gets its own role,
# which may do one thing: assume a tenant's role. Each tenant role may read only that
# tenant's secrets (baseplate/dev/<tenant>/*). The platform's per-tenant secret stores
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
      Action    = "sts:AssumeRole"
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
      Resource = "arn:aws:secretsmanager:us-east-2:${data.aws_caller_identity.current.account_id}:secret:baseplate/dev/${each.key}/*"
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
      Action   = "sts:AssumeRole"
      Resource = [for role in aws_iam_role.tenant_secrets : role.arn]
    }]
  })
}

# One small PostgreSQL instance per tenant: separate credentials, security group and data.
# Footnote needs pgvector, which RDS for PostgreSQL provides as an extension.
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
  secret_name                = "baseplate/dev/${each.key}/database"
  instance_class             = "db.t4g.micro"
  multi_az                   = false
  backup_retention_days      = 1
  deletion_protection        = false
  final_snapshot             = false
  secret_recovery_days       = 0
}
