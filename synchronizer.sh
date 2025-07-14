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
    # 检查并安装 Docker
    if ! command -v docker &> /dev/null; then
        echo "Docker 未安装，正在安装 Docker..."
        sudo apt-get update
        sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
        sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io
        sudo systemctl start docker
        sudo systemctl enable docker
        if command -v docker &> /dev/null; then
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

    # 检查并安装 Node.js 和 npm
    if ! command -v node &> /dev/null || ! command -v npm &> /dev/null; then
        echo "Node.js 或 npm 未安装，正在安装 Node.js 和 npm..."
        curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
        sudo apt-get install -y nodejs
        if command -v node &> /dev/null && command -v npm &> /dev/null; then
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

    # 检查并安装 pm2
    if ! command -v pm2 &> /dev/null; then
        echo "pm2 未安装，正在安装 pm2..."
        sudo npm install -g pm2
        if command -v pm2 &> /dev/null; then
            echo "pm2 安装成功！版本信息："
            pm2 --version
        else
            echo "pm2 安装失败，请检查错误信息。"
            exit 1
        fi
    else
        echo "pm2 已安装，版本信息："
        pm2 --version
    fi

    # 安装 synchronizer-cli
    echo "正在全局安装 synchronizer-cli..."
    sudo npm install -g synchronizer-cli
    if command -v synchronizer &> /dev/null; then
        echo "synchronizer-cli 安装成功！"
    else
        echo "synchronizer-cli 安装失败，请检查错误信息。"
        exit 1
    fi

    # 执行 synchronize init
    echo "即将执行 synchronize init，请准备以下信息："
    echo "1. 您的 Synq 密钥（必填）"
    echo "2. 您的钱包地址（必填）"
    echo "3. 同步名称（可选，按回车可跳过）"
    read -p "按回车键继续执行 synchronize init..." dummy
    echo "正在执行 synchronize init，请按照提示手动填写信息..."
    synchronizer init
    if [ $? -eq 0 ]; then
        echo "synchronize init 执行成功！"
    else
        echo "synchronize init 执行失败，请检查错误信息。"
        exit 1
    fi

    # 启动 synchronize 服务
    echo "正在启动 synchronize 服务..."
    pm2 start "synchronizer start" --name synchronize
    if pm2 list | grep -q "synchronize"; then
        echo "synchronize 服务通过 pm2 启动成功！"
        pm2 list
    else
        echo "synchronize 服务启动失败，请检查错误信息。"
        exit 1
    fi
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
