# helm

Workload Helm charts go here, one directory per chart/app. Each chart should ship
`values-dev.yaml` and `values-prod.yaml` for the two environments in `live/`.

Nothing is deployed to a real cluster yet — no charts have been added. A cluster ingress
controller (e.g. ingress-nginx configured to listen on NodePort 30080, matching
`modules/alb`'s `ingress_node_port` and `live/dev/kind-config.yaml`) is a prerequisite for
routing external traffic to any workload chart added here.
