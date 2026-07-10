# Bucket/region here must match live/prod/env.hcl (state_bucket, aws_region).
data "terraform_remote_state" "vpc" {
  backend = "s3"

  config = {
    bucket = "infra-tfstate-prod-us-east-1"
    key    = "live/prod/vpc/terraform.tfstate"
    region = "us-east-1"
  }
}

module "k8s_nodes" {
  source = "../../../modules/k8s-nodes"

  vpc_id             = data.terraform_remote_state.vpc.outputs.vpc_id
  vpc_cidr           = data.terraform_remote_state.vpc.outputs.vpc_cidr
  private_subnet_ids = data.terraform_remote_state.vpc.outputs.private_subnet_ids
}
