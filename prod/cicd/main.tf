module "cicd" {
  source = "../../modules/cicd"

  ecr_repository_url        = data.terraform_remote_state.k8s_nodes.outputs.contacts_micro_service_ecr_repository_url
  ecr_repository_arn        = data.terraform_remote_state.k8s_nodes.outputs.contacts_micro_service_ecr_repository_arn
  control_plane_instance_id = data.terraform_remote_state.k8s_nodes.outputs.control_plane_instance_id
}
