output "pipeline_name" {
  value = aws_codepipeline.this.name
}

output "github_connection_arn" {
  value = aws_codestarconnections_connection.github.arn
}

output "github_connection_status" {
  value = aws_codestarconnections_connection.github.connection_status
}

output "artifact_bucket" {
  value = aws_s3_bucket.artifacts.bucket
}
