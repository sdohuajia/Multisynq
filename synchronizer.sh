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
    idx=1
    echo "请输入配置数据，每组配置分行输入（SYNC_NAME 必须，PROXY 可选），结束请输入 'done'"
    echo "注意：SYNC_NAME 从 Multisynq 平台获取（例如 synq-m1-abcdef123456）"
    echo "示例:"
    echo "WALLET: 0x123abc..."
    echo "KEY: ae1c98c9-xxxx-xxxx-xxxx"
    echo "SYNC_NAME: synq-m1-abcdef123456"
    echo "PROXY: http://user:pass@ip:port"
    echo "输入 'done' 开始下一组或结束"
    
    temp=$(mktemp)
    while true; do
      echo -e "\n=== 输入第 $idx 组配置 ==="
      read -rp "WALLET: " WALLET
      if [[ "$WALLET" == "done" ]]; then
        break
      fi
      read -rp "KEY: " KEY
      read -rp "SYNC_NAME: " SYNC_NAME
      read -rp "PROXY (可选，直接回车跳过): " PROXY
      
      WALLET=$(echo "$WALLET" | tr -d '[:space:]')
      KEY=$(echo "$KEY" | tr -d '[:space:]')
      SYNC_NAME=$(echo "$SYNC_NAME" | tr -d '[:space:]')
      PROXY=$(echo "$PROXY" | tr -d '[:space:]')
      
      if [[ -z "$WALLET" || -z "$KEY" || -z "$SYNC_NAME" ]]; then
        echo "⚠️ 必填字段（WALLET, KEY, SYNC_NAME）不能为空，跳过此组"
        continue
      fi
      
      {
        echo "WALLET=$WALLET"
        echo "KEY=$KEY"
        echo "SYNC_NAME=$SYNC_NAME"
        [[ -n "$PROXY" ]] && echo "PROXY=$PROXY"
      } >> "$temp"
      
      echo "✔️ 已记录配置 (WALLET: $WALLET, SYNC_NAME: $SYNC_NAME)"
      idx=$((idx+1))
    done
    
    if [[ ! -s "$temp" ]]; then
      echo "❌ 未检测到有效配置数据"
      rm -f "$temp"
      read -rp "按回车继续..."
      return
    fi
    
    idx=1
    while IFS= read -r line; do
      if [[ "$line" == WALLET=* ]]; then
        f=".env.m$idx"
        echo > "$f"
      fi
      echo "$line" >> "$f"
      if [[ "$line" == SYNC_NAME=* || "$line" == PROXY=* ]]; then
        echo "✔️ 已写入 $f (${line#SYNC_NAME=})"
        idx=$((idx+1))
      fi
    done < "$temp"
    
    rm -f "$temp"
    total=$((idx-1))
    if [[ $total -eq 0 ]]; then
      echo "⚠️ 未生成任何配置文件"
    else
      echo "✅ 共生成 $total 个配置"
    fi
    read -rp "按回车继续..."
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
