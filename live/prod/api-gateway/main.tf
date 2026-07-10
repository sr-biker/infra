# Bucket/region here must match live/prod/env.hcl (state_bucket, aws_region).
data "terraform_remote_state" "vpc" {
  backend = "s3"

  config = {
    bucket = "infra-tfstate-prod-us-east-1"
    key    = "live/prod/vpc/terraform.tfstate"
    region = "us-east-1"
  }
}

data "terraform_remote_state" "alb" {
  backend = "s3"

  config = {
    bucket = "infra-tfstate-prod-us-east-1"
    key    = "live/prod/alb/terraform.tfstate"
    region = "us-east-1"
  }
}

module "api_gateway" {
  source = "../../../modules/api-gateway"

  private_subnet_ids    = data.terraform_remote_state.vpc.outputs.private_subnet_ids
  alb_security_group_id = data.terraform_remote_state.alb.outputs.alb_security_group_id
  alb_listener_arn      = data.terraform_remote_state.alb.outputs.listener_arn
}
