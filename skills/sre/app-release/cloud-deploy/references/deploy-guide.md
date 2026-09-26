# 华为云部署领域指南

## 1. hcloud CLI 安装

worker 无 hcloud 时自动安装（KooCLI = 华为云 CLI）：

```bash
if ! command -v hcloud >/dev/null 2>&1; then
  # 架构判定
  case "$(uname -m)" in
    x86_64|amd64) APP_ARCH="amd64" ;;
    aarch64|arm64) APP_ARCH="arm64" ;;
    *) echo "unsupported arch: $(uname -m)"; exit 1 ;;
  esac
  DL_URL="https://cn-north-4-hdn-koocli.obs.cn-north-4.myhuaweicloud.com/cli/latest/huaweicloud-cli-linux-${APP_ARCH}.tar.gz"
  curl -fsSL --max-time 300 -o /tmp/hcloud.tar.gz "$DL_URL" || exit 1
  mkdir -p /tmp/hcloud-x && tar -xzf /tmp/hcloud.tar.gz -C /tmp/hcloud-x
  find /tmp/hcloud-x -type f -name hcloud -exec install -m 0755 {} /usr/local/bin/hcloud \;
  echo y | hcloud configure set --cli-agree-privacy-statement=true
fi
hcloud version
```

**注意**：
- arm64 必须下 `-arm64-` 包，amd64 下 `-amd64-`，下错会 `Exec format error`
- 首次运行必须 `echo y | hcloud configure set --cli-agree-privacy-statement=true`，否则卡在隐私声明
- 下载可能慢（arm64 曾 90s+），`--max-time` 给足 300s

## 2. 认证配置（profile 隔离）

```bash
HC_PROFILE="task-$$"
hcloud configure set --cli-profile="$HC_PROFILE" \
  --cli-access-key="$HUAWEICLOUD_SDK_AK" \
  --cli-secret-key="$HUAWEICLOUD_SDK_SK" \
  --cli-region=cn-north-4 --cli-mode=AKSK

# 包装函数：所有 hcloud 命令通过它执行
hc() { hcloud "$@" --cli-profile="$HC_PROFILE"; }
obs() { obsutil "$@" -i "$HUAWEICLOUD_SDK_AK" -k "$HUAWEICLOUD_SDK_SK" \
  -e obs.cn-north-4.myhuaweicloud.com; }

# 部署结束后清理
trap 'hcloud configure delete --cli-profile="$HC_PROFILE" 2>/dev/null || true' EXIT
```

**严禁** `hcloud configure set` 改 default profile——并发 task 会互相覆盖 AK/SK 导致资源创建到错误账号。

## 3. ECS 创建

### 3.1 幂等检查

```bash
EXISTING_ECS=$(hc ECS ListServersDetails --cli-region=cn-north-4 2>/dev/null \
  | grep -B5 -A20 "\"name\": \"deploy-${REPO_FULL_NAME//\//-}" \
  | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | tail -1)
if [ -n "$EXISTING_ECS" ]; then
  ECS_IP="$EXISTING_ECS"
else
  # 新建流程
fi
```

### 3.2 动态选规格

```bash
ARCH=$(uname -m)
MIN_FLAVOR=$(hc ECS ListFlavors --cli-region=cn-north-4 2>/dev/null | python3 -c "
import json,sys
arch_map={'x86_64':'x86','amd64':'x86','aarch64':'ARM','arm64':'ARM'}
want=arch_map.get('$ARCH'.strip(),'x86')
data=json.load(sys.stdin)
flavors=data.get('flavors',[]) if isinstance(data,dict) else data
candidates=[f for f in flavors
  if f.get('os_extra_specs',{}).get('ecs:architecture','')==want
  and f.get('is_public',True)]
candidates.sort(key=lambda f:(f.get('vcpus',999),f.get('ram',99999)))
print(candidates[0]['id'] if candidates else 's6.small.1')
" 2>/dev/null)
```

### 3.3 创建 ECS

```bash
# 密钥对（不存在则创建）
if ! hc ECS NovaListKeypairs --cli-region=cn-north-4 2>/dev/null | grep -q "grape-deploy-kp"; then
  hc ECS NovaCreateKeypair --cli-region=cn-north-4 \
    --name=grape-deploy-kp --public_key="$(cat ~/.ssh/id_ed25519.pub)" 2>/dev/null || true
fi

INSTANCE_NAME="deploy-${REPO_FULL_NAME//\//-}-$(date +%H%M%S)"
hc ECS CreateServer --cli-region=cn-north-4 \
  --name "$INSTANCE_NAME" --flavor "$MIN_FLAVOR" --image "Ubuntu 22.04" \
  --charging-mode postPaid --security-group "default" \
  --keypair "grape-deploy-kp" \
  --server.availability_zone=cn-north-4a \
  --server.publicip.eip.bandwidth.name=auto-eip \
  --server.publicip.eip.bandwidth.size=5

# 等待 running，获取浮动 IP
ECS_IP=$(hc ECS ListServersDetails --cli-region=cn-north-4 2>/dev/null \
  | grep -A20 "$INSTANCE_NAME" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | tail -1)
```

**关键约束**：
- AZ 必须是 `cn-north-4a` 或 `cn-north-4b`，**禁止 `cn-north-4g`**（DPDK 网卡，SSH 连不上）
- 必须带 keypair，否则建完 SSH 连不上
- EIP 必须在创建时自动关联（`--server.publicip.eip.*`），不要先建再手动关联
- 不硬编码 flavor，动态查询最小可用按量规格

## 4. SSH 部署

### 4.0 关联仓库部署（多仓库场景）

当 `$GRAPE_LINKED_REPOS` 非空时，需要对每个关联仓库分别构建并部署到同一 ECS：

```bash
# 解析关联仓库 worktree 列表（平台自动初始化）
if [ -n "$GRAPE_LINKED_WORKTREES" ]; then
  echo "$GRAPE_LINKED_WORKTREES" | python3 -c "
import json,sys
for w in json.load(sys.stdin):
    print(f\"{w['repo_key']}\t{w['branch']}\t{w['dir']}\")
" | while IFS=$'\t' read -r rk br dir; do
    REPO_SHORT="${rk#gitcode:}"
    REPO_NAME="${REPO_SHORT#*/}"
    echo "=== 部署关联仓库: $REPO_SHORT ==="
    cd "$dir" 2>/dev/null || continue
    # 构建按项目类型执行（同主仓库 §4.2）
    # 上传到 ECS 独立目录
    ssh -o StrictHostKeyChecking=no root@"$ECS_IP" "mkdir -p /opt/$REPO_NAME"
    scp -o StrictHostKeyChecking=no -r ./* root@"$ECS_IP":/opt/$REPO_NAME/
    # SSH 启动服务（不同端口，避免与主仓库冲突）
    ssh -o StrictHostKeyChecking=no root@"$ECS_IP" 'bash -s' << LINKED_EOF
cd /opt/$REPO_NAME
# 按项目类型启动（示例：Java 后端用 8080 端口）
# mvn spring-boot:run -Dserver.port=8080 或 nohup java -jar target/*.jar --server.port=8080 &
LINKED_EOF
done
fi
```

**关键**：每个关联仓库部署到 `/opt/<repo_name>` 独立目录，使用不同端口，避免与主仓库冲突。

### 4.1 上传代码

```bash
ssh -o StrictHostKeyChecking=no root@"$ECS_IP" "mkdir -p /opt/$REPO_NAME"
scp -o StrictHostKeyChecking=no -r "$WORKDIR"/* root@"$ECS_IP":/opt/$REPO_NAME/
ssh-copy-id -o StrictHostKeyChecking=no root@"$ECS_IP" 2>/dev/null || true
```

### 4.2 单条 SSH 完成部署

```bash
ssh -o StrictHostKeyChecking=no root@"$ECS_IP" 'bash -s' << 'DEPLOY_EOF'
set -e
# DNS 修复（systemd-resolved 可能解析失败）
echo 'nameserver 8.8.8.8' > /etc/resolv.conf
echo 'nameserver 223.5.5.5' >> /etc/resolv.conf

cd /opt/__REPO_NAME__
# apt 镜像加速
sed -i 's|http://archive.ubuntu.com|http://mirrors.huaweicloud.com|g' /etc/apt/sources.list 2>/dev/null || true
apt-get update -qq
apt-get install -y -qq python3 python3-pip python3-venv python3.10-venv 2>/dev/null || \
  apt-get install -y -qq python3 python3-pip python3-venv

# venv + 依赖（华为云 PyPI 镜像优先）
rm -rf venv
python3 -m venv venv
venv/bin/pip install -q --upgrade pip \
  -i https://mirrors.huaweicloud.com/repository/pypi/simple \
  --trusted-host mirrors.huaweicloud.com || true
for i in 1 2 3; do
  venv/bin/pip install -q -r requirements.txt gunicorn \
    -i https://mirrors.huaweicloud.com/repository/pypi/simple \
    --trusted-host mirrors.huaweicloud.com && break
  echo "pip retry $i/3"; sleep 5
done

# 启动（按端口精确清理旧进程，禁止 pkill -f）
ss -tlnp 2>/dev/null | grep ':5000' | grep -oP 'pid=\K[0-9]+' | sort -u | xargs -r kill 2>/dev/null || true
sleep 1
nohup venv/bin/gunicorn -w 2 -b 0.0.0.0:5000 app:app > /tmp/flask.log 2>&1 &
sleep 4
DEPLOY_EOF
```

**注意**：
- 必须用单条 SSH 会话跑完，防多命令叠加超时
- 严禁 `pkill -f gunicorn`（会误杀 agent 进程）
- pip 优先用华为云镜像，回退官方源重试 3 次

## 5. 验证

```bash
# 端口检查
ssh root@"$ECS_IP" "ss -tlnp | grep 5000"

# HTTP 验证（期望 200）
curl -s -o /dev/null -w '%{http_code}' "http://$ECS_IP:5000/"
curl -s -o /dev/null -w '%{http_code}' "http://$ECS_IP:5000/post/1"
```

## 6. 资源释放

### 6.1 收集资源信息

从 Issue 正文/评论提取：ECS 实例名/IP、RDS 实例名、OBS 桶名。
信息不完整时用 `grape git-repo issues comments list` 查评论补充。

### 6.2 释放 ECS

```bash
# 查询
hc ECS ListServersDetails --cli-region=cn-north-4 | python3 -c "
import json,sys
data=json.load(sys.stdin)
for s in data.get('servers',[]):
    print(s.get('id',''), s.get('name',''), s.get('status',''))
"
# 删除
hc ECS DeleteServer --cli-region=cn-north-4 --server_id="<INSTANCE_ID>"
# 验证：再次查询确认已不存在
```

### 6.3 释放 RDS

```bash
hc RDS ListInstances --cli-region=cn-north-4 | python3 -c "
import json,sys
data=json.load(sys.stdin)
for i in data.get('instances',[]):
    print(i.get('id',''), i.get('name',''), i.get('status',''))
"
hc RDS DeleteInstance --cli-region=cn-north-4 --instance_id="<RDS_ID>"
```

### 6.4 释放 OBS 桶

```bash
# 先清空（非空桶无法删除）
obs rm <BUCKET_NAME> -r -f 2>/dev/null || true
# 再删桶
obs rm <BUCKET_NAME> -b 2>/dev/null || true
```

### 6.5 释放 EIP

```bash
hc EIP ListPublicIps --cli-region=cn-north-4 2>/dev/null | python3 -c "
import json,sys
data=json.load(sys.stdin)
for e in data.get('publicips',[]):
    print(e.get('id',''), e.get('public_ip_address',''), e.get('status',''))
"
hc EIP DeletePublicIp --cli-region=cn-north-4 --publicip_id="<EIP_ID>"
```

**释放注意**：
- 先查再删，确认资源存在后操作
- ECS 先删，关联 EIP 可能自动释放，独立 EIP 需手动删
- OBS 桶必须先清空对象
- RDS 删除可能异步，等几分钟再验证
- 幂等：重复释放已不存在资源视为成功
