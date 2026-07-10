include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

terraform {
  source = "${get_repo_root()}/modules/k8s-nodes"
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id             = "vpc-mock"
    vpc_cidr           = "10.0.0.0/16"
    private_subnet_ids = ["subnet-mock1", "subnet-mock2"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

inputs = {
  name                        = "infra-${local.env_vars.locals.environment}"
  vpc_id                      = dependency.vpc.outputs.vpc_id
  vpc_cidr                    = dependency.vpc.outputs.vpc_cidr
  private_subnet_ids          = dependency.vpc.outputs.private_subnet_ids
  control_plane_instance_type = local.env_vars.locals.control_plane_instance_type
  worker_instance_type        = local.env_vars.locals.worker_instance_type
  worker_count                = local.env_vars.locals.worker_count
  kubernetes_version          = local.env_vars.locals.kubernetes_version
}
