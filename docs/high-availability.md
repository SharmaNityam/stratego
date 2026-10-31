# Optional replicated PostgreSQL demo

This is an alternative to the standalone PostgreSQL deployment. A local primary-pod failover test passed on 31 October 2026; see [local verification](local-verification.md). CloudNativePG creates a primary, two replicas and a read/write service. Automatic failover depends on healthy replicas, Kubernetes control-plane availability, storage, and operator configuration. The default replication mode can lose recent acknowledged transactions during failover; validate the required durability and configure synchronous replication and backups if needed. Three pods on one Mac do not provide physical-machine availability. Prometheus and Grafana also remain single instances.

These commands create a **new empty database**. Existing SQLite or standalone PostgreSQL tasks are not migrated. Do not switch an existing deployment without a tested data migration and backup. Install only in a disposable demo cluster with enough CPU, memory and persistent storage. Keep the operator and PostgreSQL versions current and review the [official CloudNativePG installation guide](https://cloudnative-pg.io/docs/1.30/installation_upgrade/) before use.

```sh
kubectl apply --server-side -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.30/releases/cnpg-1.30.1.yaml
kubectl -n cnpg-system rollout status deployment/cnpg-controller-manager --timeout=180s
kubectl apply -f k8s/ha/postgres-cluster.yaml
kubectl wait --for=condition=Ready cluster/stratego-postgres-ha --timeout=600s
# First deploy k8s/app.yaml, then point it at the operator-generated application URI.
kubectl patch deployment stratego --type=strategic --patch-file k8s/ha/app-database-patch.yaml
kubectl rollout status deployment/stratego --timeout=180s
kubectl get pods -l cnpg.io/cluster=stratego-postgres-ha -o wide
```

The operator-generated Secret is named `stratego-postgres-ha-app`; its `uri` points to the read/write service. See [Connecting from an application](https://cloudnative-pg.io/docs/1.27/applications/).

For a failover experiment, first verify the cluster reports all three PostgreSQL instances healthy. Create a task, identify the primary using the Cluster status, delete **only the primary pod**, wait for a new primary and the application to recover, then check the task. Expect a brief interruption. Record observed results. Use independent machines and storage failure domains to assess real node failure.
