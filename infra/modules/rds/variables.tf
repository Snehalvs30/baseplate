variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnets, in at least two availability zones."
}

variable "allowed_security_group_ids" {
  type        = list(string)
  description = "Security groups allowed to connect (the EKS nodes)."
}

variable "db_name" {
  type = string
}

variable "username" {
  type = string
}

variable "password_key" {
  type        = string
  description = "The key the password is stored under in the secret, matching what the app's chart expects."
}

variable "secret_name" {
  type = string
}

variable "engine_version" {
  type    = string
  default = "17"
}

variable "instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "multi_az" {
  type    = bool
  default = false
}

variable "backup_retention_days" {
  type    = number
  default = 1
}

variable "deletion_protection" {
  type    = bool
  default = false
}

variable "final_snapshot" {
  type    = bool
  default = false
}

variable "secret_recovery_days" {
  type    = number
  default = 0
}
