output "control_plane_private_ip" {
  value = module.k8s_nodes.control_plane_private_ip
}

output "control_plane_instance_id" {
  value = module.k8s_nodes.control_plane_instance_id
}

output "node_security_group_id" {
  value = module.k8s_nodes.node_security_group_id
}

output "worker_asg_name" {
  value = module.k8s_nodes.worker_asg_name
}

output "contacts_micro_service_ecr_repository_url" {
  value = module.k8s_nodes.contacts_micro_service_ecr_repository_url
}

output "contacts_micro_service_ecr_repository_arn" {
  value = module.k8s_nodes.contacts_micro_service_ecr_repository_arn
}

output "membership_ecr_repository_url" {
  value = module.k8s_nodes.membership_ecr_repository_url
}

output "membership_ecr_repository_arn" {
  value = module.k8s_nodes.membership_ecr_repository_arn
}

output "studio_chatbot_ecr_repository_url" {
  value = module.k8s_nodes.studio_chatbot_ecr_repository_url
}

output "studio_chatbot_ecr_repository_arn" {
  value = module.k8s_nodes.studio_chatbot_ecr_repository_arn
}
