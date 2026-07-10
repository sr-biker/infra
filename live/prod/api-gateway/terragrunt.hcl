include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

terraform {
  source = "${get_repo_root()}/modules/api-gateway"
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    private_subnet_ids = ["subnet-mock1", "subnet-mock2"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

dependency "alb" {
  config_path = "../alb"

  mock_outputs = {
    alb_security_group_id = "sg-mock"
    listener_arn          = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/mock"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

inputs = {
  name                  = "infra-${local.env_vars.locals.environment}"
  private_subnet_ids    = dependency.vpc.outputs.private_subnet_ids
  alb_security_group_id = dependency.alb.outputs.alb_security_group_id
  alb_listener_arn      = dependency.alb.outputs.listener_arn
}
