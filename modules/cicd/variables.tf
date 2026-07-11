variable "name" {
  type    = string
  default = "infra-prod"
}

variable "github_owner" {
  type    = string
  default = "sr-biker"
}

variable "github_repo" {
  type    = string
  default = "-contacts-micro-service"
}

variable "github_branch" {
  type    = string
  default = "main"
}

variable "ecr_repository_url" {
  type = string
}

variable "ecr_repository_arn" {
  type = string
}

variable "control_plane_instance_id" {
  type = string
}

variable "k8s_deployment_name" {
  type    = string
  default = "contacts-micro-service"
}

variable "k8s_container_name" {
  type    = string
  default = "app"
}

variable "k8s_namespace" {
  type    = string
  default = "default"
}
