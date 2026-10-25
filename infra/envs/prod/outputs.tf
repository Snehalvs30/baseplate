output "cluster_name" {
  value = module.eks.cluster_name
}

output "configure_kubectl" {
  value = "aws eks update-kubeconfig --region us-east-2 --name ${module.eks.cluster_name}"
}

output "tenant_secret_role_arns" {
  value = { for tenant, role in aws_iam_role.tenant_secrets : tenant => role.arn }
}

output "external_secrets_role_arn" {
  value = aws_iam_role.external_secrets.arn
}

output "database_hosts" {
  value = { for tenant, db in module.database : tenant => db.address }
}
