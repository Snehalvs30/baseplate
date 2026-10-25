variable "name" {
  type        = string
  description = "Name prefix for the VPC and its resources."
}

variable "cidr" {
  type        = string
  description = "The VPC's address range."
  default     = "10.20.0.0/16"
}

variable "az_count" {
  type        = number
  description = "Availability zones to spread across (2 or 3)."
  default     = 2
  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "Use 2 or 3 availability zones."
  }
}

variable "single_nat_gateway" {
  type        = bool
  description = "One shared NAT gateway (cheaper) instead of one per zone (survives a zone outage)."
  default     = true
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster that will create load balancers in these subnets (tags them)."
  default     = ""
}
