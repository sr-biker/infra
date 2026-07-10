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
live/
  prod/                      # only real Terragrunt environment; env.hcl + one dir per module
    env.hcl                  # environment/aws_region/state_bucket only, used by root terragrunt.hcl
    vpc/                     # terragrunt.hcl (just `include "root"`) + main.tf + outputs.tf
    k8s-nodes/               # same shape; main.tf reads vpc's state via terraform_remote_state
    alb/                     # same shape; reads vpc + k8s-nodes state
    api-gateway/             # same shape; reads vpc + alb state
  dev/                       # NOT Terragrunt-managed — local kind cluster, see live/dev/README.md
    kind-config.yaml
helm/                        # workload charts, one dir per chart, values-dev.yaml / values-prod.yaml
```

## Environments

- **dev** — local only. `live/dev/kind-config.yaml` spins up a `kind` cluster approximating the prod
  topology (control-plane + 2 workers, ingress NodePort mapped to the host). No AWS calls, no
  Terragrunt unit — see `live/dev/README.md`.
- **prod** — the only environment under Terragrunt, deployed to AWS `us-east-1`.

### Module composition is plain OpenTofu, not Terragrunt

Each `live/prod/<unit>/terragrunt.hcl` does nothing but `include "root"` (to get the generated
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
  hand-duplicated (not generated) and must be kept in sync with `live/prod/env.hcl` if the bucket or
  region ever changes.

## State & Locking

- Backend: S3, configured in root `terragrunt.hcl`, keyed per-module via `path_relative_to_include()`.
- Locking: S3-native (`use_lockfile = true`), **not** DynamoDB — requires OpenTofu ≥ 1.10
  (or Terraform ≥ 1.10, but this repo pins to OpenTofu via `terraform_binary = "tofu"` in root
  `terragrunt.hcl`).
- Bucket (`infra-tfstate-prod-us-east-1`, see `live/prod/env.hcl`) is bootstrapped by Terragrunt on
  first `apply`, not pre-created.

## Working on this repo

- Requires the `tofu` (OpenTofu) CLI on PATH, in addition to `terragrunt` — Terragrunt is configured
  to invoke `tofu`, not `terraform`.
- Run Terragrunt (`terragrunt plan`/`apply`) from inside each `live/prod/<unit>` directory, one at a
  time, in dependency order (`vpc` → `k8s-nodes` → `alb` → `api-gateway`) — see "Module composition
  is plain OpenTofu, not Terragrunt" above. There is no `run --all`/`run-all` here.
- `live/prod/env.hcl` only holds Terragrunt-level concerns (`environment`, `aws_region`,
  `state_bucket`) used by the root `terragrunt.hcl` for the S3 backend/provider generation. Module
  config (`kubernetes_version`, instance types/counts, CIDRs, `name`) lives as defaults in each
  module's `variables.tf` instead — change it there.
- `modules/k8s-nodes` templates (`templates/*.sh.tpl`) use `$${...}` for literal shell variables and
  `${...}` for OpenTofu-interpolated values — keep that distinction when editing them.
- Any ingress controller deployed via Helm must listen on NodePort 30080 to match
  `modules/alb`'s `ingress_node_port` default and `live/dev/kind-config.yaml`'s port mapping.
