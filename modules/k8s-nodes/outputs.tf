output "control_plane_private_ip" {
  value = aws_instance.control_plane.private_ip
}

output "control_plane_instance_id" {
  value = aws_instance.control_plane.id
}

output "node_security_group_id" {
  value = aws_security_group.node.id
}

output "worker_asg_name" {
  value = aws_autoscaling_group.worker.name
}
