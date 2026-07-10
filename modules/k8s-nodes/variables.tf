variable "name" {
  type = string
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
  type = string
}

variable "worker_instance_type" {
  type = string
}

variable "worker_count" {
  type = number
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes minor version, e.g. 1.30"
}

variable "ssh_key_name" {
  type        = string
  default     = null
  description = "Existing EC2 key pair name for SSH access, optional"
}
