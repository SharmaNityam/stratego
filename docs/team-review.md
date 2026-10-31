# Team review notes

- Nityam requested priorities, a high-availability plan and dashboards for CPU, memory and pod counts. The local cluster distributes app replicas where possible; PostgreSQL and the local machine remain single points of failure.
- Priyansh chose Low, Medium and High priorities with no preset selection, urgency sorting and a dashboard that makes traffic and health clear. Review the task form, sort control and dashboard panel labels; suggest any changes after trying them.
- Randeep chose ordering by due date with priority as the tie-breaker, PostgreSQL for shared application data, a pod recovery demo, preservation of existing tasks during migration, and automatic recovery with a brief interruption. Review the high-availability guide and local verification results after trying the demo.

These notes record decisions and items to review. The main app migration and local PostgreSQL primary failover were tested; see local-verification.md for results and limits. A backup restore was tested in a temporary database; AWS remains untested.
