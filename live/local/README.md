# local environment

`local` does not touch AWS. It's a local [kind](https://kind.sigs.k8s.io/) cluster standing in for
the prod EC2/kubeadm cluster, so Helm charts under `helm/` can be developed and tested without a real
API Gateway / ALB / EC2 stack. (Named `local`, not `dev`, since a real AWS `dev` account/environment
may be provisioned separately later — this directory would not be it.)

## Usage

```bash
kind create cluster --name infra-local --config kind-config.yaml
kubectl cluster-info --context kind-infra-local

# Postgres — required by contacts-micro-service's values-local.yaml (db.host: postgres)
kubectl apply -f postgres.yaml
kubectl rollout status deployment/postgres

# build the app image and load it into kind's nodes (kind can't pull from a local docker
# daemon on its own — images must be built + loaded explicitly)
docker build -t contacts-micro-service-app:latest ~/projects/contacts-micro-service
kind load docker-image contacts-micro-service-app:latest --name infra-local

# install workloads
helm upgrade --install contacts ../../helm/contacts-micro-service -f ../../helm/contacts-micro-service/values-local.yaml
kubectl rollout status deployment/contacts-micro-service

# no ingress controller is installed yet, so there's nothing listening on the NodePort
# 30080 -> host 8080 mapping in kind-config.yaml — reach the app via port-forward instead:
kubectl port-forward svc/contacts-micro-service 8080:8080
curl http://localhost:8080/api/contacts

# teardown
kind delete cluster --name infra-local
```

There is no Terragrunt unit for `local` — nothing here is AWS-managed state, so it isn't part of the
`live/` Terragrunt tree. `prod` is the only environment under Terragrunt.
