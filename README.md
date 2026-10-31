# Stratego

A Flask task manager and a local-first DevOps demonstration: Docker, Terraform, Ansible, Kubernetes, Prometheus, Grafana, and GitHub Actions. Tasks support creation, editing, deletion, status filters and due-date reminders.

## Run locally

Requires Python 3.10 or newer.

```sh
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements-dev.txt
flask --app 'app:create_app()' run
```

Open http://127.0.0.1:5000. Tasks are stored in `data/stratego.db`. Run `pytest -q` and `ruff check app tests` for checks.

## Docker

```sh
docker build -t stratego-app:local .
docker run --rm -p 5000:5000 -v stratego-data:/data stratego-app:local
```

## Kubernetes local demo

Use a **single-node** cluster (e.g. minikube) with a default storage class and metrics-server enabled. Build `stratego-app:local` into the cluster's image store (for minikube, `minikube image build -t stratego-app:local .`), then run:

```sh
kubectl apply -f k8s/app.yaml
kubectl apply -f monitoring/
kubectl get pods,hpa
kubectl port-forward service/stratego 8080:80
```

Open http://localhost:8080. In separate terminals, forward Prometheus with `kubectl port-forward service/prometheus 9090:9090` and Grafana with `kubectl port-forward service/grafana 3000:3000`. Grafana's image defaults to admin/admin and asks for a new password on first sign-in. The included dashboard displays request rate and latency. Prometheus stores up to seven days of metrics on a 2 GiB persistent volume, subject to available disk space. The volume survives pod restarts; deleting the persistent volume claim may delete its data, depending on the storage class. Grafana changes are ephemeral in this demo. Prometheus discovers and scrapes each application pod through the Kubernetes API. The bundled RBAC binding assumes the default namespace. CPU/node metrics and pod counts are not yet collected. HPA requires a working metrics-server; check `kubectl describe hpa stratego`.

SQLite is shared via a ReadWriteOnce volume, suitable here only for a single-node demonstration. Two application replicas do not provide database high availability. Multi-node or production deployments need a shared database such as PostgreSQL, durable monitoring storage, and authentication and security controls.

## Cloud later

`terraform/` provisions a single Ubuntu EC2 instance in the default VPC, a restricted security group and encrypted root disk. It requires AWS credentials, an existing key pair and an operator IP CIDR; applying incurs AWS charges. Copy the example tfvars and set real values. Run `terraform init`, `terraform plan`, and only then `terraform apply`. The `ansible/setup.yml` playbook installs Docker and a pinned single-node k3s release using the example inventory. These cloud steps have not been applied or validated against AWS. Review the k3s installation script and version before use. Delete resources with `terraform destroy` when finished.

A cloud deployment also needs an image in a registry, a modified deployment image reference, and an accessible kubeconfig. CI runs lint, tests and a Docker build. Image publishing is disabled until the `DOCKERHUB_IMAGE` repository variable and `DOCKER_USERNAME` / `DOCKER_PASSWORD` secrets are configured. The image uses the commit SHA tag. Automated cluster deployment is intentionally not configured before the target cluster exists.
