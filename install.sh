#!/bin/bash

# XrayR日志监控一键安装脚本 (修复版)
# GitHub: https://github.com/your-username/xrayr-log-monitor
# 使用方法: 
# wget https://raw.githubusercontent.com/your-username/xrayr-log-monitor/main/install_fixed.sh && chmod +x install_fixed.sh && sudo ./install_fixed.sh

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
    echo -e "${BLUE}  XrayR日志监控一键安装脚本${NC}"
    echo -e "${BLUE}================================${NC}"
    echo ""
}

# 检查系统要求
check_requirements() {
    print_message "检查系统要求..."
    
    # 检查是否为root用户
    if [ "$EUID" -ne 0 ]; then
        print_error "请以root用户身份运行此脚本"
        echo "使用方法: sudo ./install_fixed.sh"
        exit 1
    fi
    
    # 检查系统类型
    if [ ! -f /etc/debian_version ]; then
        print_warning "此脚本主要为Debian/Ubuntu系统设计，其他系统可能需要调整"
    fi
    
    # 检查XrayR日志文件
    if [ ! -f "/etc/XrayR/access.Log" ]; then
        print_warning "XrayR日志文件 /etc/XrayR/access.Log 不存在"
        echo "脚本仍会继续安装，但请确保XrayR已正确安装"
    fi
    
    print_message "系统检查完成"
}

# 创建主监控脚本
create_monitor_script() {
    print_message "创建日志监控脚本..."
    
    SCRIPT_DIR="/root/xrayr_monitor"
    mkdir -p "$SCRIPT_DIR"
    
    # 创建主监控脚本
    cat > "$SCRIPT_DIR/xrayr_log_cleanup.sh" << 'EOF'
#!/bin/bash

# XrayR日志清理脚本
# 检查/etc/XrayR/access.Log文件大小，超过100M时清理并重启XrayR

LOG_FILE="/etc/XrayR/access.Log"
MAX_SIZE=104857600  # 100MB in bytes
SCRIPT_LOG="/var/log/xrayr_cleanup.log"

# 记录日志函数
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$SCRIPT_LOG"
}

# 检查日志文件是否存在
if [ ! -f "$LOG_FILE" ]; then
    log_message "警告: XrayR日志文件 $LOG_FILE 不存在"
    exit 1
fi

# 获取文件大小
FILE_SIZE=$(stat -c%s "$LOG_FILE" 2>/dev/null)

if [ $? -ne 0 ]; then
    log_message "错误: 无法获取文件 $LOG_FILE 的大小"
    exit 1
fi

log_message "检查日志文件大小: $FILE_SIZE bytes ($(($FILE_SIZE/1024/1024))MB)"

# 检查文件大小是否超过100MB
if [ "$FILE_SIZE" -gt "$MAX_SIZE" ]; then
    log_message "日志文件超过100MB，开始清理..."
    
    # 备份当前日志（可选）
    BACKUP_FILE="/etc/XrayR/access.Log.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$LOG_FILE" "$BACKUP_FILE"
    log_message "已备份日志文件到: $BACKUP_FILE"
    
    # 清空日志文件
    > "$LOG_FILE"
    log_message "已清空日志文件: $LOG_FILE"
    
    # 重启XrayR服务
    log_message "开始重启XrayR服务..."
    
    # 使用systemctl重启
    if systemctl is-active --quiet XrayR; then
        systemctl restart XrayR
        if [ $? -eq 0 ]; then
            log_message "XrayR服务重启成功"
        else
            log_message "错误: XrayR服务重启失败"
        fi
    else
        log_message "警告: XrayR服务未运行，尝试启动..."
        systemctl start XrayR
        if [ $? -eq 0 ]; then
            log_message "XrayR服务启动成功"
        else
            log_message "错误: XrayR服务启动失败"
        fi
    fi
else
    log_message "日志文件大小正常，无需清理"
fi

log_message "脚本执行完成"
EOF

    chmod +x "$SCRIPT_DIR/xrayr_log_cleanup.sh"
    print_message "监控脚本创建完成: $SCRIPT_DIR/xrayr_log_cleanup.sh"
}

# 创建expect重启脚本（可选）
create_expect_script() {
    print_message "创建expect重启脚本..."
    
    SCRIPT_DIR="/root/xrayr_monitor"
    
    cat > "$SCRIPT_DIR/xrayr_restart.exp" << 'EOF'
#!/usr/bin/expect

# XrayR自动重启脚本
# 自动执行xrayr命令并选择6进行重启

set timeout 30

# 启动xrayr命令
spawn xrayr

# 等待菜单出现并选择6
expect {
    "请输入你的选择" {
        send "6\r"
        exp_continue
    }
    "重启" {
        send "\r"
        exp_continue
    }
    "restart" {
        send "\r"
        exp_continue
    }
    "成功" {
        puts "XrayR重启成功"
    }
    "失败" {
        puts "XrayR重启失败"
        exit 1
    }
    timeout {
        puts "操作超时"
        exit 1
    }
    eof {
        puts "命令执行完成"
    }
}

exit 0
EOF

    chmod +x "$SCRIPT_DIR/xrayr_restart.exp"
    print_message "expect脚本创建完成: $SCRIPT_DIR/xrayr_restart.exp"
}

# 用户配置选择
configure_settings() {
    print_message "开始配置设置..."

    # 选择重启方式
    echo ""
    echo "请选择XrayR重启方式:"
    echo "1) 使用systemctl重启 (推荐，更稳定)"
    echo "2) 使用xrayr命令重启 (需要安装expect)"
    echo -n "请输入选择 (1 或 2，默认为1): "
    read restart_method

    restart_method=${restart_method:-1}

    if [ "$restart_method" = "2" ]; then
        # 安装expect
        print_message "安装expect工具..."
        apt-get update -qq
        apt-get install -y expect

        create_expect_script

        # 修改主脚本使用expect重启
        SCRIPT_DIR="/root/xrayr_monitor"
        sed -i '/# 使用systemctl重启/,/fi$/c\
    # 使用expect脚本重启\
    if [ -f "'$SCRIPT_DIR'/xrayr_restart.exp" ]; then\
        "'$SCRIPT_DIR'/xrayr_restart.exp"\
        if [ $? -eq 0 ]; then\
            log_message "XrayR服务重启成功（通过xrayr命令）"\
        else\
            log_message "错误: XrayR服务重启失败（通过xrayr命令）"\
        fi\
    else\
        log_message "错误: expect脚本不存在"\
    fi' "$SCRIPT_DIR/xrayr_log_cleanup.sh"

        print_message "已配置使用xrayr命令重启"
    else
        print_message "已配置使用systemctl重启"
    fi

    # 选择检查频率
    echo ""
    echo "请选择检查频率:"
    echo "1) 每小时检查一次"
    echo "2) 每30分钟检查一次"
    echo "3) 每15分钟检查一次"
    echo "4) 自定义"
    echo -n "请输入选择 (1-4，默认为1): "
    read frequency

    frequency=${frequency:-1}

    case $frequency in
        1)
            CRON_TIME="0 * * * *"
            FREQ_DESC="每小时"
            ;;
        2)
            CRON_TIME="*/30 * * * *"
            FREQ_DESC="每30分钟"
            ;;
        3)
            CRON_TIME="*/15 * * * *"
            FREQ_DESC="每15分钟"
            ;;
        4)
            echo -n "请输入检查间隔分钟数 (例如: 10 表示每10分钟检查一次): "
            read custom_minutes

            # 验证输入是否为有效数字
            if [[ "$custom_minutes" =~ ^[1-9][0-9]*$ ]] && [ "$custom_minutes" -le 59 ]; then
                CRON_TIME="*/$custom_minutes * * * *"
                FREQ_DESC="每${custom_minutes}分钟"
            else
                print_warning "输入无效，使用默认设置: 每小时检查一次"
                CRON_TIME="0 * * * *"
                FREQ_DESC="每小时"
            fi
            ;;
        *)
            CRON_TIME="0 * * * *"
            FREQ_DESC="每小时"
            print_warning "使用默认设置: 每小时检查一次"
            ;;
    esac

    # 设置crontab
    print_message "设置定时任务..."
    SCRIPT_DIR="/root/xrayr_monitor"
    (crontab -l 2>/dev/null | grep -v "xrayr_log_cleanup"; echo "$CRON_TIME $SCRIPT_DIR/xrayr_log_cleanup.sh") | crontab -

    print_message "定时任务设置完成: $FREQ_DESC"
}

# 显示安装结果
show_installation_result() {
    print_header
    print_message "安装完成！"
    echo ""

    SCRIPT_DIR="/root/xrayr_monitor"

    echo -e "${GREEN}安装信息:${NC}"
    echo "• 脚本位置: $SCRIPT_DIR/xrayr_log_cleanup.sh"
    echo "• 日志文件: /var/log/xrayr_cleanup.log"
    echo "• 监控文件: /etc/XrayR/access.Log"
    echo "• 大小限制: 100MB"
    echo ""

    echo -e "${GREEN}当前定时任务:${NC}"
    crontab -l | grep xrayr_log_cleanup || echo "未找到定时任务"
    echo ""

    echo -e "${GREEN}常用命令:${NC}"
    echo "• 手动运行检查: $SCRIPT_DIR/xrayr_log_cleanup.sh"
    echo "• 查看清理日志: tail -f /var/log/xrayr_cleanup.log"
    echo "• 查看定时任务: crontab -l"
    echo "• 编辑定时任务: crontab -e"
    echo ""

    # 测试运行
    print_message "执行测试运行..."
    "$SCRIPT_DIR/xrayr_log_cleanup.sh"

    echo ""
    print_message "如果需要查看详细日志，请运行: tail -f /var/log/xrayr_cleanup.log"
    print_message "感谢使用XrayR日志监控脚本！"
}

# 主函数
main() {
    print_header

    check_requirements
    create_monitor_script
    configure_settings
    show_installation_result
}

# 运行主函数
main "$@"
