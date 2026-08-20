# bank-backend-gitops

This repository stores the Kubernetes GitOps manifests for `bank-backend-springboot`.

## Repository responsibilities

- Application source code: `xiaopanyz-max/bank-backend-springboot`
- Deployment desired state: `xiaopanyz-max/bank-backend-gitops`

GitHub Actions in the application repository builds container images and updates `k8s/kustomization.yaml` in this repository. Argo CD watches this repository and syncs the desired state into the local Kubernetes cluster.

## Local secrets

Do not commit real database credentials.

Create the local secret file from the example before deploying:

```bash
cp k8s/config/secret.example.yaml k8s/config/secret.yaml
kubectl apply -f k8s/config/secret.yaml
kubectl apply -k k8s/
```

