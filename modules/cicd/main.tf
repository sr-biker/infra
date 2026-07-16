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
#
# One CodeStarConnections connection authorizes an AWS account against a GitHub account/org
# (not a single repo), so every pipeline instance in this account can reuse the same
# connection instead of each needing its own manual approval -- pass an existing
# connection's ARN via codestar_connection_arn to reuse it; leave unset to create a new one.
resource "aws_codestarconnections_connection" "github" {
  count = var.codestar_connection_arn == null ? 1 : 0

  name          = "${var.name}-github"
  provider_type = "GitHub"
}

locals {
  codestar_connection_arn = coalesce(var.codestar_connection_arn, try(aws_codestarconnections_connection.github[0].arn, null))
}

# Existing secret holding a GitHub PAT used by the Build stage to push the image-tag bump
# commit -- see variables.tf for the "not Terraform-managed" note.
data "aws_secretsmanager_secret" "github_token" {
  name = var.github_token_secret_name
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
        Resource = local.codestar_connection_arn
      },
      {
        Effect   = "Allow"
        Action   = ["codebuild:StartBuild", "codebuild:BatchGetBuilds"]
        Resource = [aws_codebuild_project.build.arn]
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
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = data.aws_secretsmanager_secret.github_token.arn
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

    environment_variable {
      name  = "VALUES_FILE"
      value = var.values_file_path
    }

    environment_variable {
      name  = "GH_OWNER"
      value = var.github_owner
    }

    environment_variable {
      name  = "GH_REPO"
      value = var.github_repo
    }

    environment_variable {
      name  = "GH_BRANCH"
      value = var.github_branch
    }

    # SECRETS_MANAGER type: CodeBuild injects the secret's plaintext value at build time,
    # never written to the buildspec or logs. The secret was created as a JSON key/value
    # pair (key == the secret's own name) rather than a plain string, so the json-key
    # suffix is required -- otherwise CodeBuild injects the whole JSON blob verbatim.
    environment_variable {
      name  = "GITHUB_TOKEN"
      value = "${data.aws_secretsmanager_secret.github_token.name}:${var.github_token_secret_name}"
      type  = "SECRETS_MANAGER"
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
            # Bump the Helm chart's values-prod.yaml with the new tag and push -- this is
            # the actual "deploy trigger": Argo CD (selfHeal, watching this repo/branch)
            # picks up the change and rolls it out, no kubectl/Deploy stage needed here.
            # Cloned fresh (rather than reusing CODEBUILD_SRC_DIR) because the
            # CodeStarSourceConnection source action hands CodeBuild a plain file export,
            # not a git checkout with .git metadata to commit against.
            - rm -rf /tmp/gitops-repo
            - git clone --depth 1 --branch $GH_BRANCH https://x-access-token:$GITHUB_TOKEN@github.com/$GH_OWNER/$GH_REPO.git /tmp/gitops-repo
            - cd /tmp/gitops-repo
            - sed -i "s|^\(\s*tag:\s*\).*|\1$IMAGE_TAG|" $VALUES_FILE
            - git config user.name "cicd-bot"
            - git config user.email "cicd-bot@infra.local"
            - git commit -am "Bump prod image tag to $IMAGE_TAG (automated)" || echo "no changes to commit"
            - git push origin HEAD:$GH_BRANCH
    YAML
  }
}

# --- pipeline ---
resource "aws_codepipeline" "this" {
  name          = var.pipeline_name
  role_arn      = aws_iam_role.pipeline.arn
  pipeline_type = "V2" # required for the trigger/git_configuration path filter below

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
        ConnectionArn    = local.codestar_connection_arn
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

  # Without this, the Build stage's own image-tag-bump commit (above) would push to the
  # same branch the Source stage watches, retriggering the pipeline forever. Excluding
  # pushes that only touch values_file_path breaks that loop at the trigger level, rather
  # than relying on a "[skip ci]"-style convention CodeStarSourceConnection doesn't support.
  trigger {
    provider_type = "CodeStarSourceConnection"

    git_configuration {
      source_action_name = "Source"

      push {
        branches {
          includes = [var.github_branch]
        }
        file_paths {
          excludes = [var.values_file_path]
        }
      }
    }
  }
}
