variable "kubernetes_version" {
  type        = string
  description = "EKS Kubernetes version. Supported versions: aws eks describe-cluster-versions --query 'clusterVersions[].clusterVersion'"
  default     = "1.36"
}

variable "admin_cidrs" {
  type        = list(string)
  description = "Your public IP address as a /32, e.g. [\"203.0.113.10/32\"]: the only place the API endpoint accepts connections from."
}
