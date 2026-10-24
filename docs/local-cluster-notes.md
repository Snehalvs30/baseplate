# Local cluster notes

## Why the local cluster is k3d (k3s), not kind

The platform started on kind. On an 8 GB laptop (Docker capped at 5 GB), it ran close to
its limits, and every restart caused a CPU spike that slowed the API server. The scheduler
and controller manager then missed their leader-election lease renewals and restarted
repeatedly (18 times each), leaving new pods Pending with no events. Disabling leader
election helped, but there was no headroom left for the observability stack.

k3s runs the whole control plane in one process with an embedded database, uses far less
CPU and memory, and enforces NetworkPolicies without a separate plugin (Calico was needed
on kind). Because everything is declared in Git, the move only needed a new cluster
definition (clusters/local/k3d.yaml), a Traefik service type change, and three bootstrap
steps: install ArgoCD, recreate External Secrets Operator's AWS credentials, apply the root
application.

EKS runs the control plane on separate, managed machines, so none of this applies there.
