locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket       = local.env_vars.locals.state_bucket
    key          = "${path_relative_to_include()}/terraform.tfstate"
    region       = local.env_vars.locals.aws_region
    encrypt      = true
    use_lockfile = true
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "${local.env_vars.locals.aws_region}"

  default_tags {
    tags = {
      Project     = "infra"
      Environment = "${local.env_vars.locals.environment}"
      ManagedBy   = "terragrunt"
    }
  }
}
EOF
}
