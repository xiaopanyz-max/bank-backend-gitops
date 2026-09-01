# 本地 nginx 双集群入口

这个目录保存本地 SIT 双集群入口的 nginx 配置。

## 为什么放在 GitOps 仓库

nginx 负责把入口流量分发到 cluster-a 和 cluster-b，属于部署和流量治理配置，不属于 Spring Boot 业务代码。因此配置源头放在 GitOps 仓库：

```text
GitOps 仓库 infra/nginx/nginx.conf  = 配置源头
本机 nginx 安装目录 conf/nginx.conf = 运行时副本
```

以后调整灰度比例、入口端口、超时时间、后端集群地址时，先改 GitOps 仓库，再同步到本机 nginx。

## 当前流量路径

```text
Postman / 浏览器
  ↓
http://127.0.0.1:18080
  ↓
本机 nginx
  ↓
upstream bank_gateway
  ├── cluster-a: 192.168.30.130:30080，weight=9
  └── cluster-b: 10.46.132.20:30080，weight=1
  ↓
api-gateway
  ↓
customer-service / account-service
```

当前权重大约是：

```text
cluster-a: 90%
cluster-b: 10%
```

nginx 的 `weight` 是相对权重，不是严格百分比。请求量少时可能看起来不均匀，请求量多时会更接近 9:1。

## 配置文件说明

核心配置在 `nginx.conf`：

```nginx
upstream bank_gateway {
    server 192.168.30.130:30080 weight=9;
    server 10.46.132.20:30080 weight=1;
}
```

这段定义后端服务池：

- `192.168.30.130:30080`：cluster-a 的 api-gateway NodePort。
- `10.46.132.20:30080`：cluster-b 的 api-gateway NodePort。
- `weight=9` 和 `weight=1`：表示 A:B 约为 9:1。

```nginx
server {
    listen 18080;
    server_name localhost;
}
```

这段定义本机唯一入口。Postman 以后只需要访问：

```text
http://127.0.0.1:18080
```

```nginx
location / {
    proxy_pass http://bank_gateway;
}
```

这段表示所有路径都转发到 `bank_gateway`。例如：

```text
POST http://127.0.0.1:18080/api/customers
```

会被 nginx 转发到 A 或 B 集群的 api-gateway。

```nginx
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
```

这几行把原始请求信息传给后端，方便后面排查来源 IP、链路日志和网关行为。

```nginx
proxy_connect_timeout 3s;
proxy_read_timeout 30s;
proxy_send_timeout 30s;
```

这几行控制 nginx 到后端服务的超时时间。cluster-b 不通时，nginx 不会一直卡死在连接阶段。

## 同步到本机 nginx

在 PowerShell 中执行：

```powershell
.\infra\nginx\sync-to-local-nginx.ps1
```

脚本会：

1. 备份本机 nginx 当前配置。
2. 把 GitOps 仓库里的 `nginx.conf` 复制到本机 nginx 安装目录。
3. 执行 `nginx.exe -t` 检查配置。
4. 如果 nginx 已运行，则 reload；否则启动 nginx。

## 常用验证

```powershell
curl.exe http://127.0.0.1:18080/actuator/health/readiness
```

发交易后，到两个集群分别看日志：

```bash
kubectl logs -n bank deploy/customer-service --since=10m | grep "globalSerialNo"
kubectl logs -n bank deploy/account-service --since=10m | grep "globalSerialNo"
```

日志中通过下面字段区分集群：

```text
cluster=bank-sit-a
cluster=bank-sit-b
```

## 调整灰度比例

只改 `weight` 即可：

```nginx
server 192.168.30.130:30080 weight=9;
server 10.46.132.20:30080 weight=1;
```

表示约 90% 到 A，10% 到 B。

如果要临时切走 B，可以把 B 注释掉：

```nginx
upstream bank_gateway {
    server 192.168.30.130:30080 weight=1;
    # server 10.46.132.20:30080 weight=1;
}
```

改完后重新同步并 reload nginx。
