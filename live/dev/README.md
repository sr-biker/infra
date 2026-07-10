# dev environment

Dev does not touch AWS. It's a local [kind](https://kind.sigs.k8s.io/) cluster standing in for the
prod EC2/kubeadm cluster, so Helm charts under `helm/` can be developed and tested without a real
API Gateway / ALB / EC2 stack.

## Usage

```bash
kind create cluster --name infra-dev --config kind-config.yaml
kubectl cluster-info --context kind-infra-dev

# install workloads, e.g.
helm upgrade --install <chart> ../../helm/<chart> -f ../../helm/<chart>/values-dev.yaml

# app is reachable on the ingress NodePort mapped to the host
curl http://localhost:8080/

# teardown
kind delete cluster --name infra-dev
```

There is no Terragrunt unit for `dev` — nothing here is AWS-managed state, so it isn't part of the
`live/` Terragrunt tree. `prod` is the only environment under Terragrunt.
