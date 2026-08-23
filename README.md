# bank-backend-gitops

This repository stores the Kubernetes GitOps manifests for `bank-backend-springboot`.

## Repository responsibilities

- Application source code: `xiaopanyz-max/bank-backend-springboot`
- Deployment desired state: `xiaopanyz-max/bank-backend-gitops`

GitHub Actions in the application repository builds container images and updates `k8s/kustomization.yaml` in this repository. Argo CD watches this repository and syncs the selected overlay into the local Kubernetes cluster.

## Kubernetes layout

```text
k8s/
  base/                 # Shared manifests used by every environment/cluster.
  overlays/
    sit-cluster-a/      # Current local SIT cluster.
    uat/                # UAT template.
    prd/                # PRD template.
  kustomization.yaml    # Current entrypoint watched by Argo CD.
```

`base` contains the common Deployments, Services and infrastructure manifests. Each overlay provides the environment-specific values such as `APP_ENV`, `CLUSTER_NAME` and log levels.

## Local secrets

Do not commit real database credentials.

Create the local secret file from the example before deploying:

```bash
cp k8s/base/config/secret.example.yaml k8s/base/config/secret.yaml
kubectl apply -f k8s/base/config/secret.yaml
kubectl apply -k k8s/
```
