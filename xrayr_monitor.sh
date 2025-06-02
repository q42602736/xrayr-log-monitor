#!/bin/bash

# XrayR日志监控一体化脚本
# GitHub: https://github.com/q42602736/xrayr-log-monitor
# 使用方法: wget https://raw.githubusercontent.com/q42602736/xrayr-log-monitor/main/xrayr_monitor.sh && chmod +x xrayr_monitor.sh && sudo ./xrayr_monitor.sh

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

print_success() {
    echo -e "${CYAN}[SUCCESS]${NC} $1"
}

print_header() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║        XrayR日志监控管理脚本           ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
}

# 显示主菜单
show_main_menu() {
    print_header
    echo -e "${CYAN}请选择操作:${NC}"
    echo "1) 安装XrayR日志监控"
    echo "2) 卸载XrayR日志监控"
    echo "3) 查看监控状态"
    echo "4) 手动执行清理"
    echo "5) 查看清理日志"
    echo "0) 退出"
    echo ""
    echo -n "请输入选择 (0-5): "
}

# 检查系统要求
check_requirements() {
    print_message "检查系统要求..."
    
    # 检查是否为root用户
    if [ "$EUID" -ne 0 ]; then
        print_error "请以root用户身份运行此脚本"
        echo "使用方法: sudo ./xrayr_monitor.sh"
        exit 1
    fi
    
    # 检查系统类型
    if [ ! -f /etc/debian_version ]; then
        print_warning "此脚本主要为Debian/Ubuntu系统设计，其他系统可能需要调整"
    fi
    
    print_message "系统检查完成"
}

# 创建主监控脚本
create_monitor_script() {
    local max_size_mb=$1
    local max_size_bytes=$((max_size_mb * 1024 * 1024))
    
    print_message "创建日志监控脚本..."
    
    SCRIPT_DIR="/root/xrayr_monitor"
    mkdir -p "$SCRIPT_DIR"
    
    # 创建主监控脚本
    cat > "$SCRIPT_DIR/xrayr_log_cleanup.sh" << EOF
#!/bin/bash

# XrayR日志清理脚本
# 检查/etc/XrayR/access.Log和error.log文件大小，超过${max_size_mb}MB时清理并重启XrayR

ACCESS_LOG_FILE="/etc/XrayR/access.Log"
ERROR_LOG_FILE="/etc/XrayR/error.log"
MAX_SIZE=${max_size_bytes}  # ${max_size_mb}MB in bytes
SCRIPT_LOG="/var/log/xrayr_cleanup.log"

# 记录日志函数
log_message() {
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - \$1" >> "\$SCRIPT_LOG"
}

# 清理单个日志文件的函数
cleanup_log_file() {
    local log_file=\$1
    local log_type=\$2

    # 检查日志文件是否存在
    if [ ! -f "\$log_file" ]; then
        log_message "警告: XrayR \$log_type 日志文件 \$log_file 不存在"
        return 1
    fi

    # 获取文件大小
    local file_size=\$(stat -c%s "\$log_file" 2>/dev/null)

    if [ \$? -ne 0 ]; then
        log_message "错误: 无法获取文件 \$log_file 的大小"
        return 1
    fi

    log_message "检查 \$log_type 日志文件大小: \$file_size bytes (\$((\$file_size/1024/1024))MB)"

    # 检查文件大小是否超过设定值
    if [ "\$file_size" -gt "\$MAX_SIZE" ]; then
        log_message "\$log_type 日志文件超过${max_size_mb}MB，开始清理..."

        # 备份当前日志
        local backup_file="/etc/XrayR/\${log_type}.log.backup.\$(date +%Y%m%d_%H%M%S)"
        cp "\$log_file" "\$backup_file"
        log_message "已备份 \$log_type 日志文件到: \$backup_file"

        # 清空日志文件
        > "\$log_file"
        log_message "已清空 \$log_type 日志文件: \$log_file"

        return 0
    else
        log_message "\$log_type 日志文件大小正常，无需清理"
        return 1
    fi
}

# 检查并清理access.log
cleanup_log_file "\$ACCESS_LOG_FILE" "access"
ACCESS_CLEANED=\$?

# 检查并清理error.log
cleanup_log_file "\$ERROR_LOG_FILE" "error"
ERROR_CLEANED=\$?

# 如果任一日志文件被清理，则重启XrayR服务
if [ \$ACCESS_CLEANED -eq 0 ] || [ \$ERROR_CLEANED -eq 0 ]; then
    
    # 重启XrayR服务
    log_message "开始重启XrayR服务..."

    # 使用systemctl重启
    if systemctl is-active --quiet XrayR; then
        systemctl restart XrayR
        if [ \$? -eq 0 ]; then
            log_message "XrayR服务重启成功"
        else
            log_message "错误: XrayR服务重启失败"
        fi
    else
        log_message "警告: XrayR服务未运行，尝试启动..."
        systemctl start XrayR
        if [ \$? -eq 0 ]; then
            log_message "XrayR服务启动成功"
        else
            log_message "错误: XrayR服务启动失败"
        fi
    fi
else
    log_message "所有日志文件大小正常，无需清理"
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

# 安装监控
install_monitor() {
    print_header
    print_message "开始安装XrayR日志监控..."

    check_requirements

    # 检查XrayR日志文件
    ACCESS_LOG_EXISTS=false
    ERROR_LOG_EXISTS=false

    if [ -f "/etc/XrayR/access.Log" ]; then
        ACCESS_LOG_EXISTS=true
    fi

    if [ -f "/etc/XrayR/error.log" ]; then
        ERROR_LOG_EXISTS=true
    fi

    if [ "$ACCESS_LOG_EXISTS" = false ] && [ "$ERROR_LOG_EXISTS" = false ]; then
        print_warning "XrayR日志文件不存在:"
        echo "  - /etc/XrayR/access.Log: ❌"
        echo "  - /etc/XrayR/error.log: ❌"
        echo "脚本仍会继续安装，但请确保XrayR已正确安装"
        echo ""
        echo -n "是否继续安装? (y/N): "
        read continue_install
        if [[ ! $continue_install =~ ^[Yy]$ ]]; then
            print_message "安装已取消"
            return
        fi
    else
        print_message "XrayR日志文件检查:"
        if [ "$ACCESS_LOG_EXISTS" = true ]; then
            echo "  - /etc/XrayR/access.Log: ✅"
        else
            echo "  - /etc/XrayR/access.Log: ❌"
        fi
        if [ "$ERROR_LOG_EXISTS" = true ]; then
            echo "  - /etc/XrayR/error.log: ✅"
        else
            echo "  - /etc/XrayR/error.log: ❌"
        fi
    fi

    # 设置文件大小限制
    echo ""
    echo "请设置日志文件大小限制:"
    echo "1) 50MB"
    echo "2) 100MB (推荐)"
    echo "3) 200MB"
    echo "4) 500MB"
    echo "5) 自定义"
    echo -n "请输入选择 (1-5，默认为2): "
    read size_choice

    size_choice=${size_choice:-2}

    case $size_choice in
        1)
            MAX_SIZE_MB=50
            ;;
        2)
            MAX_SIZE_MB=100
            ;;
        3)
            MAX_SIZE_MB=200
            ;;
        4)
            MAX_SIZE_MB=500
            ;;
        5)
            echo -n "请输入自定义大小(MB，范围1-1000): "
            read custom_size

            if [[ "$custom_size" =~ ^[1-9][0-9]*$ ]] && [ "$custom_size" -le 1000 ]; then
                MAX_SIZE_MB=$custom_size
            else
                print_warning "输入无效，使用默认设置: 100MB"
                MAX_SIZE_MB=100
            fi
            ;;
        *)
            MAX_SIZE_MB=100
            print_warning "使用默认设置: 100MB"
            ;;
    esac

    print_message "设置文件大小限制为: ${MAX_SIZE_MB}MB"

    # 创建监控脚本
    create_monitor_script $MAX_SIZE_MB

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
    echo "4) 自定义间隔"
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

    # 显示安装结果
    echo ""
    print_success "安装完成！"
    echo ""
    echo -e "${GREEN}安装信息:${NC}"
    echo "• 脚本位置: $SCRIPT_DIR/xrayr_log_cleanup.sh"
    echo "• 日志文件: /var/log/xrayr_cleanup.log"
    echo "• 监控文件: "
    echo "  - /etc/XrayR/access.Log"
    echo "  - /etc/XrayR/error.log"
    echo "• 大小限制: ${MAX_SIZE_MB}MB"
    echo "• 检查频率: $FREQ_DESC"
    echo ""

    # 测试运行
    print_message "执行测试运行..."
    "$SCRIPT_DIR/xrayr_log_cleanup.sh"

    echo ""
    print_success "XrayR日志监控安装成功！"
    echo ""
    echo -n "按回车键返回主菜单..."
    read
}

# 卸载监控
uninstall_monitor() {
    print_header
    print_message "开始卸载XrayR日志监控..."

    check_requirements

    # 检查是否已安装
    SCRIPT_DIR="/root/xrayr_monitor"
    if [ ! -d "$SCRIPT_DIR" ]; then
        print_warning "未找到XrayR日志监控安装"
        echo ""
        echo -n "按回车键返回主菜单..."
        read
        return
    fi

    # 确认卸载
    echo ""
    echo -e "${YELLOW}警告: 此操作将完全删除XrayR日志监控系统${NC}"
    echo -n "确定要卸载吗? (y/N): "
    read confirm_uninstall

    if [[ ! $confirm_uninstall =~ ^[Yy]$ ]]; then
        print_message "卸载已取消"
        echo ""
        echo -n "按回车键返回主菜单..."
        read
        return
    fi

    # 删除crontab任务
    print_message "删除定时任务..."
    crontab -l 2>/dev/null | grep -v "xrayr_log_cleanup" | crontab - 2>/dev/null || true

    # 删除脚本目录
    if [ -d "$SCRIPT_DIR" ]; then
        print_message "删除脚本目录: $SCRIPT_DIR"
        rm -rf "$SCRIPT_DIR"
    fi

    # 询问是否删除日志文件
    echo ""
    echo -n "是否删除日志文件 /var/log/xrayr_cleanup.log? (y/N): "
    read delete_log
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
    echo -n "是否删除XrayR日志备份文件? (y/N): "
    read delete_backup
    if [[ $delete_backup =~ ^[Yy]$ ]]; then
        ACCESS_BACKUP_COUNT=$(find /etc/XrayR/ -name "access.log.backup.*" 2>/dev/null | wc -l)
        ERROR_BACKUP_COUNT=$(find /etc/XrayR/ -name "error.log.backup.*" 2>/dev/null | wc -l)
        TOTAL_BACKUP_COUNT=$((ACCESS_BACKUP_COUNT + ERROR_BACKUP_COUNT))

        if [ "$TOTAL_BACKUP_COUNT" -gt 0 ]; then
            find /etc/XrayR/ -name "access.log.backup.*" -delete 2>/dev/null
            find /etc/XrayR/ -name "error.log.backup.*" -delete 2>/dev/null
            print_message "已删除备份文件: access.log(${ACCESS_BACKUP_COUNT}个) error.log(${ERROR_BACKUP_COUNT}个)"
        else
            print_message "未找到备份文件"
        fi
    else
        print_message "保留备份文件"
    fi

    echo ""
    print_success "卸载完成！"
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
    print_success "XrayR日志监控卸载成功！"
    echo ""
    echo -n "按回车键返回主菜单..."
    read
}

# 查看监控状态
show_monitor_status() {
    print_header
    print_message "XrayR日志监控状态"

    SCRIPT_DIR="/root/xrayr_monitor"

    # 检查是否已安装
    if [ ! -d "$SCRIPT_DIR" ]; then
        print_warning "XrayR日志监控未安装"
        echo ""
        echo -n "按回车键返回主菜单..."
        read
        return
    fi

    echo ""
    echo -e "${GREEN}安装状态:${NC} ✅ 已安装"

    # 检查脚本文件
    if [ -f "$SCRIPT_DIR/xrayr_log_cleanup.sh" ]; then
        echo -e "${GREEN}监控脚本:${NC} ✅ 存在"
    else
        echo -e "${RED}监控脚本:${NC} ❌ 缺失"
    fi

    # 检查定时任务
    CRON_STATUS=$(crontab -l 2>/dev/null | grep "xrayr_log_cleanup" || echo "")
    if [ -n "$CRON_STATUS" ]; then
        echo -e "${GREEN}定时任务:${NC} ✅ 已设置"
        echo "  └─ $CRON_STATUS"
    else
        echo -e "${RED}定时任务:${NC} ❌ 未设置"
    fi

    # 检查XrayR日志文件
    echo -e "${GREEN}XrayR日志文件:${NC}"

    # 检查access.log
    if [ -f "/etc/XrayR/access.Log" ]; then
        ACCESS_SIZE=$(stat -c%s "/etc/XrayR/access.Log" 2>/dev/null)
        ACCESS_SIZE_MB=$((ACCESS_SIZE/1024/1024))
        echo "  - access.Log: ✅ 存在 (${ACCESS_SIZE_MB}MB)"
    else
        echo "  - access.Log: ❌ 不存在"
    fi

    # 检查error.log
    if [ -f "/etc/XrayR/error.log" ]; then
        ERROR_SIZE=$(stat -c%s "/etc/XrayR/error.log" 2>/dev/null)
        ERROR_SIZE_MB=$((ERROR_SIZE/1024/1024))
        echo "  - error.log: ✅ 存在 (${ERROR_SIZE_MB}MB)"
    else
        echo "  - error.log: ❌ 不存在"
    fi

    # 检查XrayR服务状态
    if systemctl is-active --quiet XrayR; then
        echo -e "${GREEN}XrayR服务:${NC} ✅ 运行中"
    else
        echo -e "${RED}XrayR服务:${NC} ❌ 未运行"
    fi

    # 检查日志文件
    if [ -f "/var/log/xrayr_cleanup.log" ]; then
        LOG_LINES=$(wc -l < "/var/log/xrayr_cleanup.log" 2>/dev/null || echo "0")
        echo -e "${GREEN}清理日志:${NC} ✅ 存在 (${LOG_LINES}行)"

        # 显示最近的日志
        echo ""
        echo -e "${CYAN}最近的清理记录:${NC}"
        tail -5 "/var/log/xrayr_cleanup.log" 2>/dev/null | while read line; do
            echo "  $line"
        done
    else
        echo -e "${YELLOW}清理日志:${NC} ⚠️  不存在"
    fi

    # 检查备份文件
    ACCESS_BACKUP_COUNT=$(find /etc/XrayR/ -name "access.log.backup.*" 2>/dev/null | wc -l)
    ERROR_BACKUP_COUNT=$(find /etc/XrayR/ -name "error.log.backup.*" 2>/dev/null | wc -l)
    TOTAL_BACKUP_COUNT=$((ACCESS_BACKUP_COUNT + ERROR_BACKUP_COUNT))

    echo -e "${GREEN}备份文件:${NC}"
    if [ "$TOTAL_BACKUP_COUNT" -gt 0 ]; then
        echo "  - access.log备份: ${ACCESS_BACKUP_COUNT}个"
        echo "  - error.log备份: ${ERROR_BACKUP_COUNT}个"
        echo "  - 总计: ✅ ${TOTAL_BACKUP_COUNT}个"
    else
        echo "  - 总计: ⚠️  无备份文件"
    fi

    echo ""
    echo -n "按回车键返回主菜单..."
    read
}

# 手动执行清理
manual_cleanup() {
    print_header
    print_message "手动执行日志清理"

    SCRIPT_DIR="/root/xrayr_monitor"

    # 检查是否已安装
    if [ ! -f "$SCRIPT_DIR/xrayr_log_cleanup.sh" ]; then
        print_warning "XrayR日志监控未安装或脚本缺失"
        echo ""
        echo -n "按回车键返回主菜单..."
        read
        return
    fi

    echo ""
    echo -e "${YELLOW}注意: 此操作将立即执行日志清理检查${NC}"
    echo -n "确定要继续吗? (y/N): "
    read confirm_cleanup

    if [[ ! $confirm_cleanup =~ ^[Yy]$ ]]; then
        print_message "操作已取消"
        echo ""
        echo -n "按回车键返回主菜单..."
        read
        return
    fi

    echo ""
    print_message "正在执行清理脚本..."
    echo ""

    # 执行清理脚本
    "$SCRIPT_DIR/xrayr_log_cleanup.sh"

    echo ""
    print_success "清理脚本执行完成！"
    echo ""
    echo -n "按回车键返回主菜单..."
    read
}

# 查看清理日志
show_cleanup_log() {
    print_header
    print_message "XrayR清理日志"

    if [ ! -f "/var/log/xrayr_cleanup.log" ]; then
        print_warning "清理日志文件不存在"
        echo ""
        echo -n "按回车键返回主菜单..."
        read
        return
    fi

    echo ""
    echo -e "${CYAN}选择查看方式:${NC}"
    echo "1) 查看最近20行"
    echo "2) 查看全部日志"
    echo "3) 实时监控日志"
    echo "0) 返回主菜单"
    echo ""
    echo -n "请输入选择 (0-3): "
    read log_choice

    case $log_choice in
        1)
            echo ""
            echo -e "${CYAN}最近20行日志:${NC}"
            echo "----------------------------------------"
            tail -20 "/var/log/xrayr_cleanup.log"
            echo "----------------------------------------"
            ;;
        2)
            echo ""
            echo -e "${CYAN}全部日志:${NC}"
            echo "----------------------------------------"
            cat "/var/log/xrayr_cleanup.log"
            echo "----------------------------------------"
            ;;
        3)
            echo ""
            echo -e "${CYAN}实时监控日志 (按Ctrl+C退出):${NC}"
            echo "----------------------------------------"
            tail -f "/var/log/xrayr_cleanup.log"
            ;;
        0)
            return
            ;;
        *)
            print_warning "无效选择"
            ;;
    esac

    if [ "$log_choice" != "0" ] && [ "$log_choice" != "3" ]; then
        echo ""
        echo -n "按回车键返回主菜单..."
        read
    fi
}

# 主程序
main() {
    while true; do
        show_main_menu
        read choice

        case $choice in
            1)
                install_monitor
                ;;
            2)
                uninstall_monitor
                ;;
            3)
                show_monitor_status
                ;;
            4)
                manual_cleanup
                ;;
            5)
                show_cleanup_log
                ;;
            0)
                print_header
                print_success "感谢使用XrayR日志监控管理脚本！"
                echo ""
                exit 0
                ;;
            *)
                print_header
                print_error "无效选择，请重新输入"
                echo ""
                echo -n "按回车键继续..."
                read
                ;;
        esac
    done
}

# 运行主程序
main "$@"
