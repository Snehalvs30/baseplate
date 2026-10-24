variable "cluster_name" {
  type = string
}

variable "kubernetes_version" {
  type        = string
  description = "EKS Kubernetes version, e.g. \"1.34\". Check what's supported with: aws eks describe-cluster-versions"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnets for the control plane's network interfaces and the nodes."
}

variable "public_access_cidrs" {
  type        = list(string)
  description = "Address ranges allowed to reach the API endpoint over the internet. Empty = private endpoint only."
  default     = []
}

variable "admin_principal_arns" {
  type        = list(string)
  description = "IAM users or roles given cluster-admin access."
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t4g.medium"]
}

variable "node_capacity_type" {
  type        = string
  description = "ON_DEMAND, or SPOT (much cheaper; nodes can be reclaimed)."
  default     = "ON_DEMAND"
}

variable "node_desired" {
  type    = number
  default = 2
}

variable "node_min" {
  type    = number
  default = 2
}

variable "node_max" {
  type    = number
  default = 3
}

variable "node_disk_gb" {
  type    = number
  default = 30
}

variable "log_retention_days" {
  type    = number
  default = 7
}
