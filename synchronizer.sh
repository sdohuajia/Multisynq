#!/bin/bash

# 检查 Docker 是否已安装
if ! command -v docker &> /dev/null; then
    echo "Docker 未安装，正在安装 Docker..."

    # 更新包索引
    sudo apt-get update

    # 安装必要的依赖
    sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common

    # 添加 Docker 官方 GPG 密钥
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

    # 添加 Docker 仓库
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

    # 再次更新包索引
    sudo apt-get update

    # 安装最新版本的 Docker
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io

    # 启动 Docker 服务并设置开机自启
    sudo systemctl start docker
    sudo systemctl enable docker

    # 验证 Docker 安装
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

# 检查 Node.js 和 npm 是否已安装
if ! command -v node &> /dev/null || ! command -v npm &> /dev/null; then
    echo "Node.js 或 npm 未安装，正在安装 Node.js 和 npm..."

    # 安装 Node.js（包含 npm）
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs

    # 验证 Node.js 和 npm 安装
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

# 检查 pm2 是否已安装
if ! command -v pm2 &> /dev/null; then
    echo "pm2 未安装，正在安装 pm2..."
    sudo npm install -g pm2

    # 验证 pm2 安装
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

# 全局安装 synchronizer-cli
echo "正在全局安装 synchronizer-cli..."
sudo npm install -g synchronizer-cli

# 验证 synchronizer-cli 安装
if command -v synchronizer &> /dev/null; then
    echo "synchronizer-cli 安装成功！"
else
    echo "synchronizer-cli 安装失败，请检查错误信息。"
    exit 1
fi

# 提示用户准备 Synq 密钥、钱包地址和同步名称
echo "即将执行 synchronize init，请准备以下信息："
echo "1. 您的 Synq 密钥（必填）"
echo "2. 您的钱包地址（必填）"
echo "3. 同步名称（可选，按回车可跳过）"
echo "请在接下来的交互中根据提示输入以上信息。"
read -p "按回车键继续执行 synchronize init..." dummy

# 执行 synchronize init，交给用户手动填写
echo "正在执行 synchronize init，请按照提示手动填写信息..."
synchronizer init

# 检查 synchronize init 是否成功
if [ $? -eq 0 ]; then
    echo "synchronize init 执行成功！"
else
    echo "synchronize init 执行失败，请检查错误信息。"
    exit 1
fi

# 执行 pm2 start "synchronize start" --name synchronize
echo "正在启动 synchronize 服务..."
pm2 start "synchronize start" --name synchronize

# 验证 pm2 服务是否启动成功
if pm2 list | grep -q "synchronize"; then
    echo "synchronize 服务通过 pm2 启动成功！"
    pm2 list
else
    echo "synchronize 服务启动失败，请检查错误信息。"
    exit 1
fi
