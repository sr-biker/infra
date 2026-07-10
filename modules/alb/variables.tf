variable "name" {
  type    = string
  default = "infra-prod"
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "node_security_group_id" {
  type        = string
  description = "Security group of the K8s worker nodes, so the ALB can reach the ingress NodePort"
}

variable "worker_asg_name" {
  type = string
}

variable "ingress_node_port" {
  type    = number
  default = 30080
}
