# Stratego

A task manager and DevOps demonstration using Flask, Docker, Terraform, Ansible, Kubernetes, Prometheus, Grafana and GitHub Actions. Tasks have titles, details, due dates, status and a required Low/Medium/High priority. The default view contains active tasks. Sort by urgency (earliest due date, then highest priority) or newest; tasks without a due date appear last in urgency order.

## Run the application locally

Requires Python 3.10 or newer. This path uses SQLite and does not require Docker.

```sh
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements-dev.txt
flask --app 'app:create_app()' run
```

Open http://127.0.0.1:5000. SQLite data is stored in `data/stratego.db`. Existing SQLite tasks created before priorities were added receive Medium during schema migration; new tasks require a choice. SQLite data is not automatically copied to PostgreSQL. Run `pytest -q` and `ruff check app tests scripts`.

## Docker image

```sh
docker build -t stratego-app:local .
docker run --rm -p 5000:5000 -v stratego-data:/data stratego-app:local
```

A named Docker volume preserves the SQLite data after the container stops. Set `DATABASE_URL` to a PostgreSQL connection string to use a shared database instead.

## Multi-node Kubernetes demo

Requires Docker, kind, kubectl, a default dynamic storage class, and a working metrics-server for HPA. The following creates a local cluster with two workers; it does not provide separate physical machines or protect against a failure of the Mac. It uses a single PostgreSQL pod and persistent volume: **the database is a single point of failure**, so this is application replica resilience, not full-stack high availability. The manifests are demonstration configuration, not hardened production infrastructure.

```sh
kind create cluster --name stratego --config k8s/kind-config.yaml
kind load docker-image stratego-app:local --name stratego
# Metrics Server for this local test cluster (requires internet).
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.9.1/components.yaml
kubectl -n kube-system patch deployment metrics-server --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
kubectl -n kube-system rollout status deployment/metrics-server --timeout=180s
# Generate a local-only database password and store it in a Kubernetes Secret.
STRATEGO_DB_PASSWORD=$(openssl rand -hex 20)
kubectl create secret generic stratego-db \
  --from-literal=password="$STRATEGO_DB_PASSWORD" \
  --from-literal=url="postgresql://stratego:${STRATEGO_DB_PASSWORD}@postgres:5432/stratego"
unset STRATEGO_DB_PASSWORD
kubectl apply -f k8s/postgres.yaml
kubectl rollout status deployment/postgres --timeout=180s
kubectl apply -f k8s/base/app.yaml
kubectl apply -f monitoring/
kubectl rollout status deployment/stratego --timeout=180s
kubectl get pods -o wide
kubectl get hpa
kubectl port-forward service/stratego 8080:80
```

Open http://localhost:8080. In separate terminals, forward Prometheus with `kubectl port-forward service/prometheus 9090:9090` and Grafana with `kubectl port-forward service/grafana 3000:3000`. Grafana's demo image defaults to admin/admin and asks for a new password on first sign-in. Use only on a trusted local machine; change the password and secure access before deployment elsewhere.

The dashboard shows aggregate application request rate and latency, application **process** CPU and resident memory per pod, reachable application pods, and node CPU and memory metrics from node-exporter. Process metrics are not node-wide or container-wide usage. In kind, nodes share the Mac's Docker VM kernel, so node metrics are not independent physical-machine measurements. Prometheus discovers pods using the Kubernetes API; its RBAC binding assumes the default namespace. Prometheus keeps up to seven days of metrics on a 2 GiB volume, subject to disk space. Deleting its PVC may delete metrics depending on the storage class. Grafana dashboard edits are ephemeral; the bundled dashboard is restored from its ConfigMap.

The Metrics Server flag above disables kubelet certificate verification for this local test cluster only. Use trusted kubelet certificates for a real deployment. See the [Metrics Server documentation](https://github.com/kubernetes-sigs/metrics-server#requirements). HPA requires metrics-server and scales the app from 2 to 5 replicas based on 50% average CPU utilization. If the cluster has no metrics-server, `kubectl describe hpa stratego` will report unavailable metrics. Install and verify a metrics-server appropriate for your cluster before demonstrating autoscaling.

To generate load against your own local demo, keep the app port-forward running and run `python3 scripts/load_test.py http://127.0.0.1:8080/ --seconds 180 --workers 20`, while watching `kubectl get hpa stratego -w` in another terminal. HPA behavior depends on workload and cluster resources; a scaling event is not guaranteed. Stop the load with Ctrl-C.

To demonstrate app pod recovery, leave the app open, then in another terminal run:

```sh
kubectl get pods -l app=stratego -o wide
kubectl delete pod POD_NAME
kubectl rollout status deployment/stratego
kubectl get pods -l app=stratego -o wide
```

Replace `POD_NAME` with one pod name from the first command. The deployment creates a replacement; confirm tasks remain visible after replacement. Topology-spread constraints distribute replicas across eligible worker nodes; availability still depends on node capacity and scheduling. Local kind storage is node-bound and is not a substitute for a replicated database or storage system. `kind delete cluster --name stratego` deletes the cluster and its local data.

The [high-availability guide](docs/high-availability.md) describes migrating the main app to a new replicated PostgreSQL cluster while preserving tasks. The migration and a primary-pod failover were verified locally. The base manifest still points to the standalone database; after migration, use the HA overlay as described in the guide.

See [local verification](docs/local-verification.md) for the checks performed and their limits, and the [demo runbook](docs/demo-runbook.md) for a presentation sequence.

For full-stack high availability, use multiple independent nodes and failure domains, a replicated managed PostgreSQL service or tested failover cluster, durable shared monitoring storage, appropriate load balancing, backups and recovery tests. Independent physical failure domains and durable off-host backups are not provided or verified by this local demo.

## AWS later

`terraform/` provisions one Ubuntu EC2 instance in the default VPC, a restricted security group and encrypted root disk. It requires AWS credentials, an existing key pair and an operator IP CIDR; applying incurs AWS charges. A single instance is not highly available. Copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars`, set real values, then run `terraform init` and `terraform plan` in that directory before applying. The `ansible/setup.yml` playbook installs Docker and a pinned single-node k3s release using the example inventory. Neither Terraform apply nor Ansible against AWS has been tested. Review the k3s installation script and version before use. Destroy cloud resources when finished.

A cloud deployment also needs a registry image, database secrets and a suitable cluster configuration. The Ansible playbook pins K3s 1.36.5, within the Kubernetes versions supported by CloudNativePG 1.30, but this combination has not been tested on AWS. The proposed CI/CD workflow and setup requirements are described in [automated deployment](docs/automated-deployment.md). The workflow passed an end-to-end test in a separate private repository and local cluster. The main repository publishes public multi-architecture images to Docker Hub; its deployment runner and AWS target are not configured yet.
