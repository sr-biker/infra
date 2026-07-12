output "db_instance_endpoint" {
  value = module.rds.db_instance_endpoint
}

output "db_instance_arn" {
  value = module.rds.db_instance_arn
}

output "master_user_secret_arn" {
  value = module.rds.master_user_secret_arn
}

output "security_group_id" {
  value = module.rds.security_group_id
}
