locals {
  environment  = "prod"
  aws_region   = "us-east-1"
  state_bucket = "infra-tfstate-prod-us-east-1"

  # Which units' remote state each unit's main.tf needs to read via terraform_remote_state.
  # Keyed and valued by directory name; data source labels are derived from these with
  # hyphens replaced by underscores (data "terraform_remote_state" "k8s_nodes", not
  # "k8s-nodes" — a literal hyphen there would parse as subtraction in an expression).
  remote_state_deps = {
    "vpc"         = []
    "k8s-nodes"   = ["vpc"]
    "alb"         = ["vpc", "k8s-nodes"]
    "api-gateway" = ["vpc", "alb"]
    "rds"         = []
  }
}

# Generates a terraform_remote_state data block for each of the current unit's
# remote_state_deps entries, so k8s-nodes/alb/api-gateway's main.tf don't have to
# hand-duplicate the bucket/key/region literals for every dependency they read.
generate "remote_state_data" {
  path      = "remote_state_data.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
  %{~for dep in lookup(local.remote_state_deps, basename(path_relative_to_include("env")), [])~}
  data "terraform_remote_state" "${replace(dep, "-", "_")}" {
    backend = "s3"

    config = {
      bucket = "${local.state_bucket}"
      key    = "prod/${dep}/terraform.tfstate"
      region = "${local.aws_region}"
    }
  }
  %{~endfor~}
  EOF
}
