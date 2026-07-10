# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

This repo provisions a self-managed Kubernetes cluster on EC2 (no EKS) using **Terragrunt** (on top
of Terraform). Application workloads are deployed with Helm charts. The stack consists of:

- API Gateway (`aws_apigatewayv2` HTTP API, public entry point)
- VPC Link → private ALB → target group (NodePort on worker instances)
- EC2 worker nodes running Kubernetes, bootstrapped with `kubeadm` (self-managed — not EKS)

## Layout

```
terragrunt.hcl              # root: S3 remote state (S3-native locking, no DynamoDB) + provider generation
modules/
  vpc/                       # VPC, public/private subnets, IGW, single NAT gateway
  k8s-nodes/                 # control-plane EC2 instance + worker ASG, kubeadm bootstrap via user_data,
                              # join command handed off through SSM Parameter Store
  alb/                       # private ALB + target group (NodePort 30080) attached to the worker ASG
  api-gateway/                # HTTP API + VPC Link fronting the private ALB
live/
  prod/                      # only real Terragrunt environment; env.hcl + one dir per module
    env.hcl
    vpc/terragrunt.hcl
    k8s-nodes/terragrunt.hcl
    alb/terragrunt.hcl
    api-gateway/terragrunt.hcl
  dev/                       # NOT Terragrunt-managed — local kind cluster, see live/dev/README.md
    kind-config.yaml
helm/                        # workload charts, one dir per chart, values-dev.yaml / values-prod.yaml
```

## Environments

- **dev** — local only. `live/dev/kind-config.yaml` spins up a `kind` cluster approximating the prod
  topology (control-plane + 2 workers, ingress NodePort mapped to the host). No AWS calls, no
  Terragrunt unit — see `live/dev/README.md`.
- **prod** — the only environment under Terragrunt, deployed to AWS `us-east-1`. Apply order is
  `vpc` → `k8s-nodes` → `alb` → `api-gateway` (enforced via Terragrunt `dependency` blocks with
  mock outputs for `plan`/`validate`).

## State & Locking

- Backend: S3, configured in root `terragrunt.hcl`, keyed per-module via `path_relative_to_include()`.
- Locking: S3-native (`use_lockfile = true`), **not** DynamoDB — requires Terraform ≥ 1.10.
- Bucket (`infra-tfstate-prod-us-east-1`, see `live/prod/env.hcl`) is bootstrapped by Terragrunt on
  first `apply`, not pre-created.

## Working on this repo

- Run Terragrunt from a `live/prod/<module>` directory, or `terragrunt run-all <cmd>` from `live/prod`
  to operate on the whole stack in dependency order.
- The `kubernetes_version`, instance types/counts, and CIDRs are all in `live/prod/env.hcl` — change
  them there, not in the modules.
- `modules/k8s-nodes` templates (`templates/*.sh.tpl`) use `$${...}` for literal shell variables and
  `${...}` for Terraform-interpolated values — keep that distinction when editing them.
- Any ingress controller deployed via Helm must listen on NodePort 30080 to match
  `modules/alb`'s `ingress_node_port` default and `live/dev/kind-config.yaml`'s port mapping.
