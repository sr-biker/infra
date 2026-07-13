# local environment

`local` does not touch AWS. It's a local [kind](https://kind.sigs.k8s.io/) cluster standing in for
the prod EC2/kubeadm cluster, so Helm charts under `helm/` can be developed and tested without a real
API Gateway / ALB / EC2 stack. (Named `local`, not `dev`, since a real AWS `dev` account/environment
may be provisioned separately later — this directory would not be it.)

## Usage

```bash
kind create cluster --name infra-local --config kind-config.yaml
kubectl cluster-info --context kind-infra-local

# This machine may have other kind/minikube clusters/contexts around (from unrelated work).
# Pin the context explicitly on every command below rather than relying on whatever
# `kubectl config current-context` happens to be — it can drift out from under you.
KCTX=kind-infra-local

# App workloads go in their own namespace, not "default" -- matches prod (see infra's
# CLAUDE.md/README for prod's namespace layout).
kubectl --context $KCTX create namespace senthil-apis

# ingress-nginx, bound to NodePort 30080 — mirrors modules/alb's ingress_node_port, which
# is what a real prod ALB target group forwards to. This is what makes `curl localhost:8080`
# (kind-config.yaml's hostPort mapping) exercise the same path prod's ALB would: NodePort ->
# ingress controller -> Ingress -> Service -> pod, not just a kubectl port-forward shortcut.
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx --kube-context $KCTX \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.type=NodePort \
  --set controller.service.nodePorts.http=30080 \
  --set controller.hostPort.enabled=false \
  --set controller.watchIngressWithoutClass=true
kubectl --context $KCTX -n ingress-nginx rollout status deployment/ingress-nginx-controller

# Postgres — required by contacts-micro-service's values-local.yaml (db.host: postgres),
# and by membership's (same host, both apps share it locally the same way they share the
# real RDS instance in prod, just as separate databases).
kubectl --context $KCTX -n senthil-apis apply -f postgres.yaml
kubectl --context $KCTX -n senthil-apis rollout status deployment/postgres

# build the app images and load them into kind's nodes (kind can't pull from a local
# docker daemon on its own — images must be built + loaded explicitly)
docker build -t contacts-micro-service-app:latest ~/projects/contacts-micro-service
kind load docker-image contacts-micro-service-app:latest --name infra-local
docker build -t membership-app:latest ~/projects/membership
kind load docker-image membership-app:latest --name infra-local

# install workloads — charts live in each app's own repo, not here
# (values-local.yaml sets ingress.enabled: true)
helm upgrade --install contacts ~/projects/contacts-micro-service/helm/contacts-micro-service \
  -f ~/projects/contacts-micro-service/helm/contacts-micro-service/values-local.yaml \
  --namespace senthil-apis --kube-context $KCTX
kubectl --context $KCTX -n senthil-apis rollout status deployment/contacts-micro-service

helm upgrade --install membership ~/projects/membership/helm/membership \
  -f ~/projects/membership/helm/membership/values-local.yaml \
  --namespace senthil-apis --kube-context $KCTX
kubectl --context $KCTX -n senthil-apis rollout status deployment/membership

# reachable the same way a real ALB would reach it in prod:
curl http://localhost:8080/api/contacts
curl http://localhost:8080/api/memberships

# teardown
kind delete cluster --name infra-local
```

There is no Terragrunt unit for `local` — nothing here is AWS-managed state, so it isn't part of the
`live/` Terragrunt tree. `prod` is the only environment under Terragrunt.
