# A PostgreSQL database for one tenant: its own instance, security group and credentials.
# The connection details are stored in Secrets Manager, where only that tenant's
# External Secrets role can read them.
terraform {
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 6.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

# Letters and digits only: the password is embedded in connection URLs, where characters
# like # ? / @ would break parsing. 32 characters keeps it strong.
resource "random_password" "this" {
  length  = 32
  special = false
}

resource "aws_db_subnet_group" "this" {
  name       = var.name
  subnet_ids = var.subnet_ids
}

# Reachable only from the cluster's nodes, only on PostgreSQL's port.
resource "aws_security_group" "this" {
  name        = "${var.name}-db"
  description = "${var.name}: PostgreSQL from the EKS nodes only"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-db" }
}

resource "aws_vpc_security_group_ingress_rule" "postgres" {
  # count, not for_each: the IDs are only known after apply, but how many there are is
  # known at plan time (for_each needs the values themselves to name its instances).
  count                        = length(var.allowed_security_group_ids)
  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = var.allowed_security_group_ids[count.index]
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_db_instance" "this" {
  identifier     = var.name
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  db_name  = var.db_name
  username = var.username
  password = random_password.this.result

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  publicly_accessible    = false
  multi_az               = var.multi_az

  backup_retention_period    = var.backup_retention_days
  deletion_protection        = var.deletion_protection
  skip_final_snapshot        = !var.final_snapshot
  final_snapshot_identifier  = var.final_snapshot ? "${var.name}-final" : null
  auto_minor_version_upgrade = true
  apply_immediately          = true
}

resource "aws_secretsmanager_secret" "this" {
  name        = var.secret_name
  description = "${var.name}: database connection"
  # 0 = deleted immediately on destroy, so the same name can be reused right away
  # (dev). Production keeps a recovery window.
  recovery_window_in_days = var.secret_recovery_days
}

resource "aws_secretsmanager_secret_version" "this" {
  secret_id = aws_secretsmanager_secret.this.id
  secret_string = jsonencode({
    (var.password_key) = random_password.this.result
    host               = aws_db_instance.this.address
    port               = aws_db_instance.this.port
    username           = var.username
    dbname             = var.db_name
  })
}
