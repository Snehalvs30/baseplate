# EKS dev: results

## Isolation probes (VPC CNI network policy agent)

| Probe | Result |
|---|---|
| podinfo -> Ledgerline's API | BLOCKED |
| Ledgerline -> the internet | BLOCKED |
| Ledgerline -> its own RDS | OPEN |
| podinfo -> Ledgerline's RDS | OPEN at first, BLOCKED after the fix |
| Footnote -> Ledgerline's RDS | OPEN (limitation; credentials still isolate the data) |

Finding: the database egress rule applied to every tenant, and both RDS instances share
the private subnets and accept the nodes' security group, so any tenant could open a
connection to any database. Fixed by giving the rule only to tenants with a database.
Network-level isolation between database tenants needs Security Groups for Pods (each
tenant's pods get their own security group; each RDS instance accepts only its
tenant's): the production next step.

## Traces (OpenTelemetry Java agent, no code changes)

Ledgerline's requests appear in Tempo with their database spans. During the load test,
the server spent 5-7 ms per GET /accounts/{id} (including the RDS query), while k6 in
Boston measured a 55 ms median: about 90% of the latency was the network to us-east-2.
Probe and scrape requests (/actuator/health, /actuator/prometheus) are traced too; a
production collector would filter them out to save storage.

## Teardown

Applications deleted first (so Kubernetes removed the load balancer it created), then
`terraform destroy`: 54 resources removed. Remaining on purpose: the state bucket, the
budget alert, and the local cluster's secrets.
