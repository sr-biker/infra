include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

terraform {
  source = "${get_repo_root()}/modules/alb"
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id             = "vpc-mock"
    private_subnet_ids = ["subnet-mock1", "subnet-mock2"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

dependency "k8s_nodes" {
  config_path = "../k8s-nodes"

  mock_outputs = {
    node_security_group_id = "sg-mock"
    worker_asg_name        = "asg-mock"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

inputs = {
  vpc_id                 = dependency.vpc.outputs.vpc_id
  private_subnet_ids     = dependency.vpc.outputs.private_subnet_ids
  node_security_group_id = dependency.k8s_nodes.outputs.node_security_group_id
  worker_asg_name        = dependency.k8s_nodes.outputs.worker_asg_name
}
