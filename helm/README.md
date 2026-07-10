# helm

Workload Helm charts live with their app repos, not here — e.g. `contacts-micro-service`'s chart is
at `~/projects/contacts-micro-service/helm/contacts-micro-service`. This directory is a placeholder
for anything cluster-wide/shared (an ingress controller values file, cert-manager, etc.), not
per-app workload charts.

Each app chart should ship `values-local.yaml` and `values-prod.yaml` for the environments in
`live/`. A cluster ingress controller (e.g. ingress-nginx configured to listen on NodePort 30080,
matching `modules/alb`'s `ingress_node_port` and `live/local/kind-config.yaml`) is a prerequisite for
routing external traffic to any workload chart deployed to prod.
