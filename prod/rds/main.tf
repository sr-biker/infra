# Self-contained: this module provisions its own VPC (see modules/rds), it does not
# join the k8s stack's VPC. No terraform_remote_state dependency on other units.
module "rds" {
  source = "../../modules/rds"
}
