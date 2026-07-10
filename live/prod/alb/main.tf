# Bucket/region here must match live/prod/env.hcl (state_bucket, aws_region).
data "terraform_remote_state" "vpc" {
  backend = "s3"

  config = {
    bucket = "infra-tfstate-prod-us-east-1"
    key    = "live/prod/vpc/terraform.tfstate"
    region = "us-east-1"
  }
}

data "terraform_remote_state" "k8s_nodes" {
  backend = "s3"

  config = {
    bucket = "infra-tfstate-prod-us-east-1"
    key    = "live/prod/k8s-nodes/terraform.tfstate"
    region = "us-east-1"
  }
}

module "alb" {
  source = "../../../modules/alb"

  vpc_id                  = data.terraform_remote_state.vpc.outputs.vpc_id
  vpc_cidr                = data.terraform_remote_state.vpc.outputs.vpc_cidr
  private_subnet_ids      = data.terraform_remote_state.vpc.outputs.private_subnet_ids
  node_security_group_id  = data.terraform_remote_state.k8s_nodes.outputs.node_security_group_id
  worker_asg_name         = data.terraform_remote_state.k8s_nodes.outputs.worker_asg_name
}
