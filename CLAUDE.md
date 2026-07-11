# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

This repo provisions a self-managed Kubernetes cluster on EC2 (no EKS) using **Terragrunt** (on top
of **OpenTofu**, not HashiCorp Terraform). Application workloads are deployed with Helm charts. The
stack consists of:

- API Gateway (`aws_apigatewayv2` HTTP API, public entry point)
- VPC Link → private ALB → target group (NodePort on worker instances)
- EC2 worker nodes running Kubernetes, bootstrapped with `kubeadm` (self-managed — not EKS)

## Layout

```
terragrunt.hcl              # root: OpenTofu engine (terraform_binary = "tofu"), S3 remote state
                              # (S3-native locking, no DynamoDB) + provider generation. Terragrunt's
                              # ONLY job in this repo — no module wiring, no dependency graph.
modules/
  vpc/                       # VPC, public/private subnets, IGW, single NAT gateway
  k8s-nodes/                 # control-plane EC2 instance + worker ASG, kubeadm bootstrap via user_data,
                              # join command handed off through SSM Parameter Store
  alb/                       # private ALB + target group (NodePort 30080) attached to the worker ASG
  api-gateway/                # HTTP API + VPC Link fronting the private ALB
  rds/                       # standalone PostgreSQL RDS instance + its own VPC, ported from
                              # ~/projects/cdk/stacks/rds_stack.py — see "rds module" below
prod/                        # only real Terragrunt environment; env.hcl + one dir per module
  env.hcl                    # environment/aws_region/state_bucket only, used by root terragrunt.hcl
  vpc/                       # terragrunt.hcl (just `include "root"`) + main.tf + outputs.tf
  k8s-nodes/                 # same shape; main.tf reads vpc's state via terraform_remote_state
  alb/                       # same shape; reads vpc + k8s-nodes state
  api-gateway/               # same shape; reads vpc + alb state
  rds/                       # same shape but no terraform_remote_state deps — self-contained
  cloudwatch-log-shipper.yaml # raw k8s manifest, not Terragrunt-managed — see "Log shipping" below
local/                       # NOT Terragrunt-managed — local kind cluster, see local/README.md
  kind-config.yaml
```

Per-app Helm charts live in the app's own repo, not here — e.g. `contacts-micro-service`'s chart is
at `~/projects/contacts-micro-service/helm/contacts-micro-service`.

## Environments

- **local** — local only, not AWS. `local/kind-config.yaml` spins up a `kind` cluster
  approximating the prod topology (control-plane + 2 workers, ingress NodePort mapped to the host).
  No AWS calls, no Terragrunt unit — see `local/README.md`. Deliberately *not* called `dev` —
  a real AWS `dev` account/environment may be provisioned separately later (possibly under a
  different AWS account than `prod`), and `local` would not be it.
- **prod** — the only environment under Terragrunt, deployed to AWS `us-east-1`.

### Module composition is plain OpenTofu, not Terragrunt

Each `prod/<unit>/terragrunt.hcl` does nothing but `include "root"` (to get the generated
`backend.tf`/`provider.tf`). The actual unit is a normal OpenTofu root module living alongside it:
`main.tf` calls the shared module from `modules/` with a `module` block, and pulls any other unit's
outputs via `data "terraform_remote_state"` (reading that unit's S3 state directly), not a Terragrunt
`dependency` block. This was a deliberate choice to keep module composition vendor-neutral — these
directories run under bare `tofu init/plan/apply` too, Terragrunt is only used here to avoid
hand-writing the same S3 backend block four times.

Consequence: there is no `dependency`-graph ordering or `run --all`. Apply in order by hand —
`vpc` → `k8s-nodes` → `alb` → `api-gateway` — each `cd`'d into and applied before the next one's
`terraform_remote_state` lookup will succeed. `plan`/`validate` on a downstream unit will fail with
"Unable to find remote state" until its upstream unit has been applied at least once; that's expected,
not a bug.
- Static config (CIDRs, instance types, `worker_count`, `kubernetes_version`, resource `name`) lives
  as variable **defaults** in each module's `variables.tf` — change it there, not by adding a
  Terragrunt input or a `main.tf` argument, unless a value needs to differ per unit.
- The S3 bucket/key/region literals inside each unit's `data "terraform_remote_state"` blocks are
  hand-duplicated (not generated) and must be kept in sync with `prod/env.hcl` if the bucket or
  region ever changes.

### rds module

`modules/rds` is a direct port of `~/projects/cdk/stacks/rds_stack.py` (a separate AWS CDK repo) —
not wired into the k8s stack. It provisions **its own** VPC (`10.1.0.0/16` by default, disjoint from
the k8s stack's `10.0.0.0/16`) with public/private/isolated subnet tiers, a single-AZ `db.t3.micro`
PostgreSQL instance in the isolated tier, RDS-managed credentials in Secrets Manager
(`manage_master_user_password`, replacing the CDK version's `Credentials.from_generated_secret`), and
an EventBridge Scheduler stop/start pair (`aws_scheduler_schedule`, replacing the CDK version's
`CfnSchedule`) that stops the DB nightly and starts it on weekday mornings.

This is a **cost-optimized, non-production** shape ported as-is from the source stack, not a
production DB config:
single-AZ, deletion protection off, `skip_final_snapshot = true`, and the whole instance goes offline
overnight/weekends via the scheduler. A production Postgres stack would instead want
`multi_az = true`, `deletion_protection = true`, no stop/start schedule, longer backup retention, and
Performance Insights on — none of that is here; add it deliberately if `rds` ever needs to hold real
prod data.

### Log shipping (prod)

`prod/cloudwatch-log-shipper.yaml` is a raw k8s manifest (not a Helm chart, not Terragrunt-managed
— applied directly with `kubectl` once the prod cluster is reachable) deploying `aws-for-fluent-bit` as
a **DaemonSet**, one pod per node, tailing every container's logs via kubelet's standard
`/var/log/containers/*.log` symlinks and shipping to CloudWatch Logs
(`/infra-prod/containers/<namespace>` log groups). DaemonSet was chosen over a per-pod sidecar since
the app already logs to stdout — a cluster-wide collector needs zero app-side changes and costs one pod
per node instead of one per app replica.

- Parser is `cri` (containerd's plain-text CRI log format), not `docker` (JSON format) — this cluster
  runs containerd (kubeadm default), not dockershim. Using the wrong parser silently fails to parse
  every log line.
- Credentials come from the EC2 instance profile (`modules/k8s-nodes`' `aws_iam_role.node` +
  the `cloudwatch_logs` policy added there, scoped to `log-group:/infra-prod/*`) — no
  IRSA/pod-identity exists here since this isn't EKS, so every pod on every node implicitly has
  whatever that role grants. Keep that policy scoped tight; don't broaden it to `logs:*`.
- Validated by deploying it to the local `kind` cluster: fluent-bit correctly parsed real container
  logs and built correct log-group/stream names, then failed only at the AWS-credentials step (no
  IMDS on `kind`) — expected, and confirms the config itself is correct. It is not left running in
  `local` (deleted after verification); this manifest is prod-only.

### CI/CD (prod)

`prod/cicd` provisions an AWS CodePipeline (`modules/cicd`) that builds `contacts-micro-service` and
deploys it to the running prod cluster: **Source** (GitHub via CodeStar Connections) → **Build**
(CodeBuild, `docker build`/push to the `contacts-micro-service` ECR repo created in
`modules/k8s-nodes`) → **Deploy** (CodeBuild, `aws ssm send-command` into the control-plane instance
running `kubectl set image deployment/contacts-micro-service ...` + `kubectl rollout status`).

- **One-time manual step required**: the `aws_codestarconnections_connection` is created in `PENDING`
  status — Terraform cannot complete a GitHub OAuth grant. Approve it once in the AWS Console
  (CodePipeline → Settings → Connections) before the pipeline can pull source.
- Both CodeBuild projects use `ARM_CONTAINER`/`amazonlinux2-aarch64-standard` — native arm64 builds
  matching the Graviton (`t4g`) worker nodes, no cross-compilation.
- The **deploy** stage assumes `deployment/contacts-micro-service` already exists in the cluster
  (`kubectl set image` updates an existing Deployment, it doesn't create one) — the first-ever deploy
  to `prod` still needs a manual `helm install` first; the pipeline handles updates after that.
- Deploy stage's IAM (`aws_iam_role.deploy` in `modules/cicd`) is scoped to `ssm:SendCommand` on
  exactly the control-plane instance ARN + the `AWS-RunShellScript` document ARN only — it cannot run
  commands on any other instance or via any other SSM document.
- Image tag = first 8 chars of the git commit SHA (`CODEBUILD_RESOLVED_SOURCE_VERSION`), plus a
  floating `:latest`. Both Build and Deploy stages compute this independently from their own
  `CODEBUILD_RESOLVED_SOURCE_VERSION` rather than passing it as a CodePipeline artifact/variable.

## State & Locking

- Backend: S3, configured in root `terragrunt.hcl`, keyed per-module via `path_relative_to_include()`.
- Locking: S3-native (`use_lockfile = true`), **not** DynamoDB — requires OpenTofu ≥ 1.10
  (or Terraform ≥ 1.10, but this repo pins to OpenTofu via `terraform_binary = "tofu"` in root
  `terragrunt.hcl`).
- Bucket (`infra-tfstate-prod-us-east-1`, see `prod/env.hcl`) is bootstrapped by Terragrunt on
  first `apply`, not pre-created.

## Working on this repo

- Requires the `tofu` (OpenTofu) CLI on PATH, in addition to `terragrunt` — Terragrunt is configured
  to invoke `tofu`, not `terraform`.
- Run Terragrunt (`terragrunt plan`/`apply`) from inside each `prod/<unit>` directory, one at a
  time, in dependency order (`vpc` → `k8s-nodes` → `alb` → `api-gateway`) — see "Module composition
  is plain OpenTofu, not Terragrunt" above. There is no `run --all`/`run-all` here.
- `prod/env.hcl` only holds Terragrunt-level concerns (`environment`, `aws_region`,
  `state_bucket`) used by the root `terragrunt.hcl` for the S3 backend/provider generation. Module
  config (`kubernetes_version`, instance types/counts, CIDRs, `name`) lives as defaults in each
  module's `variables.tf` instead — change it there.
- `modules/k8s-nodes` templates (`templates/*.sh.tpl`) use `$${...}` for literal shell variables and
  `${...}` for OpenTofu-interpolated values — keep that distinction when editing them.
- Any ingress controller deployed via Helm must listen on NodePort 30080 to match
  `modules/alb`'s `ingress_node_port` default and `local/kind-config.yaml`'s port mapping.
