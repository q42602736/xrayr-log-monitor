#!/bin/bash

# XrayR日志监控卸载脚本
# GitHub: https://github.com/your-username/xrayr-log-monitor

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}  XrayR日志监控卸载脚本${NC}"
    echo -e "${BLUE}================================${NC}"
    echo ""
}

# 检查权限
check_permissions() {
    if [ "$EUID" -ne 0 ]; then
        print_error "请以root用户身份运行此脚本"
        echo "使用方法: sudo bash uninstall.sh"
        exit 1
    fi
}

# 卸载函数
uninstall_monitor() {
    print_message "开始卸载XrayR日志监控..."
    
    # 删除crontab任务
    print_message "删除定时任务..."
    crontab -l 2>/dev/null | grep -v "xrayr_log_cleanup" | crontab - 2>/dev/null || true
    
    # 删除脚本目录
    SCRIPT_DIR="/root/xrayr_monitor"
    if [ -d "$SCRIPT_DIR" ]; then
        print_message "删除脚本目录: $SCRIPT_DIR"
        rm -rf "$SCRIPT_DIR"
    fi
    
    # 询问是否删除日志文件
    echo ""
    read -p "是否删除日志文件 /var/log/xrayr_cleanup.log? (y/N): " delete_log
    if [[ $delete_log =~ ^[Yy]$ ]]; then
        if [ -f "/var/log/xrayr_cleanup.log" ]; then
            rm -f "/var/log/xrayr_cleanup.log"
            print_message "已删除日志文件"
        fi
    else
        print_message "保留日志文件: /var/log/xrayr_cleanup.log"
    fi
    
    # 询问是否删除备份文件
    echo ""
    read -p "是否删除XrayR日志备份文件? (y/N): " delete_backup
    if [[ $delete_backup =~ ^[Yy]$ ]]; then
        BACKUP_COUNT=$(find /etc/XrayR/ -name "access.Log.backup.*" 2>/dev/null | wc -l)
        if [ "$BACKUP_COUNT" -gt 0 ]; then
            find /etc/XrayR/ -name "access.Log.backup.*" -delete 2>/dev/null
            print_message "已删除 $BACKUP_COUNT 个备份文件"
        else
            print_message "未找到备份文件"
        fi
    else
        print_message "保留备份文件"
    fi
    
    print_message "卸载完成！"
    echo ""
    echo -e "${GREEN}已删除的内容:${NC}"
    echo "• 定时任务 (crontab)"
    echo "• 脚本目录: $SCRIPT_DIR"
    if [[ $delete_log =~ ^[Yy]$ ]]; then
        echo "• 日志文件: /var/log/xrayr_cleanup.log"
    fi
    if [[ $delete_backup =~ ^[Yy]$ ]]; then
        echo "• XrayR日志备份文件"
    fi
    
    echo ""
    print_message "感谢使用XrayR日志监控脚本！"
}

# 主函数
main() {
    print_header
    check_permissions
    uninstall_monitor
}

# 运行主函数
main "$@"
