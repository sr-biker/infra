output "pipeline_name" {
  value = module.cicd.pipeline_name
}

output "github_connection_arn" {
  value = module.cicd.github_connection_arn
}

output "github_connection_status" {
  value = module.cicd.github_connection_status
}

output "membership_pipeline_name" {
  value = module.cicd_membership.pipeline_name
}

output "membership_github_connection_arn" {
  value = module.cicd_membership.github_connection_arn
}

output "membership_github_connection_status" {
  value = module.cicd_membership.github_connection_status
}
