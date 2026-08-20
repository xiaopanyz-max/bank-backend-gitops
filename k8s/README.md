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
3. 将 `config/secret.example.yaml` 复制为 `config/secret.yaml`，填入该账号密码；此文件不会提交 Git。
4. GitHub Actions 已成功将三张业务镜像推送至 GHCR。
5. GHCR 包对本地集群可拉取。公开包可直接拉取；私有包需先配置 `imagePullSecret`。
6. Windows 的 MyClash 与 NAT 代理保持启动，以便 containerd 拉取镜像。

## 初始化 Windows MySQL

用 Windows 本机的 MySQL Workbench 或命令行，以管理员账号依次执行：

1. 在 MySQL 中创建 `bank_k8s` 账号，并授予 `bank_dev`、`bank_account` 所需权限。
2. 执行应用仓库 `bank-backend-springboot/database/schema.sql`：创建客户库表。
3. 执行应用仓库 `bank-backend-springboot/account-service/database/schema.sql`：创建账户库表。

随后将同一账号和密码填入 `config/secret.yaml`。不要把真实密码写进示例 SQL 或提交到 Git。

## 部署

在 Ubuntu 节点执行：

```bash
kubectl apply -f k8s/config/secret.yaml
kubectl apply -k k8s/
kubectl get pods -n bank -w
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

- MySQL 位于 Windows 主机，`EndpointSlice` 使用 VMware NAT 网关地址 `192.168.30.1`；若 VMware NAT 网段改变，需要同步修改 `infra/mysql-external.yaml`。
- `config/secret.yaml` 必须在本地创建，绝不可提交到 Git；仓库只保留安全的示例文件。
- Nacos、RocketMQ 都是单副本；生产应按各组件的高可用方案部署。
