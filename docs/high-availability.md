# Main application high-availability demo

The main app can use `stratego-postgres-main-ha`, a CloudNativePG cluster with one primary and two replicas. Transactions wait for one synchronous standby, and CloudNativePG failover quorum is enabled. This favors preservation of acknowledged writes: if the required standby or a safe promotion quorum is unavailable, writes or failover can pause until the cluster recovers. CloudNativePG documents failover quorum as an experimental feature; review its [failover guidance](https://cloudnative-pg.io/docs/1.30/failover/) before using it outside the demo. No configuration eliminates every data-loss scenario, and replication is not a backup.

The local kind setup has two worker nodes, one control-plane node and one physical Mac. Application pods are spread across available workers, but PostgreSQL has three instances on two workers. Losing the Mac or control plane remains a single point of failure. Local kind volumes are node-bound; multi-host or multi-zone resilience, backup restoration, and AWS are not verified.

## Migrate existing tasks

The migration is **offline**: app replicas are stopped temporarily so writes cannot change during the backup and copy. It expects the existing standalone database deployment `postgres`, database/user `stratego`, application deployment/container `stratego`, and its `stratego-db` secret. The target must be a new, empty `stratego-postgres-main-ha` cluster. It refuses to overwrite an existing target or run again after the app has switched.

```sh
# Check the context first; this process changes the named cluster.
kubectl config current-context
kubectl apply --server-side -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.30/releases/cnpg-1.30.1.yaml
kubectl -n cnpg-system rollout status deployment/cnpg-controller-manager --timeout=180s
kubectl apply -f k8s/ha/main-postgres-cluster.yaml
kubectl wait --for=condition=Ready cluster/stratego-postgres-main-ha --timeout=600s
KUBE_CONTEXT="$(kubectl config current-context)" scripts/migrate-to-ha.sh
```

The script checks that all three database instances are ready and that the target is empty. It stops app pods, saves a PostgreSQL dump under `data/backups/` with owner-only file permissions, restores it under the application role, compares task counts and checksums, waits for both replicas to replay the restore, then changes the app database secret and brings the app back. The backup contains task data in plaintext; protect it and take a separate durable backup if needed. The original database is left intact.

If a failure occurs before the switch, the script restores the original app replica count. If a failure occurs during or after the switch, it leaves the target configured for manual investigation: reverting automatically could discard new writes. A partially restored target is not overwritten on a retry. The original standalone database becomes stale as soon as new writes reach the replicated database, so do not switch back to it without a tested reverse migration or recovery plan. Only app writes are paused; stop any other writers separately before migration.

## Keep the app pointed at the HA database

After migration, `k8s/ha/` is the declarative HA overlay. `kubectl kustomize k8s/ha` renders the app, service, HPA and replicated database. **Do not apply the standalone `k8s/base/app.yaml` to a migrated app**: its database secret targets the old database. Applying the overlay before migration would instead point the app at the empty target database. The overlay also uses the local image tag from the base; update the image for the target environment before applying it, or it can replace the deployed image. The GitHub deployment script updates only the image and retains the database secret.

The older `k8s/ha/postgres-cluster.yaml` creates a separate experimental database named `stratego-postgres-ha`; it is not the main app database and is not part of the HA overlay.

## Check failover

After confirming three database instances are healthy and application tasks are visible, delete only the current **primary pod**, then monitor the cluster status, app readiness and task data. A brief interruption is expected. The revised app passed a repeated primary-worker interruption test locally; that run observed approximately 51.7 seconds before the first successful health check after failures. See the verification record for the test setup and results. Do not delete a PVC or multiple database pods as part of this demo. Verify writes made after recovery as well as the pre-existing tasks. See [local verification](local-verification.md) for the actual test results and their limits.
