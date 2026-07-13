variable "name" {
  type    = string
  default = "infra-prod"
}

# CodePipeline names are a flat namespace (not scoped by var.name the way every other
# resource in this module is) -- explicit per-instance so two invocations of this module
# (one per app) don't collide trying to create the same pipeline name.
variable "pipeline_name" {
  type = string
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

