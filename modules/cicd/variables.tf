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

# ARN of an existing aws_codestarconnections_connection (GitHub-authorized) to reuse instead
# of creating a new one -- one connection authorizes the whole GitHub account/org, not a
# single repo, so a second pipeline in the same account doesn't need its own manual
# console approval. Leave null (default) to create a fresh connection for this instance.
variable "codestar_connection_arn" {
  type    = string
  default = null
}

variable "ecr_repository_url" {
  type = string
}

variable "ecr_repository_arn" {
  type = string
}

# Path (relative to repo root) to the Helm chart's values-prod.yaml, updated with the new
# image tag after each ECR push so Argo CD (selfHeal, watching this file's git state) picks
# up the new version -- no separate Deploy stage needed.
variable "values_file_path" {
  type    = string
  default = "helm/contacts-micro-service/values-prod.yaml"
}

# Name of an *existing* Secrets Manager secret (plain string value, not JSON) holding a
# GitHub PAT with `repo` scope on github_owner/github_repo -- used by the Build stage to
# push the image-tag bump commit back. Not Terraform-managed, same pattern as rds's
# master_secret_name: create it once by hand before applying.
variable "github_token_secret_name" {
  type    = string
  default = "/cicd/github/token"
}

