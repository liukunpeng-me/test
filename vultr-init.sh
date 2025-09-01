#!/bin/bash
sudo ufw disable
sudo systemctl stop ufw
sudo systemctl disable ufw
## curl https://raw.githubusercontent.com/liukunpeng-me/test/refs/heads/main/vultr-init.sh |bash
set -euo pipefail

# 清理临时文件
cleanup() {
    if [ -f "gost.tar.gz" ]; then
        rm -f gost.tar.gz
    fi
}
trap cleanup EXIT

# 检查 root 权限
if [[ "$EUID" -ne 0 ]]; then
    echo "$(tput setaf 1)错误：必须以 root 用户运行此脚本！$(tput sgr0)"
    exit 1
fi

# 配置参数（Linux amd64 架构专用下载地址）
DOWNLOAD_URL="https://github.com/go-gost/gost/releases/download/v3.2.5-nightly.20250830/gost_3.2.5-nightly.20250830_linux_amd64.tar.gz"
CONFIG_PATH="/etc/gost.yml"
SERVICE_PATH="/etc/systemd/system/gost.service"
LISTEN_PORT=1080
USERNAME="admin"
PASSWORD="a111111"

# 安装指定版本的 gost 二进制文件
install_gost() {
    # 验证系统架构是否匹配（仅支持 Linux amd64）
    if [[ "$(uname)" != "Linux" ]] || [[ "$(uname -m)" != "x86_64" ]]; then
        echo "$(tput setaf 1)错误：此脚本仅支持 Linux amd64 (x86_64) 架构系统$(tput sgr0)"
        exit 1
    fi

    # 下载指定版本
    echo "下载指定版本: $DOWNLOAD_URL..."
    if ! curl -fsSL -o gost.tar.gz "$DOWNLOAD_URL"; then
        echo "$(tput setaf 1)下载失败，请检查网络或下载地址是否有效$(tput sgr0)"
        exit 1
    fi

    # 安装二进制
    echo "安装 gost..."
    tar -xzf gost.tar.gz
    chmod +x gost
    mv gost /usr/local/bin/
    echo "$(tput setaf 2)gost 安装完成$(tput sgr0)"
}

# 创建配置文件
create_config() {
    echo "创建配置文件..."
    cat > "$CONFIG_PATH" << EOF
services:
- name: socks5-service
  addr: ":$LISTEN_PORT"
  handler:
    type: socks5
    auth:
      username: $USERNAME
      password: $PASSWORD
  listener:
    type: tcp

log:
  output: stderr
  level: info
EOF
    chmod 600 "$CONFIG_PATH"  # 限制权限
    echo "$(tput setaf 2)配置文件已创建: $CONFIG_PATH$(tput sgr0)"
}

# 检查端口占用
check_port() {
    if netstat -tulpn | grep -q ":$LISTEN_PORT "; then
        echo "$(tput setaf 1)错误：端口 $LISTEN_PORT 已被占用$(tput sgr0)"
        exit 1
    fi
}

# 设置系统服务
setup_service() {
    check_port

    echo "配置系统服务..."
    cat > "$SERVICE_PATH" << EOF
[Unit]
Description=GO Simple Tunnel (gost) service
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/gost -C $CONFIG_PATH
Restart=always
RestartSec=5s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    chmod 644 "$SERVICE_PATH"
    systemctl daemon-reload
    systemctl enable --now gost
    echo "$(tput setaf 2)系统服务已启动$(tput sgr0)"
}

# 卸载功能
uninstall() {
    echo "卸载 gost..."
    systemctl stop gost 2>/dev/null
    systemctl disable gost 2>/dev/null
    rm -f "$SERVICE_PATH" "$CONFIG_PATH" /usr/local/bin/gost
    systemctl daemon-reload
    echo "$(tput setaf 2)卸载完成$(tput sgr0)"
    exit 0
}

# 主逻辑
main() {
    if [ "$#" -eq 1 ] && [ "$1" = "--uninstall" ]; then
        uninstall
    fi

    install_gost
    create_config
    setup_service

    echo -e "\n$(tput setaf 2)部署完成！$(tput sgr0)"
    echo "Socks5 代理信息:"
    echo "  地址: 0.0.0.0:$LISTEN_PORT"
    echo "  用户名: $USERNAME"
    echo "  密码: $PASSWORD"
    echo "服务状态: systemctl status gost"
    echo "日志查看: journalctl -u gost -f"
}

main "$@"



