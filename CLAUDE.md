# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

This repo provisions a self-managed Kubernetes cluster on EC2 (no EKS) using **Terragrunt** (on top
of Terraform). Application workloads are deployed with Helm charts. The stack consists of:

- API Gateway (public entry point)
- Private ALB + target group (routes traffic to the Kubernetes worker nodes)
- EC2 worker nodes running Kubernetes (control plane + workers, self-managed — not EKS)

The repo is currently in early/scaffolding stage — no Terragrunt modules or Helm charts have been
committed yet beyond IDE project files.

## Environments

- **dev** — runs locally (not deployed to AWS)
- **prod** — deployed to AWS

Expect a standard Terragrunt layout with per-environment directories (e.g. `dev/`, `prod/` or
`environments/dev`, `environments/prod`), each with its own `terragrunt.hcl` pointing at shared
Terraform modules.

## State Locking

State locking uses **S3** (not DynamoDB). Since S3-native locking is used, this implies a Terraform/
Terragrunt version with S3 conditional-write locking support — check the configured provider/
Terragrunt versions once the backend config is committed, rather than assuming a DynamoDB lock table
exists.

## Notes for Future Work

- Since this is not EKS, expect Terraform/Terragrunt to handle kubeadm-style cluster bootstrapping
  (or an equivalent self-managed install) on the EC2 instances directly, rather than relying on
  AWS-managed control plane resources.
- The ALB is private, fronted by API Gateway — check how the two are wired (VPC Link vs. other
  integration) once that part of the stack is built, since it affects how routes/target groups are
  defined.
- The dev environment running locally (rather than against real AWS resources) implies either
  LocalStack, a local k8s tool (kind/minikube), or some other local emulation — check how `dev/`
  is actually wired once it exists, don't assume it mirrors `prod/` 1:1.
- Keep Terragrunt/Terraform (infra provisioning) and Helm charts (Kubernetes workload deployment)
  in clearly separated directories as the repo grows.
