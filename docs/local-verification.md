# Local verification

Results from 31 October 2026 on the Stratego kind cluster:

- Docker image built and its health endpoint responded.
- The SQLite tests and a PostgreSQL integration test passed. Terraform validation and the Ansible syntax check passed.
- Kubernetes started a control-plane node and two worker nodes. Two app replicas ran on separate workers using the same standalone PostgreSQL database.
- A task created through the app was still visible after deleting one app pod and waiting for a replacement. The test used a new port-forward after the original pod was deleted.
- Metrics Server reported CPU utilization; a local HTTP load test drove the HPA from two app replicas to five. The load generator reported 9,733 successful requests and 38,215 errors; the test included a deliberate port-forward restart, during which the original generator retried connection failures without delay. This run demonstrates scaling, not application availability or error-rate performance. A separate 10-second smoke load without a tunnel restart completed 975 requests with no errors; it is not a production performance benchmark.
- A separate three-instance CloudNativePG cluster became healthy across the two workers. Both replicas reported streaming and caught up before the primary pod was deleted. The operator promoted a replica on the other worker, and a task remained readable through a separate test application after promotion. This did not test a physical host failure or guarantee zero data loss under other timing conditions.
- Prometheus discovered and scraped the app pods. Its request counter was still present after its pod was restarted. Grafana loaded the five-panel dashboard.

PostgreSQL and Prometheus were loaded into this cluster using locally rebuilt images based on their upstream images, because image downloads on the node were slow. This verifies their behavior in this local setup, not every deployment environment.

The main demo has a single PostgreSQL pod, single control plane, and single physical host. Those components remain failure points. The CloudNativePG cluster was tested separately with its own database; switching an existing deployment and migrating its data remain untested. AWS infrastructure, multi-host failure, recovery from storage loss, and automated cloud deployment are not yet validated.
