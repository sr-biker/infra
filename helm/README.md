# helm

Workload Helm charts go here, one directory per chart/app. Each chart should ship
`values-local.yaml` and `values-prod.yaml` for the environments in `live/`.

A cluster ingress controller (e.g. ingress-nginx configured to listen on NodePort 30080, matching
`modules/alb`'s `ingress_node_port` and `live/local/kind-config.yaml`) is a prerequisite for
routing external traffic to any workload chart deployed to prod.
