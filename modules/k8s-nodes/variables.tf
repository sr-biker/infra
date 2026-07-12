variable "name" {
  type    = string
  default = "infra-prod"
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "control_plane_instance_type" {
  type    = string
  default = "t4g.small"
}

variable "worker_instance_type" {
  type    = string
  default = "t4g.small"
}

variable "worker_count" {
  type    = number
  default = 2
}

variable "kubernetes_version" {
  type        = string
  default     = "1.36"
  description = "Kubernetes minor version, e.g. 1.36"
}

variable "db_secret_name" {
  type        = string
  default     = "/rds/postgres/credentials"
  description = "Secrets Manager secret nodes are allowed to read via the Secrets Store CSI driver (AWS provider), scoped narrowly to this one name -- not secretsmanager:* on everything."
}
