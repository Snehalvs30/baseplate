variable "kubernetes_version" {
  type        = string
  description = "EKS Kubernetes version. Supported versions: aws eks describe-cluster-versions --query 'clusterVersions[].clusterVersion'"
  default     = "1.36"
}
