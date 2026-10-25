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
