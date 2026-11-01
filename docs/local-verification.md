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

## Main application migration and failover

On 31 October 2026, the standalone app database was backed up and migrated into a new three-instance `stratego-postgres-main-ha` cluster. The source and target task counts and checksums matched before the app switched; both replicas had replayed the restored data. The original database and a local, owner-readable backup were retained.

A clean rehearsal tested recovery from an injected backup failure, successful migration of three varied tasks, app-role ownership, a new write, refusal to repeat migration, and reapplication of the HA overlay using a rehearsal-specific database name. In the main local cluster, a primary deletion promoted another database instance, with the existing task and a new test write still readable afterward. One health probe failed during the approximately 4.2-second test, and the app pods did not restart. The temporary test task was removed.

With the migrated database, an HTTP load test completed 6,708 requests with zero reported errors and the HPA scaled the app from two to five pods across both workers. In a separate app-pod deletion check, 57 health requests succeeded with zero reported errors while Kubernetes replaced the pod. These are specific local test runs, not guarantees of availability or durability under every failure.

The retained backup was restored into a separate temporary database, and its task checksum and application ownership matched the original source. The new database uses one synchronous standby and experimental failover quorum. Both workers still share one Mac and one control plane; the standalone source and the backup become stale after new writes. Simultaneous failures, physical-host failure, and AWS remain untested.

## Worker interruption tests

A first test stopped the worker hosting the database primary. PostgreSQL initiated failover, but the surviving app process became unresponsive and restarted because database connections occupied its HTTP worker threads. The worker was restarted; this run did not pass end-to-end recovery. The app was subsequently updated with a three-second PostgreSQL connection timeout and a process-based liveness probe. The revised version was subsequently tested again as described below.

In a second test, the revised app's worker containing a database standby was stopped for 80 seconds while the primary and another standby remained on the surviving worker. The surviving app responded to 35 health probes with zero failures, the existing task remained readable, and its process did not restart. The interrupted worker was restarted; all three database instances and both app replicas returned to readiness. This second test does not demonstrate primary-worker failure recovery.

The revised primary-worker failure test was repeated after moving the primary to one worker with both standbys on the other. Stopping the primary worker triggered promotion; the original task and a newly committed test task were readable afterward, and the surviving app did not restart. Over a 120-second probe window, 70 health checks succeeded and 16 failed; the first successful recovery after failures was observed at approximately 51.7 seconds. The test task was removed. After the stopped worker restarted, both app replicas and all three database instances returned to readiness. The restarted worker's app pod itself restarted, as expected when its host was stopped. These results cover this specific local failure arrangement and do not guarantee behavior under other failures.

## Monitoring dashboard extension

Prometheus discovered three node-exporter pods (one on each local kind node). Node CPU and memory queries each returned three series, and Grafana loaded the seven-panel dashboard. Kind nodes share a Docker VM kernel, so these readings are not independent physical-host metrics.

## Browser and image publishing

A browser walkthrough created a task, marked it done, filtered it, and deleted it using a separate local database. Desktop and mobile create/edit form alignment was checked at viewport widths 320, 375, 480, 700, 900, 1100 and 1440 pixels with no document overflow or controls extending outside their forms. The main GitHub Actions workflow passed tests and published commit `c68d1dd3c8a372f13e53ae3d0f14a4ef0315ece8` to the public Docker Hub repository for linux/amd64 and linux/arm64. The deploy job remains disabled until a target runner and cluster are configured.

## UI interaction sweep

On 31 October 2026, a browser walkthrough exercised creation with required fields and each priority, title/details/status/priority edits, all status filters, urgency/newest sorting, and both cancel and confirmation of deletion. Mobile and desktop views were inspected, and a temporary task was created, edited, filtered, and deleted against the live local Kubernetes app. Filter and sort selections now remain after edits and deletions; creating from Done or In progress opens Active so the new task is visible. A browser layout sweep checked 331 widths from 280 to 1600 pixels for horizontal overflow and overlapping form, navigation, and header controls. This covers the tested browser and widths rather than every browser, font, device, or setting.

## Presentation-aligned ingress and deployment

On 1 November 2026, two F5 NGINX Ingress Controller 5.6.3 replicas were installed through Helm chart 2.7.3 in the local kind cluster. A browser created, edited, filtered and deleted a temporary task through the NGINX route; the existing task was retained. The scoped deployer applied the app, service, HPA and ingress manifests and completed a rollout. An intentionally nonexistent image caused a failed rollout and restored the previous image. Prometheus loaded both alert rules, and `promtool` verified the unavailable-app rule against test data; no notification receiver was configured.

The HPA reported both CPU and memory metrics. Temporarily reducing the memory target to 25% caused four replicas to become ready, after which the target was restored to 80%. A CPU load test through NGINX caused scaling to five replicas and reported 34,428 successful requests and 274 errors over 75 seconds with 25 workers. A separate 20-second, five-worker run completed 10,455 requests without errors. These results demonstrate scaling and the limits of those tests; they are not an availability or capacity guarantee.
