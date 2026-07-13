# infra

Provisions a self-managed Kubernetes cluster on EC2 (no EKS) on AWS, and is the root of the deploy
path for every application workload that runs on it. This is the repo to start from to understand how
the whole system fits together — see `CLAUDE.md` for the detailed layout/module breakdown.

## What this repo owns

- **Networking & cluster**: VPC, `kubeadm`-bootstrapped control-plane + worker ASG (Graviton/AL2023),
  private ALB, API Gateway HTTP API fronting it (`modules/vpc`, `modules/k8s-nodes`, `modules/alb`,
  `modules/api-gateway`), provisioned via Terragrunt-wrapped OpenTofu (`prod/`).
- **Shared data store**: a single PostgreSQL RDS instance (`modules/rds`) in the cluster's own VPC,
  reused by every app below (one database per app on the instance, not one instance per app).
- **Per-app ECR repos + node IAM**: `modules/k8s-nodes` also owns one ECR repository per app
  (`contacts-micro-service`, `membership`) and the node role's `ecr_pull`/`db_secret_read` policies
  they need.
- **Argo CD** (installed manually via SSM onto the control-plane, not Terraform-managed — see
  `CLAUDE.md`): the GitOps controller that actually deploys workloads. Terragrunt/OpenTofu has no
  network path to the private cluster API server, so nothing past "the cluster exists" is provisioned
  from here — see "Why apps aren't deployed from this repo" below.
- **Keycloak** (`helm/keycloak`, deployed via Argo CD like the apps below — this is the one exception
  to "app charts live in the app's own repo," since it's platform/cluster infra, not an application
  with its own source): dev-mode, in-memory H2, realm/client/user config re-imported from a
  checked-in `realm-export.json` on every restart. Issues the JWTs `contacts-micro-service`/
  `membership` validate for their write endpoints — see those repos' READMEs.
- **CI**: `prod/cicd` provisions one CodePipeline per app (`customer-api-pipeline` for
  `contacts-micro-service`, `membership-pipeline` for `membership`; see `modules/cicd`) — each just
  `Source` → `Build` (docker build + push to that app's ECR repo). No Deploy stage: Argo CD's
  `selfHeal` would just revert a `kubectl set image` step the moment it ran, since git
  (`values-prod.yaml`'s `image.tag`) is the actual desired-state source of truth. "Deploy" here means
  bumping that file and pushing, same as this repo's own tag-bump commits.

## What this repo does NOT own

Application source, Dockerfiles, and Helm charts live in each app's own repo, not here:

| App repo | What it is | Namespace | Deployed as |
|---|---|---|---|
| [`contacts-micro-service`](https://github.com/sr-biker/-contacts-micro-service) | Spring Boot + Postgres contacts REST service | `senthil-apis` | Argo CD `Application` `contacts-micro-service`, path `/` on the shared ingress |
| [`membership`](https://github.com/sr-biker/membership-ms) | Spring Boot + Postgres membership (classes: yoga/pilates/strength; schedules: daily/weekly) REST service | `senthil-apis` | Argo CD `Application` `membership`, path `/api/memberships` on the shared ingress |

Both apps share one namespace (`senthil-apis`), not `default` — namespaces here are purely a logical/
naming/RBAC boundary, not a network or scheduling isolation one (see "Adding a new app" below for the
resource-naming pitfall that sharing a namespace across two Helm releases can cause). Keycloak lives in
its own namespace, `senthil-auth`, deployed via this repo's own `helm/keycloak` chart.

Both apps protect their write endpoints (`POST`/`PUT`/`DELETE`) with JWTs issued by Keycloak — `GET`
and `/actuator/**` stay open. See each app repo's README for how that's wired (Spring Security OAuth2
resource server, off by default in local `docker-compose`, on in `kind`/prod).

Each app repo's Helm chart is rendered **directly** by Argo CD (`spec.source.helm.valueFiles` pointing
at that repo's `values-prod.yaml`) — there is no intermediate "rendered manifests" repo. (An earlier
`contacts-ms-manifests` repo did that job via pre-rendered, committed YAML; it was retired once Argo CD
switched to rendering Helm directly, and has since been deleted.)

## Why apps aren't deployed from this repo

Terraform/Terragrunt has no network path to the cluster's private API server (no bastion, no VPN, no
public endpoint) — it can create EC2 instances and IAM roles, but it cannot `kubectl apply` anything.
All cluster-level actions go through **SSM Session Manager** onto the control-plane instance, and
ongoing app deployment is delegated entirely to **Argo CD** (GitOps: each app repo's `main` branch is
the source of truth for what's running; Argo CD auto-syncs and self-heals). This repo's job ends at
"the cluster and its shared infra (VPC/RDS/ECR/IAM) exist" — it does not, and structurally cannot,
reach into the cluster to deploy workloads directly.

## Adding a new app to the cluster

1. Add an `aws_ecr_repository` + `aws_ecr_lifecycle_policy` for it in `modules/k8s-nodes/main.tf`
   (extend the node role's `ecr_pull` policy `Resource` list too), `terragrunt apply` in
   `prod/k8s-nodes`.
2. If it needs the shared Postgres instance: create its database via `psql` over SSM (one-time, same
   pattern as `contact`/`membership`) — the node's `db_secret_read` IAM policy already covers the
   shared `/rds/postgres/credentials` secret, no new secret needed unless the app needs different
   credentials.
3. Build + push its image to the new ECR repo (arm64 — matches the Graviton nodes).
4. Add an Argo CD `Application` (via SSM, `kubectl apply`) pointing at the app repo's Helm chart, with
   `destination.namespace: senthil-apis` and a distinct `ingress.path` so it doesn't collide with `/`
   (owned by `contacts-micro-service`).

See `CLAUDE.md` for the detailed rationale behind each of these steps (ECR credential provider gap,
no IRSA, RDS-in-same-VPC, etc.) and known pitfalls: Helm `releaseName` must be pinned explicitly in the
`Application`, or Argo CD's default-to-Application-name release name will produce
`app.kubernetes.io/instance` labels that don't match what a manual `helm template` test used, causing
a perpetual `OutOfSync`; and since every app's chart shares the `senthil-apis` namespace, any
chart-internal resource name that isn't prefixed with the app's own name (e.g. a bare
`ecr-registry-refresh` CronJob/ServiceAccount/Role/RoleBinding, not `<app>-ecr-registry-refresh`) will
collide with another app's identically-named resource — Argo CD will fight the two `Application`s over
ownership of the same object instead of erroring loudly.

## Environments

- **local** — `kind` cluster, not AWS. See `local/README.md`.
- **prod** — the only environment under Terragrunt, AWS `us-east-1`.
