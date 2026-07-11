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
