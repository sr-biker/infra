module "cicd" {
  source = "../../modules/cicd"

  pipeline_name      = "customer-api-pipeline"
  ecr_repository_url = data.terraform_remote_state.k8s_nodes.outputs.contacts_micro_service_ecr_repository_url
  ecr_repository_arn = data.terraform_remote_state.k8s_nodes.outputs.contacts_micro_service_ecr_repository_arn
}

module "cicd_membership" {
  source = "../../modules/cicd"

  # Distinct var.name -- every other resource in the module (artifact bucket, GitHub
  # connection, IAM roles, CodeBuild project) is prefixed with this, so it must differ
  # from the default "infra-prod" to avoid colliding with the contacts-micro-service
  # instance above.
  name             = "infra-prod-membership"
  pipeline_name    = "membership-pipeline"
  github_repo      = "membership-ms"
  values_file_path = "helm/membership/values-prod.yaml"

  ecr_repository_url = data.terraform_remote_state.k8s_nodes.outputs.membership_ecr_repository_url
  ecr_repository_arn = data.terraform_remote_state.k8s_nodes.outputs.membership_ecr_repository_arn
}
