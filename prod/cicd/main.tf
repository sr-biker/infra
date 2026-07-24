module "cicd" {
  source = "../../modules/cicd"

  pipeline_name      = "customer-api-pipeline"
  ecr_repository_url = data.terraform_remote_state.k8s_nodes.outputs.contacts_micro_service_ecr_repository_url
  ecr_repository_arn = data.terraform_remote_state.k8s_nodes.outputs.contacts_micro_service_ecr_repository_arn
}

module "cicd_membership" {
  source = "../../modules/cicd"

  # Distinct var.name -- every other resource in the module (artifact bucket, GitHub
  # connection, IAM roles, CodeBuild project) is prefixed with this, so it must differ
  # from the default "infra-prod" to avoid colliding with the contacts-micro-service
  # instance above.
  name             = "infra-prod-membership"
  pipeline_name    = "membership-pipeline"
  github_repo      = "membership-ms"
  values_file_path = "helm/membership/values-prod.yaml"

  # Reuse the connection created for contacts-micro-service -- one CodeStarConnections
  # connection authorizes the whole sr-biker GitHub account, so a second per-app connection
  # (and its manual console approval) isn't needed.
  codestar_connection_arn = module.cicd.github_connection_arn

  ecr_repository_url = data.terraform_remote_state.k8s_nodes.outputs.membership_ecr_repository_url
  ecr_repository_arn = data.terraform_remote_state.k8s_nodes.outputs.membership_ecr_repository_arn
}

module "cicd_studio_chatbot" {
  source = "../../modules/cicd"

  name             = "infra-prod-studio-chatbot"
  pipeline_name    = "studio-chatbot-pipeline"
  github_repo      = "studio-chatbot"
  values_file_path = "helm/values-prod.yaml"

  codestar_connection_arn = module.cicd.github_connection_arn

  ecr_repository_url = data.terraform_remote_state.k8s_nodes.outputs.studio_chatbot_ecr_repository_url
  ecr_repository_arn = data.terraform_remote_state.k8s_nodes.outputs.studio_chatbot_ecr_repository_arn

  # Existing secret (arn:aws:secretsmanager:us-east-1:605448157849:secret:prod/open-ai-bIXb8M),
  # JSON key/value with key == secret name, same convention as github_token_secret_name.
  openai_api_key_secret_name = "prod/open-ai"

  # Only pipeline instance with an evals suite to gate on today -- see
  # modules/cicd/variables.tf's enable_evals_gate. Blocks Build (and its ECR push) behind a
  # passing run of studio-chatbot's RAGAS + router + LLM-judge evals against a throwaway
  # pgvector container, using the checked-in evals/fixtures/faq.md (data/faq.md itself is
  # gitignored -- local-dev-only, see app/faq_loader.py) so the suite has deterministic FAQ
  # content to ingest and grade against without needing live Google Drive credentials in CI.
  enable_evals_gate = true

  evals_buildspec = <<-YAML
    version: 0.2
    phases:
      install:
        commands:
          - apt-get update -y
          - apt-get install -y --no-install-recommends docker.io postgresql-client git
          - pip install -q -r requirements.txt -r requirements-evals.txt
      pre_build:
        commands:
          # storage-driver=vfs -- this image isn't CodeBuild's own docker-enabled runtime, so
          # overlay2 isn't available in this nested-container environment; vfs is slower but
          # works anywhere. Logs to a file (not the build's stdout) since dockerd is noisy,
          # and the longer timeout/retry gives the daemon room to actually come up instead of
          # failing on first sleep tick like the previous 30s attempt did.
          - export DOCKER_HOST=unix:///var/run/docker.sock
          - dockerd --storage-driver=vfs -H "$DOCKER_HOST" > /tmp/dockerd.log 2>&1 &
          # privileged_mode CodeBuild environments can pre-set DOCKER_HOST to their own
          # docker-in-docker endpoint -- pinning it above to the socket dockerd was just told
          # to listen on is what makes this `docker info` check reach the daemon we started,
          # rather than polling forever against a different (unlistening) endpoint.
          - timeout 90 sh -c 'until docker info >/dev/null 2>&1; do sleep 2; done' || (cat /tmp/dockerd.log; exit 1)
          - >-
            docker run -d --name pgvector-eval -p 5432:5432
            -e POSTGRES_USER=studio -e POSTGRES_PASSWORD=studio -e POSTGRES_DB=studio
            pgvector/pgvector:pg16
          - timeout 60 sh -c 'until PGPASSWORD=studio psql -h 127.0.0.1 -U studio -d studio -c "\q" 2>/dev/null; do sleep 2; done'
          - PGPASSWORD=studio psql -h 127.0.0.1 -U studio -d studio -c 'CREATE EXTENSION IF NOT EXISTS vector;'
          - cp evals/fixtures/faq.md data/faq.md
          - APP_PROFILE=local DB_HOST=127.0.0.1 DB_PORT=5432 DB_NAME=studio DB_USER=studio DB_PASSWORD=studio python scripts/ingest_faq.py
      build:
        commands:
          - >-
            APP_PROFILE=local DB_HOST=127.0.0.1 DB_PORT=5432 DB_NAME=studio DB_USER=studio DB_PASSWORD=studio
            RUN_RAGAS_EVALS=1 RUN_ROUTER_EVALS=1 RUN_LLM_JUDGE_EVALS=1
            pytest evals/ -q
      post_build:
        commands:
          - docker rm -f pgvector-eval || true
    cache:
      paths:
        # Zipped to/from the module's cache.location S3 prefix around each build -- this is
        # what makes repeat "pip install" runs fast and quiet, the same role Maven's local
        # .m2 repo plays for repeat `mvn` builds.
        - /root/.cache/pip/**/*
  YAML
}
