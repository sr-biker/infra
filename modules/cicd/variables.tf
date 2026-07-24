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

# Gates the Build stage (docker build + ECR push) behind a passing CodeBuild run of
# evals_buildspec -- default off so the existing Java pipelines (contacts-micro-service,
# membership), which have no Python evals harness, are unaffected. Set true and supply
# evals_buildspec for an app that has one (see studio-chatbot's instantiation).
variable "enable_evals_gate" {
  type    = bool
  default = false
}

# Full inline buildspec (YAML string) for the Evals stage. App-specific -- unlike the Build
# stage's fixed docker-build-and-push shape, what "run the evals" means (which suite, what
# fixture data, whether a throwaway DB needs to be stood up) varies per app, so this is
# supplied by the caller rather than templated here. Required when enable_evals_gate = true.
variable "evals_buildspec" {
  type    = string
  default = null
}

# CodeBuild environment image for the Evals stage -- distinct from the Build stage's fixed
# amazonlinux2-aarch64 (which only ever needs `docker build`), since evals need a language
# runtime/toolchain that varies per app. Defaults to Python 3.13, x86 (LINUX_CONTAINER, not
# the Build stage's ARM_CONTAINER) since that's what studio-chatbot's evals need -- ragas's
# nest_asyncio dependency is incompatible with 3.14 (see studio-chatbot's
# requirements-evals.txt), and this image family only publishes x86 tags.
variable "evals_compute_image" {
  type    = string
  default = "public.ecr.aws/docker/library/python:3.13"
}

# Name of an *existing* Secrets Manager secret holding an OpenAI API key, injected into the
# Evals stage as OPENAI_API_KEY. Not Terraform-managed; only used when enable_evals_gate = true.
variable "openai_api_key_secret_name" {
  type    = string
  default = "/cicd/openai/api-key"
}

# JSON key within openai_api_key_secret_name whose value is the actual API key -- not
# necessarily equal to the secret name (unlike github_token_secret_name, which is a plain
# string secret with no JSON key at all).
variable "openai_api_key_secret_json_key" {
  type    = string
  default = "OPENAI_API_KEY"
}

