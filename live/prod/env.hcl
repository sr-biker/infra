locals {
  environment  = "prod"
  aws_region   = "us-east-1"
  state_bucket = "infra-tfstate-prod-us-east-1"

  vpc_cidr             = "10.0.0.0/16"
  public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]

  control_plane_instance_type = "t3.medium"
  worker_instance_type        = "t3.medium"
  worker_count                = 2

  kubernetes_version = "1.30"
}
