output "pipeline_name" {
  value = aws_codepipeline.this.name
}

output "github_connection_arn" {
  value = local.codestar_connection_arn
}

output "github_connection_status" {
  value = try(aws_codestarconnections_connection.github[0].connection_status, "REUSED")
}

output "artifact_bucket" {
  value = aws_s3_bucket.artifacts.bucket
}

output "evals_project_name" {
  value = try(aws_codebuild_project.evals[0].name, null)
}
