output "vpc_id" {
  value = aws_vpc.this.id
}

output "db_instance_id" {
  value = aws_db_instance.postgres.id
}

output "db_instance_arn" {
  value = aws_db_instance.postgres.arn
}

output "db_instance_endpoint" {
  value = aws_db_instance.postgres.endpoint
}

output "db_instance_address" {
  value = aws_db_instance.postgres.address
}

output "master_user_secret_arn" {
  value = aws_db_instance.postgres.master_user_secret[0].secret_arn
}

output "security_group_id" {
  value = aws_security_group.db.id
}
