# 本地 Kubernetes 部署

该目录用于在本地单节点 Kubernetes 集群中运行整套银行服务。

## 包含的组件

- Windows MySQL：由 Windows 主机管理，Kubernetes 通过 `mysql:3306` 访问。
- Nacos 单机版：本地服务注册与发现；为简化学习环境，鉴权关闭。
- RocketMQ 5.3.2：单 NameServer、单 Broker。
- customer-service、account-service、api-gateway。

## 部署前提

1. Windows 的 MySQL 已运行。Kubernetes 经 Windows 的受限端口转发访问 `192.168.30.1:3306`，而 MySQL 本身仍只监听本机回环地址。
2. 已创建只允许 K8s NAT 网段访问的 `bank_k8s` 数据库账号，并初始化 `bank_dev`、`bank_account`。
3. 将 `base/config/secret.example.yaml` 复制为 `base/config/secret.yaml`，填入该账号密码；此文件不会提交 Git。
4. GitHub Actions 已成功将三张业务镜像推送至 GHCR。
5. GHCR 包对本地集群可拉取。公开包可直接拉取；私有包需先配置 `imagePullSecret`。
6. Windows 的 MyClash 与 NAT 代理保持启动，以便 containerd 拉取镜像。

## 初始化 Windows MySQL

用 Windows 本机的 MySQL Workbench 或命令行，以管理员账号依次执行：

1. 在 MySQL 中创建 `bank_k8s` 账号，并授予 `bank_dev`、`bank_account` 所需权限。
2. 执行应用仓库 `bank-backend-springboot/database/schema.sql`：创建客户库表。
3. 执行应用仓库 `bank-backend-springboot/account-service/database/schema.sql`：创建账户库表。

随后将同一账号和密码填入 `base/config/secret.yaml`。不要把真实密码写进示例 SQL 或提交到 Git。

## 部署

在 Ubuntu 节点执行：

```bash
kubectl apply -f k8s/base/config/secret.yaml
kubectl apply -k k8s/
kubectl get pods -n bank -w
```

## 环境与日志级别

当前 `k8s/kustomization.yaml` 指向 `overlays/sit-cluster-a`，所以默认本地集群按 SIT 集群 A 运行。公共配置和环境差异拆分为：

- `base/`：所有环境共用的 Deployment、Service、Nacos、RocketMQ、MySQL 映射和日志采集配置。
- `overlays/sit-cluster-a/env-config.yaml`：SIT 集群 A，业务包 `com.example.bank` 使用 `DEBUG`，方便本地联调和排查。
- `overlays/sit-cluster-b/env-config.yaml`：SIT 集群 B，业务包 `com.example.bank` 使用 `DEBUG`，用于第二个 Kubernetes 集群接入双集群演练。
- `overlays/uat/env-config.yaml`：UAT，业务包使用 `INFO`，接近准生产验证。
- `overlays/prd/env-config.yaml`：PRD，根日志使用 `WARN`，业务包使用 `INFO`，降低生产日志噪音。

业务服务通过 Deployment 的 `envFrom` 引入当前环境配置：

```yaml
envFrom:
  - configMapRef:
      name: bank-app-config
  - configMapRef:
      name: bank-env-config
```

如果后面要切到 UAT 或 PRD，修改根目录 `k8s/kustomization.yaml` 的 `resources`，从 `overlays/sit-cluster-a` 切到 `overlays/uat` 或 `overlays/prd`，然后提交 GitOps 仓库。Argo CD 同步后会让 Pod 使用新的环境配置。

第二个集群不要修改根目录 `k8s/kustomization.yaml`，而是让 cluster-b 的 Argo CD Application 直接指向：

```text
k8s/overlays/sit-cluster-b
```

这样 cluster-a 和 cluster-b 可以共享同一套 base，但各自使用不同 overlay。

当前 cluster-b overlay 已将 MySQL EndpointSlice 地址替换为：

```text
10.46.132.206:3306
```

这是第一台 Windows 在当前热点/WLAN 网络里的地址。如果热点 IP 变化，需要同步更新 `overlays/sit-cluster-b/kustomization.yaml` 中的 MySQL EndpointSlice patch。

当前 base 中 Fluent Bit 的 Elasticsearch 输出地址为：

```text
10.46.132.23:9200
```

cluster-a 和 cluster-b 默认使用同一个 ES 日志入口。如果 Kibana 能打开但查不到日志，先看 `kubectl logs -n logging ds/fluent-bit --tail=120`；若日志里仍然连接旧地址或超时，需要同步更新 `base/observability/fluent-bit.yaml` 中的 Fluent Bit ES Host。

cluster-b 当前作为副集群使用，计划只承接约 25% 流量，因此资源配置比 cluster-a 更轻：

- 业务服务：`replicas=1`，`requests.cpu=50m`，`requests.memory=256Mi`。
- Nacos / RocketMQ：`replicas=1`，`requests.cpu=100m`，`requests.memory=384Mi`。
- RocketMQ Broker JVM：cluster-b 覆盖为 `-Xms96m -Xmx128m -Xmn32m -XX:MaxDirectMemorySize=64m -XX:-AlwaysPreTouch -XX:ParallelGCThreads=1 -XX:ConcGCThreads=1`，避免副集群 4G 学习 VM 被 Broker 默认内存配置拖垮。
- RocketMQ Broker hostPath：cluster-b 通过 initContainer 在 Pod 启动前修正 `/var/lib/bank-k8s/rocketmq` 和 `/var/log/bank-k8s/rocketmq` 权限，避免新节点上 `DirectoryOrCreate` 创建 root 目录后 Broker 无法写入而秒退。
- Deployment 策略：`Recreate`，更新时先停旧 Pod 再起新 Pod，避免 4G 学习 VM 因滚动发布临时双倍 Pod 而 `Insufficient cpu`。

目的：在 4G 左右内存的学习 VM 上保留双集群能力，同时避免因为资源 request 过高导致 Pod `Pending`。

cluster-b 首次部署前仍然需要手动创建数据库 Secret。Secret 不提交到 GitOps 仓库：

```bash
kubectl create namespace bank --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic bank-local-secrets -n bank \
  --from-literal=MYSQL_USERNAME=bank_k8s \
  --from-literal=MYSQL_PASSWORD='替换成真实 MySQL 密码'
```

所有 Pod 运行后，从 Windows 访问：

```text
http://192.168.30.130:30080
```

网关路由示例：

```text
POST /api/customers
POST /api/customers/page
GET  /api/customers/{id}
GET  /api/transactions/{id}/with-balance
```

## 本地与生产差异

- MySQL 位于 Windows 主机，`EndpointSlice` 默认使用 cluster-a 的 VMware NAT 网关地址 `192.168.30.1`；若 cluster-b 不能访问该地址，需要在 cluster-b overlay 中增加 MySQL EndpointSlice patch，改成 cluster-b 能访问到的 MySQL 地址。
- `base/config/secret.yaml` 必须在本地创建，绝不可提交到 Git；仓库只保留安全的示例文件。
- Nacos、RocketMQ 都是单副本；生产应按各组件的高可用方案部署。
