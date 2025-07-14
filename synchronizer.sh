#!/bin/bash

# 主菜单函数
show_menu() {
    clear
    echo "====================================="
    echo "  Synchronizer 安装与启动脚本"
    echo "  作者：@ferdie_jhovie"
    echo "  注意：这是一个免费脚本！"
    echo "====================================="
    echo "1. 部署节点（安装 Docker、Node.js、npm、pm2、synchronizer-cli 并启动服务）"
    echo "2. 查看 pm2 进程列表"
    echo "3. 查看日志 (pm2 logs -f)"
    echo "4. 退出"
    echo "====================================="
    echo "请输入选项 (1-4)："
}

# 部署节点函数（整合所有安装和启动步骤）
deploy_node() {
    # 安装依赖
    install_dep() {
        if ! command -v node &>/dev/null; then
            curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
            sudo apt install -y nodejs
            if command -v node &>/dev/null && command -v npm &>/dev/null; then
                echo "Node.js 和 npm 安装成功！版本信息："
                node --version
                npm --version
            else
                echo "Node.js 或 npm 安装失败，请检查错误信息。"
                exit 1
            fi
        else
            echo "Node.js 和 npm 已安装，版本信息："
            node --version
            npm --version
        fi

        if ! command -v docker &>/dev/null; then
            curl -fsSL https://get.docker.com | sh
            sudo usermod -aG docker $USER
            if command -v docker &>/dev/null; then
                echo "Docker 安装成功！版本信息："
                docker --version
            else
                echo "Docker 安装失败，请检查错误信息。"
                exit 1
            fi
        else
            echo "Docker 已安装，版本信息："
            docker --version
        fi

        sudo npm i -g pm2 synchronizer-cli
        if command -v pm2 &>/dev/null && command -v synchronizer &>/dev/null; then
            echo "pm2 和 synchronizer-cli 安装成功！版本信息："
            pm2 --version
            synchronizer --version
        else
            echo "pm2 或 synchronizer-cli 安装失败，请检查错误信息。"
            exit 1
        fi

        synchronizer install-docker
        echo "✅ 依赖安装完成"
        read -rp "按回车继续..."
    }

    # 生成 .env 文件（仅生成一个 .env 文件，移除代理）
    gen_envs() {
        echo "请输入账户信息，格式：WALLET----synqKey"
        echo "示例: 0x123abc----ae1c98c9-xxxx-xxxx-xxxx"
        echo "----------------------------------------"
        
        # 读取单行输入
        read -r line
        if [[ -z $line ]]; then
            echo "❌ 未输入数据"
            read -rp "按回车继续..."
            return
        fi
        
        # 使用awk分割输入的行，使用----作为分隔符
        WAL=$(echo "$line" | awk -F '----' '{print $1}')
        KEY=$(echo "$line" | awk -F '----' '{print $2}')
        
        if [[ -z $WAL || -z $KEY ]]; then
            echo "❌ 格式错误，请确保输入格式为 WALLET----synqKey"
            read -rp "按回车继续..."
            return
        fi
        
        # 生成单一的 .env 文件
        cat > ".env" <<EOF
WALLET=$WAL
KEY=$KEY
EOF
        echo "✔️ 已写入 .env ($WAL)"
        echo "✅ 已生成 .env 配置文件"
        read -rp "按回车继续..."
    }

    # 启动节点
    start_nodes() {
        echo "🔄 清空旧 pm2 记录..."
        pm2 delete all &>/dev/null || true
        
        echo "🧹 清理所有旧 Docker 容器..."
        docker ps -aq --filter "name=synchronizer-" | xargs -r docker rm -f

        # 检查 .env 文件是否存在
        if [[ ! -f .env ]]; then
            echo "❌ 未找到 .env 文件，请确保已生成配置文件"
            read -rp "按回车继续..."
            return
        fi

        # 加载 .env 文件
        source ".env"
        
        # 设置固定端口
        http_port=8080
        metrics_port=9090
        
        # 创建唯一的同步名称
        sync_name="synq-$(date +%s)"
        
        echo "🚀 启动节点 (端口: $http_port)..."
        pm2 start bash --name "synchronize" -- -c \
            "docker run --rm --name synchronizer \
            --platform linux/amd64 \
            -p $http_port:8080 \
            -p $metrics_port:9090 \
            -e SYNC_HTTP_PORT=$http_port \
            -e SYNC_METRICS_PORT=$metrics_port \
            cdrakep/synqchronizer:latest \
            --depin wss://api.multisynq.io/depin \
            --sync-name $sync_name \
            --launcher cli \
            --key $KEY \
            --wallet $WALLET \
            --time-stabilized"
        
        if pm2 list | grep -q "synchronize"; then
            echo "✅ 节点已启动"
            echo "📊 节点状态页面可通过以下地址访问:"
            echo "  - http://localhost:$http_port"
        else
            echo "❌ 节点启动失败，请检查错误信息"
            read -rp "按回车继续..."
            return
        fi
        
        read -rp "按回车继续..."
    }

    # 执行安装依赖
    install_dep

    # 执行生成 .env 文件
    gen_envs

    # 执行启动节点
    start_nodes
}

# 查看 pm2 进程列表
show_pm2_list() {
    echo "当前 pm2 进程列表："
    pm2 list
}

# 查看日志
show_pm2_logs() {
    echo "正在显示 pm2 日志 (按 Ctrl+C 返回菜单)..."
    pm2 logs -f synchronize
}

# 主循环
while true; do
    show_menu
    read choice
    case $choice in
        1)
            deploy_node
            read -n 1 -s -r -p "按任意键返回菜单..."
            ;;
        2)
            show_pm2_list
            read -n 1 -s -r -p "按任意键返回菜单..."
            ;;
        3)
            show_pm2_logs
            read -n 1 -s -r -p "按任意键返回菜单..."
            ;;
        4)
            echo "退出脚本，感谢使用！"
            exit 0
            ;;
        *)
            echo "无效选项，请输入 1-4。"
            read -n 1 -s -r -p "按任意键返回菜单..."
            ;;
    esac
done
