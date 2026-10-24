output "cluster_name" {
  value = module.eks.cluster_name
}

output "configure_kubectl" {
  value = "aws eks update-kubeconfig --region us-east-2 --name ${module.eks.cluster_name}"
}

output "tenant_secret_role_arns" {
  value = { for tenant, role in module.tenant_secrets : tenant => role.role_arn }
}
