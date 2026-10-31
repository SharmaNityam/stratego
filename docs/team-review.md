# Team review notes

- Nityam requested priorities, a high-availability plan and dashboards for CPU, memory and pod counts. The local cluster distributes app replicas where possible; PostgreSQL and the local machine remain single points of failure.
- Priyansh chose Low, Medium and High priorities with no preset selection, urgency sorting and a dashboard that makes traffic and health clear. Review the task form, sort control and dashboard panel labels; suggest any changes after trying them.
- Randeep chose ordering by due date with priority as the tie-breaker, PostgreSQL for shared application data and a pod recovery demo. Review the ordering and the demo steps in the README; suggest changes after trying them.

These notes record decisions and items to review. The local Kubernetes demo and separate PostgreSQL primary failover were tested; see local-verification.md for results and limits. AWS and data migration remain untested.
