#!/usr/bin/env bash
set -e

# ========== 全局端口配置 ==========
# 仅用于仪表盘，移除节点端口映射以匹配官方单开
DASHBOARD_HTTP_PORT=8000
DASHBOARD_METRICS_PORT=8100

# ========== 菜单 ==========
menu() {
  clear
  echo "======= Multisynq CLI 多代理管理 ======="
  echo "  作者：@ferdie_jhovie"
  echo "  注意：这是一个免费脚本！感谢群友@galaxy的代码提供"
  echo "========================================"
  echo "1) 安装依赖（Node·Docker·CLI）"
  echo "2) 生成多个 .env.mX 配置"
  echo "3) 启动所有节点（pm2，含代理）"
  echo "4) 查看节点状态 (pm2 ls)"
  echo "5) 查看节点日志（选择节点）"
  echo "6) 停止所有节点并清理容器"
  echo "7) 查询积分（支持多代理）"
  echo "8) 启动仪表盘（可选密码）"
  echo "9) 检查 Docker 镜像更新"
  echo "10) 查看系统状态和服务日志"
  echo "0) 退出"
  echo "========================================"
  read -rp "请输入选项: " opt
  case $opt in
    1) install_dep ;;
    2) gen_envs ;;
    3) start_nodes ;;
    4) pm2 ls; read -rp "按回车继续..." ;;
    5) show_logs ;;
    6) stop_all ;;
    7) check_points ;;
    8) start_dashboard ;;
    9) synchronize check-updates; read -rp "按回车继续..." ;;
    10) synchronize status; read -rp "按回车继续..." ;;
    0) exit 0 ;;
    *) echo "❌ 无效选项"; sleep 1 ;;
  esac
}

# ========== 安装依赖 ==========
install_dep() {
  command -v node &>/dev/null || {
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    sudo apt install -y nodejs
  }
  command -v docker &>/dev/null || {
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker $USER
  }
  sudo npm i -g pm2 synchronizer-cli
  synchronize install-docker
  echo "✅ 依赖安装完成"
  read -rp "按回车继续..."
}

# ========== 生成配置 ==========
gen_envs() {
  CONFIG_DIR="/root/.synchronizer-cli"
  
  echo "🌀 开始循环批量生成 .env.mX 和 config.jsonX（按 Ctrl + C 停止）"

  while true; do
    echo
    echo "================ 新一轮生成开始 ================"

    # 检查 synchronize 命令是否存在
    if ! command -v synchronize &>/dev/null; then
      echo "❌ 未找到 synchronize 命令，请确认是否已安装。"
      read -rp "按回车继续..."
      return 1
    fi

    # 执行 init
    echo "🚀 正在运行：synchronize init ..."
    synchronize init

    CONFIG_FILE="$CONFIG_DIR/config.json"
    if [ ! -f "$CONFIG_FILE" ]; then
      echo "❌ 未找到 $CONFIG_FILE，跳过当前轮次。"
      read -rp "按回车继续..."
      continue
    fi

    # 提取字段
    WALLET=$(jq -r .wallet "$CONFIG_FILE")
    KEY=$(jq -r .key "$CONFIG_FILE")
    SYNC_NAME=$(jq -r .syncHash "$CONFIG_FILE")

    # 手动输入代理地址
    read -rp "🌐 请输入代理地址（例如：http://user:pass@ip:port，留空跳过）: " PROXY
    PROXY=$(echo "$PROXY" | tr -d '[:space:]')

    # 验证必填字段
    if [[ -z "$WALLET" || -z "$KEY" || -z "$SYNC_NAME" ]]; then
      echo "❌ 缺少必要字段（WALLET, KEY, SYNC_NAME），跳过当前轮次"
      read -rp "按回车继续..."
      continue
    fi

    # 自动编号 .env.mX
    idx=1
    while [ -e ".env.m$idx" ]; do
      idx=$((idx+1))
    done
    env_file=".env.m$idx"

    # 写入 .env 文件
    {
      echo "WALLET=$WALLET"
      echo "KEY=$KEY"
      echo "SYNC_NAME=$SYNC_NAME"
      [[ -n "$PROXY" ]] && echo "PROXY=$PROXY"
    } > "$env_file"

    echo "✅ 已创建：$env_file"

    # 备份 config.json
    j=1
    while [ -e "$CONFIG_DIR/config.json$j" ]; do
      j=$((j+1))
    done
    mv "$CONFIG_FILE" "$CONFIG_DIR/config.json$j"
    echo "📦 config.json 已保存为：config.json$j"

    echo "✅ 本轮生成完成。准备下一轮（Ctrl + C 退出）..."
    read -rp "按回车继续..."
  done
}

# ========== 启动所有节点 ==========
start_nodes() {
  pm2 delete all &>/dev/null || true
  docker ps -aq --filter "name=synchronizer-" | xargs -r docker rm -f
  idx=1
  for f in .env.m*; do
    [[ -f $f ]] || continue
    name="${f##*.}"
    source "$f"
    if [[ -z $SYNC_NAME ]]; then
      echo "❌ $f 缺少 SYNC_NAME，跳过启动"
      continue
    fi
    if [[ -n $PROXY ]]; then
      echo "🚀 启动 $name 使用代理 $PROXY (sync-name: $SYNC_NAME)"
      pm2 start bash --name "$name" -- -c \
        "http_proxy=$PROXY HTTPS_PROXY=$PROXY \
        docker run --rm --name synchronizer-$name \
        --platform linux/amd64 \
        cdrakep/synqchronizer:latest \
        --depin wss://api.multisynq.io/depin \
        --sync-name $SYNC_NAME \
        --launcher cli-2.6.1/docker-2025-06-24 \
        --key $KEY \
        --wallet $WALLET \
        --time-stabilized"
    else
      echo "🚀 启动 $name 无代理 (sync-name: $SYNC_NAME)"
      pm2 start bash --name "$name" -- -c \
        "docker run --rm --name synchronizer-$name \
        --platform linux/amd64 \
        cdrakep/synqchronizer:latest \
        --depin wss://api.multisynq.io/depin \
        --sync-name $SYNC_NAME \
        --launcher cli-2.6.1/docker-2025-06-24 \
        --key $KEY \
        --wallet $WALLET \
        --time-stabilized"
    fi
    idx=$((idx+1))
  done
  echo "✅ 所有节点已启动"
  read -rp "按回车继续..."
}

# ========== 停止并清理 ==========
stop_all() {
  pm2 stop all || true
  pm2 delete all || true
  docker ps -aq --filter "name=synchronizer-" | xargs -r docker rm -f
  echo "✅ 所有节点和容器已停止"
  read -rp "按回车继续..."
}

# ========== 查看日志 ==========
show_logs() {
  echo "可用节点："
  pm2 ls | awk 'NR>3 && $2 !~ /-/ {print $2}' | sort | uniq || echo "无运行中的节点"
  echo "可用 .env 文件："
  ls .env.m* 2>/dev/null | sed 's/.env.//' || echo "无 .env.m* 文件"
  read -rp $'\n输入节点名（如 m1），或回车查看全部: ' name
  if [[ -n $name ]]; then
    if pm2 list | grep -q "$name"; then
      pm2 logs "$name" --lines 50
    else
      echo "❌ 节点 $name 未运行"
    fi
  else
    pm2 logs --lines 50
  fi
  read -rp "按回车继续..."
}

# ========== 查询积分 ==========
check_points() {
  echo "查询所有 .env.mX 积分..."
  for f in .env.m*; do
    [[ -f $f ]] || continue
    name="${f##*.}"
    source "$f"
    echo -e "\n🔹 [$name] $WALLET (sync-name: $SYNC_NAME)"
    url="https://startsynqing.com/api/external/multisynq/synqers/$WALLET"
    result=$(curl -s "$url")
    credits=$(echo "$result" | grep -o '"serviceCredits":[0-9]*' | cut -d':' -f2)
    if [[ -n $credits ]]; then
      echo "✅ 总积分: $credits"
    else
      echo "❌ API 查询失败，使用 CLI 回退..."
      synchronize points "$WALLET"
    fi
  done
  read -rp "按回车继续..."
}

# ========== 启动仪表盘 ==========
start_dashboard() {
  echo "是否为单个节点启动仪表盘？(y/N)"
  read -r single
  if [[ $single == "y" || $single == "Y" ]]; then
    ls .env.m* | sed 's/.env.//'
    read -rp "请输入节点名（如 m1）: " name
    [[ -f ".env.$name" ]] || { echo "❌ 配置不存在"; read -rp "按回车继续..."; return; }
    source ".env.$name"
    port=$((DASHBOARD_HTTP_PORT + ${name#m}))
    cid=$(docker ps --filter "name=synchronizer-$name" -q)
    [[ -z $cid ]] && { echo "⚠️ 容器未运行"; read -rp "按回车继续..."; return; }
    read -rp "仪表盘密码（可选）: " pwd
    if [[ -n $pwd ]]; then
      synchronize web --port "$port" --password "$pwd" --container "$cid" &
    else
      synchronize web --port "$port" --container "$cid" &
    fi
    echo "🌐 仪表盘已启动：http://localhost:$port"
  else
    idx=1
    for f in .env.m*; do
      [[ -f $f ]] || continue
      name="${f##*.}"
      port=$((DASHBOARD_HTTP_PORT + idx))
      cid=$(docker ps --filter "name=synchronizer-$name" -q)
      [[ -n $cid ]] && synchronize web --port "$port" --container "$cid" &
      echo "🌐 [$name] http://localhost:$port"
      idx=$((idx+1))
    done
  fi
  read -rp "按回车继续..."
}

# ========== 主循环 ==========
while true; do menu; done
