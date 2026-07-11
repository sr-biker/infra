data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# --- artifact bucket ---
resource "aws_s3_bucket" "artifacts" {
  bucket        = "${var.name}-cicd-artifacts-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # pipeline artifacts, not data worth protecting from accidental deletion
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- source: GitHub via CodeStar Connections ---
# Created in PENDING status — must be approved once, manually, in the AWS Console
# (CodePipeline > Settings > Connections) before the pipeline can pull source. Terraform
# cannot complete a GitHub OAuth grant on your behalf.
resource "aws_codestarconnections_connection" "github" {
  name          = "${var.name}-github"
  provider_type = "GitHub"
}

# --- IAM: CodePipeline ---
resource "aws_iam_role" "pipeline" {
  name = "${var.name}-cicd-pipeline"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codepipeline.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "pipeline" {
  name = "${var.name}-cicd-pipeline"
  role = aws_iam_role.pipeline.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:GetBucketVersioning"]
        Resource = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = "codestar-connections:UseConnection"
        Resource = aws_codestarconnections_connection.github.arn
      },
      {
        Effect   = "Allow"
        Action   = ["codebuild:StartBuild", "codebuild:BatchGetBuilds"]
        Resource = [aws_codebuild_project.build.arn, aws_codebuild_project.deploy.arn]
      },
    ]
  })
}

# --- IAM: CodeBuild (build stage — docker build + push to ECR) ---
resource "aws_iam_role" "build" {
  name = "${var.name}-cicd-build"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "build" {
  name = "${var.name}-cicd-build"
  role = aws_iam_role.build.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${var.name}-*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "${aws_s3_bucket.artifacts.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
        ]
        Resource = var.ecr_repository_arn
      },
    ]
  })
}

# --- IAM: CodeBuild (deploy stage — SSM into the control plane, kubectl set image) ---
resource "aws_iam_role" "deploy" {
  name = "${var.name}-cicd-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "deploy" {
  name = "${var.name}-cicd-deploy"
  role = aws_iam_role.deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${var.name}-*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "${aws_s3_bucket.artifacts.arn}/*"
      },
      {
        # Scoped to exactly one instance and one document — this role can run shell
        # commands ONLY on the control-plane instance, via ONLY the standard shell-script
        # document, not arbitrary instances/documents.
        Effect = "Allow"
        Action = "ssm:SendCommand"
        Resource = [
          "arn:aws:ec2:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:instance/${var.control_plane_instance_id}",
          "arn:aws:ssm:${data.aws_region.current.region}::document/AWS-RunShellScript",
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:GetCommandInvocation", "ssm:ListCommandInvocations"]
        Resource = "*"
      },
    ]
  })
}

# --- CodeBuild: build (docker build + push) ---
resource "aws_codebuild_project" "build" {
  name         = "${var.name}-build"
  service_role = aws_iam_role.build.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    # arm64 to match the Graviton (t4g) worker nodes — native build, no cross-compilation.
    type                        = "ARM_CONTAINER"
    image                       = "aws/codebuild/amazonlinux2-aarch64-standard:3.0"
    compute_type                = "BUILD_GENERAL1_SMALL"
    privileged_mode             = true # required for `docker build`
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "REPO_URI"
      value = var.ecr_repository_url
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = <<-YAML
      version: 0.2
      phases:
        pre_build:
          commands:
            - aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $REPO_URI
            - IMAGE_TAG=$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | cut -c1-8)
            - echo "Building $REPO_URI:$IMAGE_TAG"
        build:
          commands:
            - docker build -t $REPO_URI:$IMAGE_TAG -t $REPO_URI:latest .
        post_build:
          commands:
            - docker push $REPO_URI:$IMAGE_TAG
            - docker push $REPO_URI:latest
    YAML
  }
}

# --- CodeBuild: deploy (SSM into control plane, kubectl set image) ---
resource "aws_codebuild_project" "deploy" {
  name         = "${var.name}-deploy"
  service_role = aws_iam_role.deploy.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    type                        = "ARM_CONTAINER"
    image                       = "aws/codebuild/amazonlinux2-aarch64-standard:3.0"
    compute_type                = "BUILD_GENERAL1_SMALL"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "REPO_URI"
      value = var.ecr_repository_url
    }
    environment_variable {
      name  = "CONTROL_PLANE_ID"
      value = var.control_plane_instance_id
    }
    environment_variable {
      name  = "K8S_DEPLOYMENT"
      value = var.k8s_deployment_name
    }
    environment_variable {
      name  = "K8S_CONTAINER"
      value = var.k8s_container_name
    }
    environment_variable {
      name  = "K8S_NAMESPACE"
      value = var.k8s_namespace
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = <<-YAML
      version: 0.2
      phases:
        build:
          commands:
            - IMAGE_TAG=$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | cut -c1-8)
            - echo "Deploying $REPO_URI:$IMAGE_TAG to deployment/$K8S_DEPLOYMENT"
            - |
              CMD_ID=$(aws ssm send-command \
                --instance-ids "$CONTROL_PLANE_ID" \
                --document-name "AWS-RunShellScript" \
                --parameters "commands=[\"export KUBECONFIG=/root/.kube/config\",\"kubectl set image deployment/$K8S_DEPLOYMENT $K8S_CONTAINER=$REPO_URI:$IMAGE_TAG -n $K8S_NAMESPACE\",\"kubectl rollout status deployment/$K8S_DEPLOYMENT -n $K8S_NAMESPACE --timeout=180s\"]" \
                --region "$AWS_DEFAULT_REGION" \
                --query 'Command.CommandId' --output text)
            - echo "SSM command: $CMD_ID"
            - |
              for i in $(seq 1 30); do
                CMD_STATUS=$(aws ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$CONTROL_PLANE_ID" --region "$AWS_DEFAULT_REGION" --query 'Status' --output text 2>/dev/null || echo Pending)
                echo "SSM command status: $CMD_STATUS"
                if [ "$CMD_STATUS" = "Success" ]; then break; fi
                if [ "$CMD_STATUS" = "Failed" ] || [ "$CMD_STATUS" = "Cancelled" ] || [ "$CMD_STATUS" = "TimedOut" ]; then
                  echo "--- stdout ---"
                  aws ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$CONTROL_PLANE_ID" --region "$AWS_DEFAULT_REGION" --query 'StandardOutputContent' --output text
                  echo "--- stderr ---"
                  aws ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$CONTROL_PLANE_ID" --region "$AWS_DEFAULT_REGION" --query 'StandardErrorContent' --output text
                  exit 1
                fi
                sleep 10
              done
              if [ "$CMD_STATUS" != "Success" ]; then echo "Timed out waiting for SSM command"; exit 1; fi
              aws ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$CONTROL_PLANE_ID" --region "$AWS_DEFAULT_REGION" --query 'StandardOutputContent' --output text
    YAML
  }
}

# --- pipeline ---
resource "aws_codepipeline" "this" {
  name     = "${var.name}-contacts-micro-service"
  role_arn = aws_iam_role.pipeline.arn

  artifact_store {
    type     = "S3"
    location = aws_s3_bucket.artifacts.bucket
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["SourceOutput"]

      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.github.arn
        FullRepositoryId = "${var.github_owner}/${var.github_repo}"
        BranchName       = var.github_branch
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["SourceOutput"]
      output_artifacts = ["BuildOutput"]

      configuration = {
        ProjectName = aws_codebuild_project.build.name
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "Deploy"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["SourceOutput"]

      configuration = {
        ProjectName = aws_codebuild_project.deploy.name
      }
    }
  }
}
