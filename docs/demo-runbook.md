# Stratego demonstration runbook

## Before presenting

1. Start Docker Desktop and confirm `kubectl config current-context` points to the intended cluster.
2. Run `kubectl get nodes`, `kubectl get pods`, `kubectl get hpa stratego`, and `kubectl get cluster stratego-postgres-main-ha`. The HA database command applies only when the CloudNativePG cluster is installed.
3. Forward the application, Grafana and Prometheus in separate terminals:

   ```sh
   kubectl port-forward service/stratego 8080:80
   kubectl port-forward service/grafana 3000:3000
   kubectl port-forward service/prometheus 9090:9090
   ```

4. Open the app at http://localhost:8080 and Grafana at http://localhost:3000. Use the Grafana credentials configured for your environment. The local demo image initially uses admin/admin and prompts for a new password.

## Demonstration sequence

1. Create tasks with different priorities and due dates; show urgency sorting and the Done filter. Use only test data you can delete afterward.
2. Show `kubectl get pods -l app=stratego -o wide` and the HPA with `kubectl get hpa stratego`. Show the Stratego Grafana dashboard for requests, latency, application process CPU/memory, reachable app pods, and node CPU/memory. On kind, nodes share the Docker VM kernel; they do not represent independent physical hosts.
3. For scaling, keep the app port-forward active and run `python3 scripts/load_test.py http://127.0.0.1:8080/ --seconds 180 --workers 20` while watching `kubectl get hpa stratego -w`. Scaling depends on the load and cluster capacity. Stop the load when finished; scale-down can take several minutes.
4. Show app self-healing by deleting **one named application pod** from the list, then run `kubectl rollout status deployment/stratego` and verify the task is still visible. A `kubectl port-forward` session can stop if its selected pod is deleted; restart that session if needed.
5. For the database failover demo, use the [HA guide](high-availability.md). Ensure all three instances are healthy and make a backup first. Delete only the current primary pod, watch `kubectl get cluster stratego-postgres-main-ha -w`, and verify task data after promotion. Expect a temporary interruption. Do not delete PVCs. The local cluster runs on one Mac, so it cannot prove host-level availability.
6. Show the [CI workflow](../.github/workflows/ci.yml) and GitHub Actions run. The publish job requires Docker Hub configuration; the deploy job additionally needs a dedicated runner and target cluster. A skipped job is not evidence of deployment.

## Cleanup

Delete only the test tasks created for the demo. Stop port-forwards with Ctrl-C. The kind cluster, persistent volumes, and local backup remain until deliberately removed; see the README and HA guide before any cleanup. AWS resources, once created, incur costs and require separate cleanup.
