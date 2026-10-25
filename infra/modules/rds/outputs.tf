output "address" {
  value = aws_db_instance.this.address
}

output "secret_name" {
  value = aws_secretsmanager_secret.this.name
}
