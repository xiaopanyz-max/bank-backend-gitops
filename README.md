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
infra/
  nginx/                # Local dual-cluster nginx entrypoint and gray routing config.
```

`base` contains the common Deployments, Services and infrastructure manifests. Each overlay provides the environment-specific values such as `APP_ENV`, `CLUSTER_NAME` and log levels.

## Local dual-cluster entrypoint

The local SIT A/B traffic entrypoint is managed in `infra/nginx/nginx.conf`.

Current route:

- `127.0.0.1:18080` -> local nginx.
- nginx -> cluster-a `192.168.30.130:30080` with weight `3`.
- nginx -> cluster-b `10.46.132.20:30080` with weight `1`.

This gives an approximate 75% / 25% split for local gray testing. See `infra/nginx/README.md` for the operating guide and config explanation.

## Local secrets

Do not commit real database credentials.

Create the local secret file from the example before deploying:

```bash
cp k8s/base/config/secret.example.yaml k8s/base/config/secret.yaml
kubectl apply -f k8s/base/config/secret.yaml
kubectl apply -k k8s/
```
