#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
#stty erase ^?

cd "$(
    cd "$(dirname "$0")" || exit
    pwd
)" || exit

idleleo=$0

#=====================================================
#	System Request: Debian 9+/Ubuntu 18.04+/Centos 7+
#	Author:	hello-yunshu
#	Dscription: Xray Onekey Management
#	Version: 2.0
#	email: admin@idleleo.com
#	Official document: hey.run
#=====================================================

#fonts color
Green="\033[32m"
Red="\033[31m"
GreenW="\033[1;32m"
RedW="\033[1;31m"
#Yellow="\033[33m"
GreenBG="\033[42;30m"
RedBG="\033[41;30m"
YellowBG="\033[43;30m"
Font="\033[0m"

#notification information
Info="${Green}[提醒]${Font}"
OK="${Green}[OK]${Font}"
Error="${RedW}[错误]${Font}"
Warning="${RedW}[警告]${Font}"

shell_version="2.2.0"
shell_mode="未安装"
tls_mode="None"
ws_grpc_mode="None"
local_bin="/usr/local"
idleleo_dir="/etc/idleleo"
idleleo_conf_dir="${idleleo_dir}/conf"
log_dir="${idleleo_dir}/logs"
xray_bin_dir="${local_bin}/bin"
xray_conf_dir="${idleleo_conf_dir}/xray"
nginx_conf_dir="${idleleo_conf_dir}/nginx"
xray_conf="${xray_conf_dir}/config.json"
xray_status_conf="${xray_conf_dir}/status_config.json"
xray_default_conf="${local_bin}/etc/xray/config.json"
nginx_conf="${nginx_conf_dir}/00-xray.conf"
nginx_ssl_conf="${nginx_conf_dir}/01-xray-80.conf"
nginx_upstream_conf="${nginx_conf_dir}/02-xray-server.conf"
idleleo_commend_file="/usr/bin/idleleo"
ssl_chainpath="${idleleo_dir}/cert"
nginx_dir="${local_bin}/nginx"
xray_info_file="${idleleo_dir}/info/xray_info.inf"
xray_qr_config_file="${idleleo_dir}/info/vless_qr.json"
nginx_systemd_file="/etc/systemd/system/nginx.service"
xray_systemd_file="/etc/systemd/system/xray.service"
xray_access_log="/var/log/xray/access.log"
xray_error_log="/var/log/xray/error.log"
amce_sh_file="/root/.acme.sh/acme.sh"
auto_update_file="${idleleo_dir}/auto_update.sh"
ssl_update_file="${idleleo_dir}/ssl_update.sh"
cert_group="nobody"
myemali="my@example.com"
shell_version_tmp="${idleleo_dir}/tmp/shell_version.tmp"
get_versions_all=$(curl -s https://www.idleleo.com/api/xray_shell_versions)
read_config_status=1
reality_add_more="off"
reality_add_nginx="off"
old_config_status="off"
old_tls_mode="NULL"
random_num=$((RANDOM % 12 + 4))
[[ -f "${xray_qr_config_file}" ]] && info_extraction_all=$(jq -rc . ${xray_qr_config_file})

##兼容代码，未来删除
[[ ! -d "${idleleo_dir}/tmp" ]] && mkdir -p ${idleleo_dir}/tmp

source '/etc/os-release'

VERSION=$(echo "${VERSION}" | awk -F "[()]" '{print $2}')

check_system() {
    if [[ "${ID}" == "centos" && ${VERSION_ID} -ge 7 ]]; then
        echo -e "${OK} ${GreenBG} 当前系统为 Centos ${VERSION_ID} ${VERSION} ${Font}"
        INS="yum"
        [[ ! -f "${xray_qr_config_file}" ]] && $INS update
    elif [[ "${ID}" == "debian" && ${VERSION_ID} -ge 8 ]]; then
        echo -e "${OK} ${GreenBG} 当前系统为 Debian ${VERSION_ID} ${VERSION} ${Font}"
        INS="apt"
        [[ ! -f "${xray_qr_config_file}" ]] && $INS update
    elif [[ "${ID}" == "ubuntu" && $(echo "${VERSION_ID}" | cut -d '.' -f1) -ge 16 ]]; then
        echo -e "${OK} ${GreenBG} 当前系统为 Ubuntu ${VERSION_ID} ${UBUNTU_CODENAME} ${Font}"
        INS="apt"
        if [[ ! -f "${xray_qr_config_file}" ]]; then
            rm /var/lib/dpkg/lock
            dpkg --configure -a
            rm /var/lib/apt/lists/lock
            rm /var/cache/apt/archives/lock
            $INS update
        fi
    else
        echo -e "${Error} ${RedBG} 当前系统为 ${ID} ${VERSION_ID} 不在支持的系统列表内, 安装中断! ${Font}"
        exit 1
    fi

    #systemctl stop firewalld
    #systemctl disable firewalld
    #echo -e "${OK} ${GreenBG} firewalld 已关闭 ${Font}"

    #systemctl stop ufw
    #systemctl disable ufw
    #echo -e "${OK} ${GreenBG} ufw 已关闭 ${Font}"
}

is_root() {
    if [[ 0 == $UID ]]; then
        echo -e "${OK} ${GreenBG} 当前用户是 root用户, 进入安装流程 ${Font}"
    else
        echo -e "${Error} ${RedBG} 当前用户不是 root用户, 请切换到 root用户 后重新执行脚本! ${Font}"
        exit 1
    fi
}

judge() {
    if [[ 0 -eq $? ]]; then
        echo -e "${OK} ${GreenBG} $1 完成 ${Font}"
        sleep 0.5
    else
        echo -e "${Error} ${RedBG} $1 失败 ${Font}"
        exit 1
    fi
}

check_version() {
    echo ${get_versions_all} | jq -rc ".$1"
    [[ 0 -ne $? ]] && echo -e "${Error} ${RedBG} 在线版本检测失败, 请稍后再试! ${Font}" && exit 1
}

pkg_install_judge() {
    if [[ "${ID}" == "centos" ]]; then
        yum list installed | grep -iw "^$1"
    else
        dpkg --get-selections | grep -iw "^$1" | grep -ivw "deinstall"
    fi
}

pkg_install() {
    install_array=(${1//,/ })
    install_status=1
    if [[ ${#install_array[@]} -gt 1 ]]; then
        for install_var in ${install_array[@]}; do
            if [[ -z $(pkg_install_judge "${install_var}") ]]; then
                ${INS} -y install ${install_var}
                install_status=0
            fi
        done
        if [[ ${install_status} == 0 ]]; then
            judge "安装 ${1//,/ }"
        else
            echo -e "${OK} ${GreenBG} 已安装 ${1//,/ } ${Font}"
            sleep 0.5
        fi
    else
        if [[ -z $(pkg_install_judge "$1") ]]; then
            ${INS} -y install $1
            judge "安装 $1"
        else
            echo -e "${OK} ${GreenBG} 已安装 $1 ${Font}"
            sleep 0.5
        fi
    fi
}

dependency_install() {
    pkg_install "bc,curl,dbus,git,jq,lsof,python3,qrencode,wget"
    if [[ "${ID}" == "centos" ]]; then
        pkg_install "crontabs"
    else
        pkg_install "cron"
    fi
    if [[ ! -f "/var/spool/cron/root" ]] && [[ ! -f "/var/spool/cron/crontabs/root" ]]; then
        if [[ "${ID}" == "centos" ]]; then
            touch /var/spool/cron/root && chmod 600 /var/spool/cron/root
            systemctl start crond && systemctl enable crond >/dev/null 2>&1
            judge "crontab 自启动配置"
        else
            touch /var/spool/cron/crontabs/root && chmod 600 /var/spool/cron/crontabs/root
            systemctl start cron && systemctl enable cron >/dev/null 2>&1
            judge "crontab 自启动配置"
        fi
    fi
    if [[ ${tls_mode} != "None" ]]; then
        if [[ "${ID}" == "centos" ]]; then
            pkg_install "epel-release,iputils,pcre,pcre-devel,zlib-devel,perl-IPC-Cmd"
        else
            pkg_install "iputils-ping,libpcre3,libpcre3-dev,zlib1g-dev"
        fi
        judge "Nginx 链接库安装"
    fi
}

read_optimize() {
    read -rp "$1" $2
    if [[ -z $(eval echo \$$2) ]]; then
        if [[ $3 != "NULL" ]]; then
            eval $(echo "$2")="$3"
        else
            echo -e "${Error} ${RedBG} 请输入正确的值! ${Font}"
            read_optimize "$1" "$2" $3 $4 $5 "$6"
        fi
    elif [[ ! -z $4 ]] && [[ ! -z $5 ]]; then
        if [[ $(eval echo \$$2) -le $4 ]] || [[ $(eval echo \$$2) -gt $5 ]]; then
            echo -e "${Error} ${RedBG} $6 ${Font}"
            read_optimize "$1" "$2" $3 $4 $5 "$6"
        fi
    fi
}

basic_optimization() {
    # 最大文件打开数
    sed -i '/^\*\ *soft\ *nofile\ *[[:digit:]]*/d' /etc/security/limits.conf
    sed -i '/^\*\ *hard\ *nofile\ *[[:digit:]]*/d' /etc/security/limits.conf
    echo '* soft nofile 65536' >>/etc/security/limits.conf
    echo '* hard nofile 65536' >>/etc/security/limits.conf

    # 关闭 Selinux
    if [[ "${ID}" == "centos" ]]; then
        sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
        setenforce 0
    fi

}

create_directory() {
    if [[ ${tls_mode} != "None" ]]; then
        [[ ! -d "${nginx_conf_dir}" ]] && mkdir -p ${nginx_conf_dir}
    fi
    [[ ! -d "${ssl_chainpath}" ]] && mkdir -p ${ssl_chainpath}
    [[ ! -d "${xray_conf_dir}" ]] && mkdir -p ${xray_conf_dir}
    [[ ! -d "${idleleo_dir}/info" ]] && mkdir -p ${idleleo_dir}/info
}

port_set() {
    if [[ "on" != ${old_config_status} ]]; then
        echo -e "\n${GreenBG} 确定 连接端口 ${Font}"
        read_optimize "请输入连接端口 (默认值:443):" "port" 443 0 65535 "请输入 0-65535 之间的值!"
    fi
}

ws_grpc_choose() {
    if [[ "on" != ${old_config_status} ]]; then
        echo -e "\n${GreenBG} 请选择 安装协议 ws/gRPC ${Font}"
        echo -e "${Red}1${Font}: ws (默认)"
        echo "2: gRPC"
        echo "3: ws+gRPC"
        read -rp "请输入: " choose_network
        if [[ $choose_network == 2 ]]; then
            [[ ${shell_mode} == "Nginx+ws+TLS" ]] && shell_mode="Nginx+gRPC+TLS"
            [[ ${shell_mode} == "Reality" ]] && shell_mode="Reality+gRPC"
            [[ ${shell_mode} == "ws ONLY" ]] && shell_mode="gRPC ONLY"
            ws_grpc_mode="onlygRPC"
        elif [[ $choose_network == 3 ]]; then
            [[ ${shell_mode} == "Nginx+ws+TLS" ]] && shell_mode="Nginx+ws+gRPC+TLS"
            [[ ${shell_mode} == "Reality" ]] && shell_mode="Reality+ws+gRPC"
            [[ ${shell_mode} == "ws ONLY" ]] && shell_mode="ws+gRPC ONLY"
            ws_grpc_mode="all"
        else
            [[ ${shell_mode} == "Reality" ]] && shell_mode="Reality+ws"
            ws_grpc_mode="onlyws"
        fi
    fi
}

xray_reality_add_more_choose() {
    if [[ "on" != ${old_config_status} ]]; then
        echo -e "\n${GreenBG} 是否添加简单 ws/gRPC 协议 用于负载均衡 [Y/${Red}N${Font}${GreenBG}]? ${Font}"
        echo -e "${Warning} ${YellowBG} 如不清楚具体用途, 请勿选择! ${Font}"
        read -r reality_add_more_fq
        case $reality_add_more_fq in
        [yY][eE][sS] | [yY])
            reality_add_more="on"
            ws_grpc_choose
            ws_inbound_port_set
            grpc_inbound_port_set
            ws_path_set
            grpc_path_set
            port_exist_check "${xport}"
            port_exist_check "${gport}"
            ;;
        *)
            reality_add_more="off"
            ws_inbound_port_set
            grpc_inbound_port_set
            ws_path_set
            grpc_path_set
            echo -e "${OK} ${GreenBG} 已跳过添加简单 ws/gRPC 协议 ${Font}"
            ;;
        esac
    fi
}

ws_grpc_qr() {
    artpath="None"
    artxport="None"
    artserviceName="None"
    artgport="None"
    if [[ ${ws_grpc_mode} == "onlyws" ]]; then
        artxport=${xport}
        artpath=${path}
    elif [[ ${ws_grpc_mode} == "onlygRPC" ]]; then
        artgport=${gport}
        artserviceName=${serviceName}
    elif [[ ${ws_grpc_mode} == "all" ]]; then
        artxport=${xport}
        artpath=${path}
        artgport=${gport}
        artserviceName=${serviceName}
    fi
}

ws_inbound_port_set() {
    if [[ "on" != ${old_config_status} ]]; then
        if [[ ${ws_grpc_mode} == "onlyws" ]] || [[ ${ws_grpc_mode} == "all" ]]; then
            echo -e "\n${GreenBG} 是否需要自定义 ws inbound_port [Y/${Red}N${Font}${GreenBG}]? ${Font}"
            read -r inbound_port_modify_fq
            case $inbound_port_modify_fq in
            [yY][eE][sS] | [yY])
                read_optimize "请输入自定义 ws inbound_port (请勿与其他端口相同! ):" "xport" "NULL" 0 65535 "请输入 0-65535 之间的值!"
                echo -e "${Green} ws inbound_port: ${xport} ${Font}"
                ;;
            *)
                xport=$((RANDOM % 1000 + 10000))
                echo -e "${Green} ws inbound_port: ${xport} ${Font}"
                ;;
            esac
        else
            xport=$((RANDOM % 1000 + 20000))
        fi
    fi
}

grpc_inbound_port_set() {
    if [[ "on" != ${old_config_status} ]]; then
        if [[ ${ws_grpc_mode} == "onlygRPC" ]] || [[ ${ws_grpc_mode} == "all" ]]; then
            echo -e "\n${GreenBG} 是否需要自定义 gRPC inbound_port [Y/${Red}N${Font}${GreenBG}]? ${Font}"
            read -r inbound_port_modify_fq
            case $inbound_port_modify_fq in
            [yY][eE][sS] | [yY])
                read_optimize "请输入自定义 gRPC inbound_port (请勿与其他端口相同! ):" "gport" "NULL" 0 65535 "请输入 0-65535 之间的值!"
                echo -e "${Green} gRPC inbound_port: ${gport} ${Font}"
                ;;
            *)
                gport=$((RANDOM % 1000 + 10000))
                [[ ${gport} == ${xport} ]] && gport=$((RANDOM % 1000 + 10000))
                echo -e "${Green} gRPC inbound_port: ${gport} ${Font}"
                ;;
            esac
        else
            gport=$((RANDOM % 1000 + 30000))
        fi
    fi
}

firewall_set() {
    echo -e "\n${GreenBG} 是否需要设置防火墙 [Y/${Red}N${Font}${GreenBG}]? ${Font}"
    read -r firewall_set_fq
    case $firewall_set_fq in
    [yY][eE][sS] | [yY])
        if [[ "${ID}" == "centos" ]]; then
            pkg_install "iptables-services"
        else
            pkg_install "iptables-persistent"
        fi
        iptables -A INPUT -i lo -j ACCEPT
        iptables -A OUTPUT -o lo -j ACCEPT
        if [[ ${tls_mode} == "TLS" ]]; then
            iptables -I INPUT -p tcp -m multiport --dport 53,80,${port} -j ACCEPT
            iptables -I INPUT -p udp -m multiport --dport 53,80,${port} -j ACCEPT
            iptables -I OUTPUT -p tcp -m multiport --sport 53,80,${port} -j ACCEPT
            iptables -I OUTPUT -p udp -m multiport --sport 53,80,${port} -j ACCEPT
            iptables -I INPUT -p udp --dport 1024:65535 -j ACCEPT
        fi
        if [[ ${ws_grpc_mode} == "onlyws" ]]; then
            iptables -I INPUT -p tcp -m multiport --dport 53,${xport} -j ACCEPT
            iptables -I INPUT -p udp -m multiport --dport 53,${xport} -j ACCEPT
            iptables -I OUTPUT -p tcp -m multiport --sport 53,${xport} -j ACCEPT
            iptables -I OUTPUT -p udp -m multiport --sport 53,${xport} -j ACCEPT
            iptables -I INPUT -p udp --dport 1024:65535 -j ACCEPT
        elif [[ ${ws_grpc_mode} == "onlygRPC" ]]; then
            iptables -I INPUT -p tcp -m multiport --dport 53,${gport} -j ACCEPT
            iptables -I INPUT -p udp -m multiport --dport 53,${gport} -j ACCEPT
            iptables -I OUTPUT -p tcp -m multiport --sport 53,${gport} -j ACCEPT
            iptables -I OUTPUT -p udp -m multiport --sport 53,${gport} -j ACCEPT
            iptables -I INPUT -p udp --dport 1024:65535 -j ACCEPT
        elif [[ ${ws_grpc_mode} == "all" ]]; then
            iptables -I INPUT -p tcp -m multiport --dport 53,${xport},${gport} -j ACCEPT
            iptables -I INPUT -p udp -m multiport --dport 53,${xport},${gport} -j ACCEPT
            iptables -I OUTPUT -p tcp -m multiport --sport 53,${xport},${gport} -j ACCEPT
            iptables -I OUTPUT -p udp -m multiport --sport 53,${xport},${gport} -j ACCEPT
            iptables -I INPUT -p udp --dport 1024:65535 -j ACCEPT
        fi
        if [[ "${ID}" == "centos" && ${VERSION_ID} -ge 7 ]]; then
            service iptables save
            service iptables restart
            echo -e "${OK} ${GreenBG} 防火墙 重启 完成 ${Font}"
        else
            netfilter-persistent save
            systemctl restart iptables
            echo -e "${OK} ${GreenBG} 防火墙 重启 完成 ${Font}"
        fi
        echo -e "${OK} ${GreenBG} 开放防火墙相关端口 ${Font}"
        echo -e "${GreenBG} 若修改配置, 请注意关闭防火墙相关端口 ${Font}"
        echo -e "${OK} ${GreenBG} 配置 Xray FullCone ${Font}"
        ;;
    *)
        echo -e "${OK} ${GreenBG} 跳过防火墙设置 ${Font}"
        ;;
    esac
}

ws_path_set() {
    if [[ "on" != ${old_config_status} ]] || [[ ${change_ws_path} == "yes" ]]; then
        if [[ ${ws_grpc_mode} == "onlyws" ]] || [[ ${ws_grpc_mode} == "all" ]]; then
            echo -e "\n${GreenBG} 是否需要自定义 ws 伪装路径 [Y/${Red}N${Font}${GreenBG}]? ${Font}"
            read -r path_modify_fq
            case $path_modify_fq in
            [yY][eE][sS] | [yY])
                read_optimize "请输入自定义 ws 伪装路径 (不需要“/”):" "path" "NULL"
                echo -e "${Green} ws 伪装路径: ${path} ${Font}"
                ;;
            *)
                path="$(head -n 10 /dev/urandom | md5sum | head -c ${random_num})"
                echo -e "${Green} ws 伪装路径: ${path} ${Font}"
                ;;
            esac
        else
            path="$(head -n 10 /dev/urandom | md5sum | head -c ${random_num})"
        fi
    elif [[ ${ws_grpc_mode} == "onlyws" ]] || [[ ${ws_grpc_mode} == "all" ]]; then
        echo -e "\n${GreenBG} 是否需要修改 ws 伪装路径 [Y/${Red}N${Font}${GreenBG}]? ${Font}"
        read -r change_ws_path_fq
        case $change_ws_path_fq in
        [yY][eE][sS] | [yY])
            change_ws_path="yes"
            ws_path_set
            ;;
        *) ;;
        esac
    fi
}

grpc_path_set() {
    if [[ "on" != ${old_config_status} ]] || [[ ${change_grpc_path} == "yes" ]]; then
        if [[ ${ws_grpc_mode} == "onlygRPC" ]] || [[ ${ws_grpc_mode} == "all" ]]; then
            echo -e "\n${GreenBG} 是否需要自定义 gRPC 伪装路径 [Y/${Red}N${Font}${GreenBG}]? ${Font}"
            read -r path_modify_fq
            case $path_modify_fq in
            [yY][eE][sS] | [yY])
                read_optimize "请输入自定义 gRPC 伪装路径 (不需要“/”):" "serviceName" "NULL"
                echo -e "${Green} gRPC 伪装路径: ${serviceName} ${Font}"
                ;;
            *)
                serviceName="$(head -n 10 /dev/urandom | md5sum | head -c ${random_num})"
                echo -e "${Green} gRPC 伪装路径: ${serviceName} ${Font}"
                ;;
            esac
        else
            serviceName="$(head -n 10 /dev/urandom | md5sum | head -c ${random_num})"
        fi
    elif [[ ${ws_grpc_mode} == "onlygRPC" ]] || [[ ${ws_grpc_mode} == "all" ]]; then
        echo -e "\n${GreenBG} 是否需要修改 gRPC 伪装路径 [Y/${Red}N${Font}${GreenBG}]? ${Font}"
        read -r change_grpc_path_fq
        case $change_grpc_path_fq in
        [yY][eE][sS] | [yY])
            change_grpc_path="yes"
            grpc_path_set
            ;;
        *) ;;
        esac
    fi
}

email_set() {
    if [[ "on" != ${old_config_status} ]]; then
        echo -e "\n${GreenBG} 是否需要自定义 Xray 用户名 [Y/${Red}N${Font}${GreenBG}]? ${Font}"
        read -r custom_email_fq
        case $custom_email_fq in
        [yY][eE][sS] | [yY])
            read -r -p "请输入合法的email (e.g. me@idleleo.com):" custom_email
            if [[ -z "${custom_email}" ]]; then
                echo -e "${Error} ${RedBG} 用户名不可为空! ${Font}"
                email_set
            fi
            ;;
        *)
            custom_email="$(head -n 10 /dev/urandom | md5sum | head -c ${random_num})@idleleo.com"
            ;;
        esac
        echo -e "${Green} Xray 用户名 (email): ${custom_email} ${Font}"
    fi
}

UUID_set() {
    if [[ "on" != ${old_config_status} ]]; then
        echo -e "\n${GreenBG} 是否需要自定义字符串映射为 UUIDv5 [Y/${Red}N${Font}${GreenBG}]? ${Font}"
        read -r need_UUID5
        case $need_UUID5 in
        [yY][eE][sS] | [yY])
            read_optimize "请输入自定义字符串 (最多30字符):" "UUID5_char" "NULL"
            UUID="$(UUIDv5_tranc ${UUID5_char})"
            echo -e "${Green} 自定义字符串: ${UUID5_char} ${Font}"
            echo -e "${Green} UUIDv5: ${UUID} ${Font}\n"
            ;;
        *)
            UUID5_char="$(head -n 10 /dev/urandom | md5sum | head -c ${random_num})"
            UUID="$(UUIDv5_tranc ${UUID5_char})"
            echo -e "${Green} UUID 映射字符串: ${UUID5_char} ${Font}"
            echo -e "${Green} UUID: ${UUID} ${Font}\n"
            #[ -z "$UUID" ] && UUID=$(cat /proc/sys/kernel/random/uuid)
            ;;
        esac
    fi
}

target_set() {
    if [[ "on" == ${old_config_status} ]] && [[ $(info_extraction target) != null ]]; then
        echo -e "\n${GreenBG} 检测到 target 域名已配置, 是否保留 [${Red}Y${Font}${GreenBG}/N]? ${Font}"
            read -r old_host_fq
            case $old_host_fq in
            [nN][oO] | [nN])
                target_reset=0
                ;;
            *)
                target_reset=1
                ;;
            esac
    fi
    if [[ ${target_reset} == 0 ]] || [[ "on" != ${old_config_status} ]]; then
        local domain
        local output
        local curl_output
        pkg_install "nmap"

        while true; do
            echo -e "\n${GreenBG} 请输入一个域名 (e.g. bing.com)${Font}"
            echo -e "${Green}域名要求支持 TLSv1.3、X25519 与 H2 以及域名非跳转用${Font}"
            read -p "确认域名符合要求后请输入: " domain
            if [ -z "$domain" ]; then
                echo -e "${Warning} ${YellowBG} 没有输入域名, 请重新输入${RedBG}${Font}"
                continue
            fi
            echo -e "${Green}正在检测域名请等待…${Font}"

            output=$(nmap --script ssl-enum-ciphers -p 443 "${domain}")
            curl_output=$(curl -I -k -m 5 "https://${domain}" 2>&1)
        
            # 检测TLSv1.3支持
            if ! echo "$output" | grep -q "TLSv1.3"; then
                echo -e "${Warning} ${YellowBG} 该域名不支持 TLSv1.3, 请重新输入${YellowBG}${Font}"
                continue
            fi

            # 检测X25519支持
            if ! echo "$output" | grep -q "x25519"; then
                echo -e "${Warning} ${YellowBG} 该域名不支持 X25519, 请重新输入${YellowBG}${Font}"
                continue
            fi

            # 检测HTTP/2支持
            if ! echo "$curl_output" | grep -q "HTTP/2"; then
                echo -e "${Warning} ${YellowBG} 该域名不支持 HTTP/2, 请重新输入${YellowBG}${Font}"
                continue
            fi
        
            # 检测是否跳转
            if echo "$curl_output" | grep -i -q 'location:'; then
                echo -e "${Warning} ${YellowBG} 该域名发生了跳转, 请重新输入${YellowBG}${Font}"
                continue
            fi

            echo -e "${OK} ${GreenBG} 域名 ${domain} 满足所有要求${Font}"
            target=$domain
            break
        done
        echo -e "${Green} target 域名: ${target} ${Font}"
    fi
}

serverNames_set() {
    if [[ ${target_reset} == 0 ]] || [[ "on" != ${old_config_status} ]]; then
        local custom_serverNames_fq
        echo -e "\n${GreenBG} 是否需要修改 ${target} 域名的 serverNames 用户名 [Y/${Red}N${Font}${GreenBG}]? ${Font}"
        echo -e "${Green} 默认为 ${target} 域名的本身${Font}"
        echo -e "${Warning} ${YellowBG} 如不清楚具体用途, 请勿继续! ${Font}"
        read -r custom_serverNames_fq
        case $custom_serverNames_fq in
        [yY][eE][sS] | [yY])
            read -p "请输入: " serverNames
            ;;
        *)
            serverNames=$target
            ;;
        esac
        echo -e "${Green} serverNames: ${serverNames} ${Font}"
    fi
}

keys_set() {
    if [[ "on" != ${old_config_status} ]]; then
        local keys
        keys=$(${xray_bin_dir}/xray x25519 | tr '\n' ' ')
        privateKey=$(echo "${keys}" | awk -F"Private key: " '{print $2}' | awk '{print $1}')
        publicKey=$(echo "${keys}" | awk -F"Public key: " '{print $2}' | awk '{print $1}')
        echo -e "${Green} privateKey: ${privateKey} ${Font}"
        echo -e "${Green} publicKey: ${publicKey} ${Font}"
    fi
}

shortIds_set() {
    if [[ "on" != ${old_config_status} ]]; then
        pkg_install "openssl"
        shortIds=$(openssl rand -hex 4)
        echo -e "${Green} shortIds: ${shortIds} ${Font}"
    fi
}

nginx_upstream_server_set() {
    if [[ ${tls_mode} == "TLS" ]]; then
        echo -e "\n${GreenBG} 是否变更 Nginx 负载均衡 [Y/${Red}N${Font}${GreenBG}]? ${Font}"
        echo -e "${Warning} ${YellowBG} 如不清楚具体用途, 请勿继续! ${Font}"
        read -r nginx_upstream_server_fq
        case $nginx_upstream_server_fq in
        [yY][eE][sS] | [yY])
            echo -e "\n${GreenBG} 请选择协议为 ws 或 gRPC ${Font}"
            echo "1: ws"
            echo "2: gRPC"
            echo "3: 返回"
            read -rp "请输入: " upstream_choose
            
            fm_remote_url="https://raw.githubusercontent.com/hello-yunshu/Xray_bash_onekey/main/file_manager.sh"
            fm_file_path=${nginx_conf_dir}
            if [ ! -f "${idleleo_dir}/file_manager.sh" ]; then
                echo -e "${Info} ${Green} 本地文件 file_manager.sh 不存在，正在下载... ${Font}"
                curl -sL "$fm_remote_url" -o "${idleleo_dir}/file_manager.sh"
                if [ $? -ne 0 ]; then
                    echo -e "${Error} ${RedBG} 下载失败，请手动下载并安装新版本 ${Font}"
                    return 1
                fi
                chmod +x "${idleleo_dir}/file_manager.sh"
            fi
            case $upstream_choose in
            1) source "${idleleo_dir}/file_manager.sh" wsServers ${fm_file_path} ;;
            2) source "${idleleo_dir}/file_manager.sh" grpcServers ${fm_file_path} ;;
            3) ;;
            *) 
                echo -e "${Error} ${RedBG} 无效选项 请重试 ${Font}" 
                nginx_upstream_server_set
                ;;
            esac
            ;;
        *) ;;
        esac
    else
        echo -e "${Error} ${RedBG} 当前模式不支持此操作! ${Font}"
    fi
}

nginx_servernames_server_set() {
    if [[ ${tls_mode} == "Reality" ]] && [[ ${reality_add_nginx} == "on" ]]; then
        echo -e "\n${GreenBG} 是否变更 Nginx serverNames 配置 [Y/${Red}N${Font}${GreenBG}]? ${Font}"
        echo -e "${Warning} ${YellowBG} 如不清楚具体用途, 请勿继续! ${Font}"
        echo -e "${Info} ${GreenBG} 配置用途可以参考文章: (敬请期待) ${Font}"
        read -r nginx_servernames_server_fq
        case $nginx_servernames_server_fq in
        [yY][eE][sS] | [yY])
            fm_remote_url="https://raw.githubusercontent.com/hello-yunshu/Xray_bash_onekey/main/file_manager.sh"
            fm_file_path=${nginx_conf_dir}
            if [ ! -f "${idleleo_dir}/file_manager.sh" ]; then
                echo -e "${Info} ${Green} 本地文件 file_manager.sh 不存在，正在下载... ${Font}"
                curl -sL "$fm_remote_url" -o "${idleleo_dir}/file_manager.sh"
                if [ $? -ne 0 ]; then
                    echo -e "${Error} ${RedBG} 下载失败，请手动下载并安装新版本 ${Font}"
                    return 1
                fi
                chmod +x "${idleleo_dir}/file_manager.sh"
            fi
            source "${idleleo_dir}/file_manager.sh" serverNames ${fm_file_path}
        ;;
        *) ;;
        esac
    else
        echo -e "${Error} ${RedBG} 当前模式不支持此操作! ${Font}"
    fi
}

UUIDv5_tranc() {
    [[ $# = 0 ]] && return
    echo "import uuid;UUID_NAMESPACE=uuid.UUID('00000000-0000-0000-0000-000000000000');print(uuid.uuid5(UUID_NAMESPACE,'$1'));" | python3
}

modify_listen_address() {
    if [[ ${tls_mode} == "Reality" ]]; then
        modifynum=1
        modifynum2=2
    else
        modifynum=0
        modifynum2=1
    fi
    if [[ ${ws_grpc_mode} == "onlyws" ]]; then
        jq ".inbounds[${modifynum}].listen = \"0.0.0.0\"" ${xray_conf} > "${xray_conf}.tmp"
        judge "Xray listen address 修改"
    elif [[ ${ws_grpc_mode} == "onlygRPC" ]]; then
        jq ".inbounds[${modifynum2}].listen = \"0.0.0.0\"" ${xray_conf} > "${xray_conf}.tmp"
        judge "Xray listen address 修改"
    elif [[ ${ws_grpc_mode} == "all" ]]; then
        jq ".inbounds[${modifynum}].listen = \"0.0.0.0\"|.inbounds[${modifynum2}].listen = \"0.0.0.0\"" ${xray_conf} > "${xray_conf}.tmp"
        judge "Xray listen address 修改"
    fi
    mv "${xray_conf}.tmp" "${xray_conf}"
}

modify_inbound_port() {
    if [[ ${tls_mode} == "Reality" ]]; then
        if [[ ${reality_add_nginx} != "on" ]]; then
            jq ".inbounds[0].port = ${port}|.inbounds[1].port = ${xport}|.inbounds[2].port = ${gport}" ${xray_conf} > "${xray_conf}.tmp"
            judge "Xray inbound port 修改"
        else
            jq ".inbounds[1].port = ${xport}|.inbounds[2].port = ${gport}" ${xray_conf} > "${xray_conf}.tmp"
            judge "Xray inbound port 修改"
        fi
    else
        jq ".inbounds[0].port = ${xport}|.inbounds[1].port = ${gport}" ${xray_conf} > "${xray_conf}.tmp"
        judge "Xray inbound port 修改"
    fi
    mv "${xray_conf}.tmp" "${xray_conf}"
}

modify_nginx_origin_conf() {
    sed -i "s/worker_processes  1;/worker_processes  auto;/" ${nginx_dir}/conf/nginx.conf
    sed -i "s/^\( *\)worker_connections  1024;.*/\1worker_connections  4096;/" ${nginx_dir}/conf/nginx.conf
    if [[ ${tls_mode} == "TLS" ]]; then
        sed -i "\$i include ${nginx_conf_dir}/*.conf;" ${nginx_dir}/conf/nginx.conf
    elif [[ ${tls_mode} == "Reality" ]] && [[ ${reality_add_nginx} == "on" ]]; then
        sed -i "\$a include ${nginx_conf_dir}/*.conf;" ${nginx_dir}/conf/nginx.conf
    fi
    sed -i "/http\( *\){/a \\\tserver_tokens off;" ${nginx_dir}/conf/nginx.conf
    sed -i "/error_page.*504/i \\\t\\tif (\$host = '${local_ip}') {\\n\\t\\t\\treturn 403;\\n\\t\\t}" ${nginx_dir}/conf/nginx.conf
}

modify_nginx_port() {
    sed -i "s/^\( *\).*ssl;$/\1listen ${port} ssl;/" ${nginx_conf}
    sed -i "3s/^\( *\).*ssl;$/\1listen [::]:${port} ssl;/" ${nginx_conf}
    judge "Xray port 修改"
    [[ -f "${xray_qr_config_file}" ]] && sed -i "s/^\( *\)\"port\".*/\1\"port\": \"${port}\",/" ${xray_qr_config_file}
    echo -e "${Green} 端口号: ${port} ${Font}"
}

modify_nginx_ssl_other() {
    if [[ -f "${nginx_dir}/conf/nginx.conf" ]] && [[ $(grep -c "server_tokens off;" ${nginx_dir}/conf/nginx.conf) -eq '0' ]] && [[ ${save_originconf} != "Yes" ]]; then
        modify_nginx_origin_conf
    fi
    sed -i "s/^\( *\)server_name\( *\).*/\1server_name\2${domain};/g" ${nginx_ssl_conf}
    sed -i "s/^\( *\)return 301.*/\1return 301 https:\/\/${domain}\$request_uri;/" ${nginx_ssl_conf}
}

modify_nginx_other() {
    if [[ -f "${nginx_dir}/conf/nginx.conf" ]] && [[ $(grep -c "server_tokens off;" ${nginx_dir}/conf/nginx.conf) -eq '0' ]] && [[ ${save_originconf} != "Yes" ]]; then
        modify_nginx_origin_conf
    fi
    if [[ ${tls_mode} == "TLS" ]]; then
        sed -i "s/^\( *\)server_name\( *\).*/\1server_name\2${domain};/g" ${nginx_conf}
        sed -i "s/^\( *\)location ws$/\1location \/${path}/" ${nginx_conf}
        sed -i "s/^\( *\)location grpc$/\1location \/${serviceName}/" ${nginx_conf}
        sed -i "s/^\( *\)return 301.*/\1return 301 https:\/\/${domain}\$request_uri;/" ${nginx_conf}
        if [[ ${ws_grpc_mode} == "onlyws" ]]; then
            sed -i "s/^\( *\)#proxy_pass\(.*\)/\1proxy_pass\2/" ${nginx_conf}
            sed -i "s/^\( *\)#proxy_redirect default;/\1proxy_redirect default;/" ${nginx_conf}
        elif [[ ${ws_grpc_mode} == "onlygRPC" ]]; then
            sed -i "s/^\( *\)#grpc_pass\(.*\)/\1grpc_pass\2/" ${nginx_conf}
        elif [[ ${ws_grpc_mode} == "all" ]]; then
            sed -i "s/^\( *\)#proxy_pass\(.*\)/\1proxy_pass\2/" ${nginx_conf}
            sed -i "s/^\( *\)#proxy_redirect default;/\1proxy_redirect default;/" ${nginx_conf}
            sed -i "s/^\( *\)#grpc_pass\(.*\)/\1grpc_pass\2/" ${nginx_conf}
        fi
    elif [[ ${tls_mode} == "Reality" ]] && [[ ${reality_add_nginx} == "on" ]]; then
        # sed -i "s/^\( *\).* reality;\( *\)/\1${serverNames} reality;\2/g" ${nginx_conf} 观察
        sed -i "s/^\( *\)listen 443 reuseport;\(.*\)/\1listen ${port} reuseport;\2/" ${nginx_conf}
    fi
}

nginx_servers_add() {
    touch ${nginx_conf_dir}/127.0.0.1.wsServers
    cat >${nginx_conf_dir}/127.0.0.1.wsServers <<EOF
server 127.0.0.1:${xport} weight=50 max_fails=2 fail_timeout=10;
EOF
    touch ${nginx_conf_dir}/127.0.0.1.grpcServers
    cat >${nginx_conf_dir}/127.0.0.1.grpcServers<<EOF
server 127.0.0.1:${gport} weight=50 max_fails=2 fail_timeout=10;
EOF
}

modify_path() {
    sed -i "s/^\( *\)\"path\".*/\1\"path\": \"\/${path}\"/" ${xray_conf}
    sed -i "s/^\( *\)\"serviceName\".*/\1\"serviceName\": \"${serviceName}\",/" ${xray_conf}
    if [[ ${tls_mode} != "Reality" ]] || [[ "$reality_add_more" == "off" ]]; then
        judge "Xray 伪装路径 修改"
    else
        echo -e "${Warning} ${YellowBG} Reality 不支持 path ${Font}"
    fi
}

modify_email_address() {
    if [[ $(jq -r '.inbounds[0].settings.clients|length' ${xray_conf}) == 1 ]] && [[ $(jq -r '.inbounds[1].settings.clients|length' ${xray_conf}) == 1 ]]; then
        sed -i "s/^\( *\)\"email\".*/\1\"email\": \"${custom_email}\"/g" ${xray_conf}
        judge "Xray 用户名 修改"
    else
        echo -e "\n${Warning} ${YellowBG} 请先删除 多余的用户  ${Font}"
    fi
}

modify_UUID() {
    if [[ $(jq -r '.inbounds[0].settings.clients|length' ${xray_conf}) == 1 ]] && [[ $(jq -r '.inbounds[1].settings.clients|length' ${xray_conf}) == 1 ]]; then
        sed -i "s/^\( *\)\"id\".*/\1\"id\": \"${UUID}\",/g" ${xray_conf}
        judge "Xray UUID 修改"
        [[ -f "${xray_qr_config_file}" ]] && sed -i "s/^\( *\)\"id\".*/\1\"id\": \"${UUID}\",/" ${xray_qr_config_file}
        [[ -f "${xray_qr_config_file}" ]] && sed -i "s/^\( *\)\"idc\".*/\1\"idc\": \"${UUID5_char}\",/" ${xray_qr_config_file}
    else
        echo -e "\n${Warning} ${YellowBG} 请先删除 多余的用户 ${Font}"
    fi
}

modify_Reality() {
  jq --arg target "${target}:443" --arg serverNames "${serverNames}" --arg privateKey "${privateKey}" --arg shortIds "${shortIds}" '
  .inbounds[0].streamSettings.realitySettings = {
    target: $target,
    serverNames: [$serverNames],
    privateKey: $privateKey,
    shortIds: [$shortIds]
  }' "${xray_conf}" > "${xray_conf}.tmp"
  judge "Xray Reality 配置修改"
  mv "${xray_conf}.tmp" "${xray_conf}"
}

web_camouflage() {
    judge "web 站点伪装"
}

xray_privilege_escalation() {
    [[ $(grep "nogroup" /etc/group) ]] && cert_group="nogroup"
    if [[ -n "$(grep "User=nobody" ${xray_systemd_file})" ]]; then
        echo -e "${OK} ${GreenBG} 检测到 Xray 的权限控制, 启动擦屁股程序 ${Font}"
        chmod -fR a+rw /var/log/xray/
        chown -fR nobody:${cert_group} /var/log/xray/
        chown -fR nobody:${cert_group} ${ssl_chainpath}/*
    fi
    echo -e "${OK} ${GreenBG} Xray 擦屁股 完成 ${Font}"
}

xray_install() {
    if [[ $(xray version) == "" ]] || [[ ! -f "${xray_conf}" ]]; then
        bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -f --version v${xray_version}
        judge "安装 Xray"
        systemctl daemon-reload
        [[ -f "${ssl_chainpath}/xray.key" ]] && xray_privilege_escalation
        [[ -f "${xray_default_conf}" ]] && rm -rf ${xray_default_conf}
        ln -s ${xray_conf} ${xray_default_conf}
    else
        echo -e "${OK} ${GreenBG} 已安装 Xray ${Font}"
    fi
}

xray_update() {
    [[ ! -d "${local_bin}/etc/xray" ]] && echo -e "${GreenBG} 若更新无效, 建议直接卸载再安装! ${Font}"
    echo -e "${Warning} ${GreenBG} 部分新功能需要重新安装才可生效 ${Font}"
    xray_online_version=$(check_version xray_online_version)
    ## xray_online_version=$(check_version xray_online_pre_version)
    ## if [[ $(info_extraction xray_version) != ${xray_online_version} ]] && [[ ${xray_version} != ${xray_online_version} ]]; then
    if [[ $(info_extraction xray_version) != ${xray_online_version} ]]; then
        if [[ ${auto_update} != "YES" ]]; then
            echo -e "${Warning} ${GreenBG} 检测到存在最新版 ${Font}"
            echo -e "${Warning} ${GreenBG} 脚本可能未兼容此版本 ${Font}"
            echo -e "\n${Warning} ${GreenBG} 是否更新 [Y/${Red}N${Font}${GreenBG}]? ${Font}"
            read -r xray_test_fq
        else
            xray_test_fq=1
        fi
        case $xray_test_fq in
        [yY][eE][sS] | [yY])
            echo -e "${OK} ${GreenBG} 即将升级 Xray ! ${Font}"
            systemctl stop xray
            ## xray_version=${xray_online_version}
            bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -f --version v${xray_version}
            judge "Xray 升级"
            ;;
        *)
            echo -e "${OK} ${GreenBG} 即将升级/重装 Xray ! ${Font}"
            systemctl stop xray
            xray_version=$(info_extraction xray_version)
            bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -f --version v${xray_version}
            judge "Xray 升级"
            ;;
        esac
    else
        timeout "升级/重装 Xray !"
        systemctl stop xray
        bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -f --version v${xray_version}
        judge "Xray 升级"
    fi
    [[ -f "${ssl_chainpath}/xray.key" ]] && xray_privilege_escalation
    [[ -f "${xray_default_conf}" ]] && rm -rf ${xray_default_conf}
    ln -s ${xray_conf} ${xray_default_conf}
    jq ".xray_version = \"${xray_version}\"" ${xray_qr_config_file} > "${xray_qr_config_file}.tmp"
    mv "${xray_qr_config_file}.tmp" "${xray_qr_config_file}"
    systemctl daemon-reload
    systemctl start xray
}

reality_nginx_add_fq() {
    echo -e "\n${Warning} ${Green} Reality 协议有流量偷跑的风险 ${Font}"
    echo -e "${Warning} ${Green} 该风险在 target 网址被 cdn 加速时存在 ${Font}"
    echo -e "${GreenBG} 是否额外安装 nginx 前置保护(推荐) [${Red}Y${Font}${GreenBG}/N]? ${Font}"
    read -r reality_nginx_add_fq
    case $reality_nginx_add_fq in
        [nN][oO] | [nN])
            echo -e "${OK} ${GreenBG} 已跳过安装 nginx ${Font}"
        ;;
        *)
            reality_add_nginx="on"
            nginx_exist_check
            nginx_systemd
            nginx_reality_conf_add
            nginx_reality_serverNames_add
        ;;

    esac
}

nginx_exist_check() {
    if [[ -f "${nginx_dir}/sbin/nginx" ]] && [[ "$(info_extraction nginx_build_version)" == "null" ]]; then
        if [[ -d "${nginx_conf_dir}" ]]; then
            rm -rf ${nginx_conf_dir}/*.conf
            if [[ -f "${nginx_conf_dir}/nginx.default" ]]; then
                cp -fp ${nginx_conf_dir}/nginx.default ${nginx_dir}/conf/nginx.conf
            elif [[ -f "${nginx_dir}/conf/nginx.conf.default" ]]; then
                cp -fp ${nginx_dir}/conf/nginx.conf.default ${nginx_dir}/conf/nginx.conf
            else
                sed -i "/if \(.*\) {$/,+2d" ${nginx_dir}/conf/nginx.conf
                sed -i "/^include.*\*\.conf;$/d" ${nginx_dir}/conf/nginx.conf
            fi
        else
            sed -i "/if \(.*\) {$/,+2d" ${nginx_dir}/conf/nginx.conf
            sed -i "/^include.*\*\.conf;$/d" ${nginx_dir}/conf/nginx.conf
        fi
        modify_nginx_origin_conf
        echo -e "${OK} ${GreenBG} Nginx 已存在, 跳过编译安装过程 ${Font}"
    #兼容代码，下个大版本删除
    elif [[ -d "/etc/nginx" ]] && [[ "$(info_extraction nginx_version)" == "null" ]]; then
        echo -e "${Error} ${GreenBG} 检测到旧版本安装的 nginx ! ${Font}"
        echo -e "${Warning} ${GreenBG} 请先做好备份 ${Font}"
        echo -e "${GreenBG} 是否需要删除 (请删除) [${Red}Y${Font}${GreenBG}/N]? ${Font}"
        read -r remove_nginx_fq
        case $remove_nginx_fq in
        [nN][oO] | [nN])
        echo -e "${OK} ${GreenBG} 已跳过删除 nginx ${Font}"
        source "$idleleo"
            ;;
        *)
            rm -rf /etc/nginx/
            [[ -f "${nginx_systemd_file}" ]] && rm -rf ${nginx_systemd_file}
            [[ -d "${nginx_conf_dir}" ]] && rm -rf ${nginx_conf_dir}/*.conf
            echo -e "${Warning} ${GreenBG} 日志目录已更改, 日志清除需要重新设置 ! ${Font}"
            nginx_install
            ;;
        esac
    #兼容代码结束
    elif [[ -d "/etc/nginx" ]] && [[ "$(info_extraction nginx_version)" == "null" ]]; then
        echo -e "${Error} ${RedBG} 检测到其他套件安装的 Nginx, 继续安装会造成冲突, 请处理后安装! ${Font}"
        exit 1
    else
        nginx_install
    fi
}

nginx_install() {
    local latest_version=$(check_version nginx_build_online_version)
    local temp_dir=$(mktemp -d)
    local current_dir=$(pwd)

    cd "$temp_dir" || exit

    echo -e "${OK} ${GreenBG} 即将下载已编译的 Nginx ${Font}"
    local url="https://github.com/hello-yunshu/Xray_bash_onekey_Nginx/releases/download/v${latest_version}/xray-nginx-custom.tar.gz"
    wget -q --show-progress --progress=bar:force:noscroll "$url" -O xray-nginx-custom.tar.gz
    tar -xzvf xray-nginx-custom.tar.gz -C ./
    [[ -d ${nginx_dir} ]] && rm -rf "${nginx_dir}"
    mv ./nginx "${nginx_dir}"
    
    cp -fp ${nginx_dir}/conf/nginx.conf ${nginx_conf_dir}/nginx.default

    # 修改基本配置
    #sed -i 's/#user  nobody;/user  root;/' ${nginx_dir}/conf/nginx.conf
    modify_nginx_origin_conf

    # 删除临时文件
    cd "$current_dir" && rm -rf "$temp_dir"
    chown -R nobody:nogroup "${nginx_dir}"
    chmod -R 755 "${nginx_dir}"
}

nginx_update() {
    if [[ -f "${nginx_dir}/sbin/nginx" ]]; then
        if [[ ${nginx_build_version} != $(info_extraction nginx_build_version) ]]; then
            ip_check
            if [[ -f "${xray_qr_config_file}" ]]; then
                domain=$(info_extraction host)
                if [[ ${tls_mode} == "TLS" ]]; then
                    port=$(info_extraction port)
                    if [[ ${ws_grpc_mode} == "onlyws" ]]; then
                        xport=$(info_extraction ws_port)
                        path=$(info_extraction path)
                        gport=$((RANDOM % 1000 + 30000))
                        [[ ${gport} == ${xport} ]] && gport=$((RANDOM % 1000 + 30000))
                        serviceName="$(head -n 10 /dev/urandom | md5sum | head -c ${random_num})"
                    elif [[ ${ws_grpc_mode} == "onlygRPC" ]]; then
                        gport=$(info_extraction grpc_port)
                        serviceName=$(info_extraction serviceName)
                        xport=$((RANDOM % 1000 + 20000))
                        path="$(head -n 10 /dev/urandom | md5sum | head -c ${random_num})"
                    elif [[ ${ws_grpc_mode} == "all" ]]; then
                        xport=$(info_extraction ws_port)
                        path=$(info_extraction path)
                        gport=$(info_extraction grpc_port)
                        serviceName=$(info_extraction serviceName)
                    fi
                    if [[ 0 -eq ${read_config_status} ]]; then
                        [[ ${auto_update} == "YES" ]] && echo "Nginx 配置文件不完整, 退出升级!" && exit 1
                        echo -e "${Error} ${RedBG} 配置文件不完整, 退出升级 ${Font}"
                        return 1
                    fi
                elif [[ ${tls_mode} == "Reality" ]] && [[ ${reality_add_nginx} == "on" ]]; then
                    port=$(info_extraction port)
                    serverNames=$(info_extraction serverNames)
                    if [[ 0 -eq ${read_config_status} ]]; then
                        [[ ${auto_update} == "YES" ]] && echo "Nginx 配置文件不完整, 退出升级!" && exit 1
                        echo -e "${Error} ${RedBG} 配置文件不完整, 退出升级 ${Font}"
                        return 1
                    fi
                elif [[ ${tls_mode} == "None" ]]; then
                    [[ ${auto_update} == "YES" ]] && echo "当前安装模式不需要 Nginx !" && exit 1
                    echo -e "${Error} ${RedBG} 当前安装模式不需要 Nginx ! ${Font}"
                    return 1
                fi
            else
                [[ ${auto_update} == "YES" ]] && echo "Nginx 配置文件不存在, 退出升级!" && exit 1
                echo -e "${Error} ${RedBG} 配置文件不存在, 退出升级 ${Font}"
                return 1
            fi
            service_stop
            timeout "删除旧版 Nginx !"
            rm -rf ${nginx_dir}
            if [[ ${auto_update} != "YES" ]]; then
                echo -e "\n${GreenBG} 是否保留原 Nginx 配置文件 [${Red}Y${Font}${GreenBG}/N]? ${Font}"
                read -r save_originconf_fq
            else
                save_originconf_fq=1
            fi
            case $save_originconf_fq in
            [nN][oO] | [nN])
                rm -rf ${nginx_conf_dir}/*.conf
                echo -e "${OK} ${GreenBG} 原配置文件已删除! ${Font}"
                ;;
            *)
                save_originconf="Yes"
                echo -e "${OK} ${GreenBG} 原配置文件已保留! ${Font}"
                ;;
            esac
            nginx_install
            if [[ ${tls_mode} == "TLS" ]] && [[ ${save_originconf} != "Yes" ]]; then
                nginx_ssl_conf_add
                nginx_conf_add
                nginx_servers_conf_add
            elif [[ ${tls_mode} == "Reality" ]] && [[ ${reality_add_nginx} == "on" ]] && [[ ${save_originconf} != "Yes" ]]; then
                nginx_reality_conf_add
            fi
            service_start
            jq ".nginx_build_version = \"${nginx_build_version}\"" ${xray_qr_config_file} > "${xray_qr_config_file}.tmp"
            mv "${xray_qr_config_file}.tmp" "${xray_qr_config_file}"
            judge "Nginx 升级"
        else
            echo -e "${OK} ${GreenBG} Nginx 已为最新版 ${Font}"
        fi
    else
        echo -e "${Error} ${RedBG} Nginx 未安装 ${Font}"
    fi
}

auto_update() {
    if [[ "${ID}" == "centos" ]]; then
        crontab_file="/var/spool/cron/root"
    else
        crontab_file="/var/spool/cron/crontabs/root"
    fi
    if [[ ! -f "${auto_update_file}" ]] || [[ $(crontab -l | grep -c "auto_update.sh") -lt 1 ]]; then
        echo -e "\n${GreenBG} 设置后台定时自动更新程序 (包含: 脚本/Xray/Nginx) ${Font}"
        echo -e "${GreenBG} 可能自动更新后有兼容问题, 谨慎开启 ${Font}"
        echo -e "${GreenBG} 是否开启 [Y/${Red}N${Font}${GreenBG}]? ${Font}"
        read -r auto_update_fq
        case $auto_update_fq in
        [yY][eE][sS] | [yY])
            wget -N -P ${idleleo_dir} --no-check-certificate https://raw.githubusercontent.com/hello-yunshu/Xray_bash_onekey/main/auto_update.sh && chmod +x ${auto_update_file}
            echo "0 1 15 * * bash ${auto_update_file}" >>${crontab_file}
            judge "设置自动更新"
            ;;
        *) ;;
        esac
    else
        echo -e "${OK} ${GreenBG} 已设置自动更新 ${Font}"
        echo -e "${GreenBG} 是否关闭? [Y/${Red}N${Font}${GreenBG}]? ${Font}"
        read -r auto_update_close_fq
        case $auto_update_fq in
        [yY][eE][sS] | [yY])
            sed -i "/auto_update.sh/d" ${crontab_file}
            rm -rf ${auto_update_file}
            judge "删除自动更新"
            ;;
        *) ;;
        esac
    fi
}

ssl_install() {
    pkg_install "socat"
    judge "安装 SSL 证书生成脚本依赖"
    curl https://get.acme.sh | sh -s email=${custom_email}
    judge "安装 SSL 证书生成脚本"
}

domain_check() {
    if [[ "on" == ${old_config_status} ]] && [[ $(info_extraction host) != null ]] && [[ $(info_extraction ip_version) != null ]]; then
        echo -e "\n${GreenBG} 检测到原域名配置存在, 是否跳过域名设置 [${Red}Y${Font}${GreenBG}/N]? ${Font}"
        read -r old_host_fq
        case $old_host_fq in
        [nN][oO] | [nN]) ;;
        *)
            domain=$(info_extraction host)
            ip_version=$(info_extraction ip_version)
            if [[ ${ip_version} == "IPv4" ]]; then
                local_ip=$(curl -4 ip.sb)
            elif [[ ${ip_version} == "IPv6" ]]; then
                local_ip=$(curl -6 ip.sb)
            else
                local_ip=${ip_version}
            fi
            echo -e "${OK} ${GreenBG} 已跳过域名设置 ${Font}"
            return 0
            ;;
        esac
    fi
    echo -e "\n${GreenBG} 确定 域名 信息 ${Font}"
    read_optimize "请输入你的域名信息 (e.g. www.idleleo.com):" "domain" "NULL"
    echo -e "\n${GreenBG} 请选择 公网IP(IPv4/IPv6) 或手动输入 域名 ${Font}"
    echo -e "${Red}1${Font}: IPv4 (默认)"
    echo "2: IPv6 (不推荐)"
    echo "3: 域名"
    read -rp "请输入: " ip_version_fq
    [[ -z ${ip_version_fq} ]] && ip_version_fq=1
    echo -e "${OK} ${GreenBG} 正在获取 公网IP 信息, 请耐心等待 ${Font}"
    if [[ ${ip_version_fq} == 1 ]]; then
        local_ip=$(curl -4 ip.sb)
        domain_ip=$(ping -4 "${domain}" -c 1 | sed '1{s/[^(]*(//;s/).*//;q}')
        ip_version="IPv4"
    elif [[ ${ip_version_fq} == 2 ]]; then
        local_ip=$(curl -6 ip.sb)
        domain_ip=$(ping -6 "${domain}" -c 1 | sed '2{s/[^(]*(//;s/).*//;q}' | tail -n +2)
        ip_version="IPv6"
    elif [[ ${ip_version_fq} == 3 ]]; then
        echo -e "${Warning} ${GreenBG} 此选项用于服务器商仅提供域名访问服务器 ${Font}"
        echo -e "${Warning} ${GreenBG} 注意服务器商域名添加 CNAME 记录 ${Font}"
        read -rp "请输入: " local_ip
        ip_version=${local_ip}
    else
        local_ip=$(curl -4 ip.sb)
        domain_ip=$(ping -4 "${domain}" -c 1 | sed '1{s/[^(]*(//;s/).*//;q}')
        ip_version="IPv4"
    fi
    echo -e "域名DNS 解析IP: ${domain_ip}"
    echo -e "公网IP/域名: ${local_ip}"
    if [[ ${ip_version_fq} != 3 ]] && [[ ${local_ip} == ${domain_ip} ]]; then
        echo -e "${OK} ${GreenBG} 域名DNS 解析IP 与 公网IP 匹配 ${Font}"
    else
        echo -e "${Warning} ${YellowBG} 请确保域名添加了正确的 A/AAAA 记录, 否则将无法正常使用 Xray ${Font}"
        echo -e "${Error} ${RedBG} 域名DNS 解析IP 与 公网IP 不匹配, 请选择: ${Font}"
        echo "1: 继续安装"
        echo "2: 重新输入"
        echo -e "${Red}3${Font}: 终止安装 (默认)"
        read -r install
        case $install in
        1)
            echo -e "${OK} ${GreenBG} 继续安装 ${Font}"
            ;;
        2)
            domain_check
            ;;
        *)
            echo -e "${Error} ${RedBG} 安装终止 ${Font}"
            exit 2
            ;;
        esac
    fi
}

ip_check() {
    if [[ "on" == ${old_config_status} || ${auto_update} == "YES" ]] && [[ $(info_extraction host) != null ]] && [[ $(info_extraction ip_version) != null ]]; then
        if [[ ${auto_update} != "YES" ]]; then
            echo -e "\n${GreenBG} 检测到原IP配置存在, 是否跳过IP设置 [${Red}Y${Font}${GreenBG}/N]? ${Font}"
            read -r old_host_fq
        else
            old_host_fq=1
        fi
        case $old_host_fq in
        [nN][oO] | [nN]) ;;
        *)
            ip_version=$(info_extraction ip_version)
            if [[ ${ip_version} == "IPv4" ]]; then
                local_ip=$(curl -4 ip.sb)
            elif [[ ${ip_version} == "IPv6" ]]; then
                local_ip=$(curl -6 ip.sb)
            else
                local_ip=${ip_version}
            fi
            echo -e "\n${OK} ${GreenBG} 已跳过IP设置 ${Font}"
            return 0
            ;;
        esac
    # ##兼容代码，未来删除
    # elif [[ ${auto_update} == "YES" ]] && [[ $(info_extraction ip_version) == null ]]; then
    #     echo "无法测试 IP 版本, 跳过 Nginx 更新!" >>${log_file}
    #     echo "(原因来自于脚本版本低无法兼容, 重装可解决问题)" >>${log_file}
    #     exit 1
    fi
    echo -e "\n${GreenBG} 确定 公网IP 信息 ${Font}"
    echo -e "${GreenBG} 请选择 公网IP 为 IPv4 或 IPv6 ${Font}"
    echo -e "${Red}1${Font}: IPv4 (默认)"
    echo "2: IPv6 (不推荐)"
    echo "3: 手动输入"
    read -rp "请输入: " ip_version_fq
    [[ -z ${ip_version_fq} ]] && ip_version=1
    echo -e "${OK} ${GreenBG} 正在获取 公网IP 信息, 请耐心等待 ${Font}"
    if [[ ${ip_version_fq} == 1 ]]; then
        local_ip=$(curl -4 ip.sb)
        ip_version="IPv4"
    elif [[ ${ip_version_fq} == 2 ]]; then
        local_ip=$(curl -6 ip.sb)
        ip_version="IPv6"
    elif [[ ${ip_version_fq} == 3 ]]; then
        read -rp "请输入: " local_ip
        ip_version=${local_ip}
    else
        local_ip=$(curl -4 ip.sb)
        ip_version="IPv4"
    fi
    echo -e "公网IP/域名: ${local_ip}"
}

port_exist_check() {
    if [[ 0 -eq $(lsof -i:"$1" | grep -i -c "listen") ]]; then
        echo -e "${OK} ${GreenBG} $1 端口未被占用 ${Font}"
    else
        echo -e "${Error} ${RedBG} 检测到 $1 端口被占用, 以下为 $1 端口占用信息 ${Font}"
        lsof -i:"$1"
        timeout "尝试自动 kill 占用进程!"
        lsof -i:"$1" | awk '{print $2}' | grep -v "PID" | xargs kill -9
        echo -e "${OK} ${GreenBG} kill 完成 ${Font}"
    fi
}

acme() {
    systemctl restart nginx
    #暂时解决ca问题
    if "$HOME"/.acme.sh/acme.sh --issue -d ${domain} -w ${idleleo_conf_dir} --server letsencrypt --keylength ec-256 --force --test; then
    #if "$HOME"/.acme.sh/acme.sh --issue -d ${domain} -w ${idleleo_conf_dir} --keylength ec-256 --force --test; then
        echo -e "${OK} ${GreenBG} SSL 证书测试签发成功, 开始正式签发 ${Font}"
        rm -rf "$HOME/.acme.sh/${domain}_ecc"
    else
        echo -e "${Error} ${RedBG} SSL 证书测试签发失败 ${Font}"
        rm -rf "$HOME/.acme.sh/${domain}_ecc"
        exit 1
    fi

    if "$HOME"/.acme.sh/acme.sh --issue -d ${domain} -w ${idleleo_conf_dir} --server letsencrypt --keylength ec-256 --force; then
    #if "$HOME"/.acme.sh/acme.sh --issue -d ${domain} -w ${idleleo_conf_dir} --keylength ec-256 --force; then
        echo -e "${OK} ${GreenBG} SSL 证书生成成功 ${Font}"
        mkdir -p ${ssl_chainpath}
        if "$HOME"/.acme.sh/acme.sh --installcert -d ${domain} --fullchainpath ${ssl_chainpath}/xray.crt --keypath ${ssl_chainpath}/xray.key --ecc --force; then
            chmod -f a+rw ${ssl_chainpath}/xray.crt
            chmod -f a+rw ${ssl_chainpath}/xray.key
            [[ $(grep "nogroup" /etc/group) ]] && cert_group="nogroup"
            chown -fR nobody:${cert_group} ${ssl_chainpath}/*
            echo -e "${OK} ${GreenBG} 证书配置成功 ${Font}"
            systemctl stop nginx
        fi
    else
        echo -e "${Error} ${RedBG} SSL 证书生成失败 ${Font}"
        rm -rf "$HOME/.acme.sh/${domain}_ecc"
        exit 1
    fi
}

xray_conf_add() {
    if [[ $(info_extraction multi_user) != "yes" ]]; then
        if [[ ${tls_mode} == "TLS" ]]; then
            wget --no-check-certificate https://raw.githubusercontent.com/hello-yunshu/Xray_bash_onekey/main/VLESS_tls/config.json -O ${xray_conf}
            modify_listen_address
            modify_path
            modify_inbound_port
        elif [[ ${tls_mode} == "Reality" ]]; then
            wget --no-check-certificate https://raw.githubusercontent.com/hello-yunshu/Xray_bash_onekey/main/VLESS_reality/config.json -O ${xray_conf}
            modify_Reality
            xray_reality_add_more
        elif [[ ${tls_mode} == "None" ]]; then
            wget --no-check-certificate https://raw.githubusercontent.com/hello-yunshu/Xray_bash_onekey/main/VLESS_tls/config.json -O ${xray_conf}
            modify_listen_address
            modify_path
            modify_inbound_port
        fi
        modify_email_address
        modify_UUID
    else
        echo -e "\n${Warning} ${GreenBG} 检测到 Xray 配置过多用户 ${Font}"
        echo -e "${GreenBG} 是否保留原 Xray 配置文件 [${Red}Y${Font}${GreenBG}/N]? ${Font}"
        read -r save_originxray_fq
        case $save_originxray_fq in
        [nN][oO] | [nN])
            rm -rf ${xray_conf}
            echo -e "${OK} ${GreenBG} 原配置文件已删除! ${Font}"
            xray_conf_add
            ;;
        *) ;;
        esac
    fi
}

xray_reality_add_more() {
    if [[ ${reality_add_more} == "on" ]]; then
        modify_path
        modify_listen_address
        modify_inbound_port
        judge "添加简单 ws/gRPC 协议"
    else
        modify_path
        modify_inbound_port
    fi
}

old_config_exist_check() {
    if [[ -f "${xray_qr_config_file}" ]]; then
        if [[ ${old_tls_mode} == ${tls_mode} ]]; then
            echo -e "\n${GreenBG} 检测到配置文件, 是否读取配置文件 [${Red}Y${Font}${GreenBG}/N]? ${Font}"
            read -r old_config_fq
            case $old_config_fq in
            [nN][oO] | [nN])
                rm -rf ${xray_qr_config_file}
                echo -e "${OK} ${GreenBG} 已删除配置文件 ${Font}"
                ;;
            *)
                echo -e "${OK} ${GreenBG} 已保留配置文件 ${Font}"
                old_config_status="on"
                old_config_input
                ;;
            esac
        else
            echo -e "\n${Warning} ${GreenBG} 检测到当前安装模式与配置文件的安装模式不一致 ${Font}"
            echo -e "${GreenBG} 是否保留配置文件 (强烈不建议) [Y/${Red}N${Font}${GreenBG}]? ${Font}"
            read -r old_config_fq
            case $old_config_fq in
            [yY][eE][sS] | [yY])
                echo -e "${Warning} ${GreenBG} 请务必确保配置文件正确 ${Font}"
                echo -e "${OK} ${GreenBG} 已保留配置文件 ${Font}"
                menu
                ;;
            *)
                rm -rf ${xray_qr_config_file}
                echo -e "${OK} ${GreenBG} 已删除配置文件 ${Font}"
                ;;
            esac
        fi
    fi
}

old_config_input() {
    info_extraction_all=$(jq -rc . ${xray_qr_config_file})
    custom_email=$(info_extraction email)
    UUID5_char=$(info_extraction idc)
    UUID=$(info_extraction id)
    if [[ ${tls_mode} == "TLS" ]]; then
        port=$(info_extraction port)
        if [[ ${ws_grpc_mode} == "onlyws" ]]; then
            xport=$(info_extraction ws_port)
            path=$(info_extraction path)
            gport=$((RANDOM % 1000 + 30000))
            [[ ${gport} == ${xport} ]] && gport=$((RANDOM % 1000 + 30000))
            serviceName="$(head -n 10 /dev/urandom | md5sum | head -c ${random_num})"
        elif [[ ${ws_grpc_mode} == "onlygRPC" ]]; then
            gport=$(info_extraction grpc_port)
            serviceName=$(info_extraction serviceName)
            xport=$((RANDOM % 1000 + 20000))
            [[ ${gport} == ${xport} ]] && xport=$((RANDOM % 1000 + 20000))
            path="$(head -n 10 /dev/urandom | md5sum | head -c ${random_num})"
        elif [[ ${ws_grpc_mode} == "all" ]]; then
            xport=$(info_extraction ws_port)
            path=$(info_extraction path)
            gport=$(info_extraction grpc_port)
            serviceName=$(info_extraction serviceName)
        fi
    elif [[ ${tls_mode} == "Reality" ]]; then
        port=$(info_extraction port)
        target=$(info_extraction target)
        serverNames=$(info_extraction serverNames)
        privateKey=$(info_extraction privateKey)
        publicKey=$(info_extraction publicKey)
        shortIds=$(info_extraction shortIds)
        if [[ ${reality_add_more} == "on" ]]; then
            if [[ ${ws_grpc_mode} == "onlyws" ]]; then
                xport=$(info_extraction ws_port)
                path=$(info_extraction ws_path)
                gport=$((RANDOM % 1000 + 30000))
                [[ ${gport} == ${xport} ]] && gport=$((RANDOM % 1000 + 30000))
                serviceName="$(head -n 10 /dev/urandom | md5sum | head -c ${random_num})"
            elif [[ ${ws_grpc_mode} == "onlygRPC" ]]; then
                gport=$(info_extraction grpc_port)
                serviceName=$(info_extraction grpc_serviceName)
                xport=$((RANDOM % 1000 + 20000))
                [[ ${gport} == ${xport} ]] && xport=$((RANDOM % 1000 + 20000))
                path="$(head -n 10 /dev/urandom | md5sum | head -c ${random_num})"
            elif [[ ${ws_grpc_mode} == "all" ]]; then
                xport=$(info_extraction ws_port)
                path=$(info_extraction ws_path)
                gport=$(info_extraction grpc_port)
                serviceName=$(info_extraction grpc_serviceName)
            fi
        else
            path="$(head -n 10 /dev/urandom | md5sum | head -c ${random_num})"
            serviceName="$(head -n 10 /dev/urandom | md5sum | head -c ${random_num})"
            xport=$((RANDOM % 1000 + 20000))
            gport=$((RANDOM % 1000 + 30000))
        fi
    elif [[ ${tls_mode} == "None" ]]; then
        if [[ ${ws_grpc_mode} == "onlyws" ]]; then
            xport=$(info_extraction ws_port)
            path=$(info_extraction path)
            gport=$((RANDOM % 1000 + 30000))
            [[ ${gport} == ${xport} ]] && gport=$((RANDOM % 1000 + 30000))
            serviceName="$(head -n 10 /dev/urandom | md5sum | head -c ${random_num})"
        elif [[ ${ws_grpc_mode} == "onlygRPC" ]]; then
            gport=$(info_extraction grpc_port)
            serviceName=$(info_extraction serviceName)
            xport=$((RANDOM % 1000 + 20000))
            [[ ${gport} == ${xport} ]] && xport=$((RANDOM % 1000 + 20000))
            path="$(head -n 10 /dev/urandom | md5sum | head -c ${random_num})"
        elif [[ ${ws_grpc_mode} == "all" ]]; then
            xport=$(info_extraction ws_port)
            path=$(info_extraction path)
            gport=$(info_extraction grpc_port)
            serviceName=$(info_extraction serviceName)
        fi
    fi
    if [[ 0 -eq ${read_config_status} ]]; then
        echo -e "\n${GreenBG} 检测到配置文件不完整, 是否保留配置文件 [Y/${Red}N${Font}${GreenBG}]? ${Font}"
        read -r old_config_input_fq
        case $old_config_input_fq in
        [yY][eE][sS] | [yY])
            old_config_status="off"
            echo -e "${OK} ${GreenBG} 已保留配置文件 ${Font}"
            ;;
        *)
            rm -rf ${xray_qr_config_file}
            old_config_status="off"
            echo -e "${OK} ${GreenBG} 已删除配置文件 ${Font}"
            ;;
        esac
    fi
}

nginx_ssl_conf_add() {
    touch ${nginx_ssl_conf}
    cat >${nginx_ssl_conf} <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name serveraddr.com;

    location ^~ /.well-known/acme-challenge/ {
        root ${idleleo_dir}/conf;
        default_type "text/plain"; 
        allow all;
    } 
    location = /.well-known/acme-challenge/ {
        return 404; 
    }

    location / {
        return 301 https://www.idleleo.com\$request_uri;
    }
}
EOF
    modify_nginx_ssl_other
    judge "Nginx SSL 配置修改"
}

nginx_conf_add() {
    touch ${nginx_conf}
    cat >${nginx_conf} <<EOF
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2               on;
    set_real_ip_from    127.0.0.1;
    real_ip_header      X-Forwarded-For;
    real_ip_recursive   on;
    ssl_certificate       ${idleleo_dir}/cert/xray.crt;
    ssl_certificate_key   ${idleleo_dir}/cert/xray.key;
    ssl_protocols         TLSv1.3;
    ssl_ciphers           TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES256-SHA:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES128-SHA;
    server_name           serveraddr.com;
    index index.html index.htm;
    root /403.html;
    error_page 403 https://www.idleleo.com/helloworld;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    ssl_early_data on;
    ssl_stapling on;
    ssl_stapling_verify on;
    ssl_prefer_server_ciphers on;
    add_header Strict-Transport-Security "max-age=31536000";

    location grpc
    {
        #grpc_pass grpc://xray-grpc-server;
        grpc_connect_timeout 60s;
        grpc_read_timeout 720m;
        grpc_send_timeout 720m;
        lingering_close always;
        client_max_body_size 0;
        grpc_set_header X-Real-IP \$remote_addr;
        grpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        grpc_set_header Early-Data \$ssl_early_data;
    }

    location ws
    {
        #proxy_pass http://xray-ws-server;
        #proxy_redirect default;
        proxy_http_version 1.1;
        proxy_connect_timeout 60s;
        proxy_send_timeout 720m;
        proxy_read_timeout 720m;
        proxy_buffering off;
        lingering_close always;
        client_max_body_size 0;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
        proxy_set_header Early-Data \$ssl_early_data;
    }

    location /
    {
        return 403;
    }
}
EOF
    modify_nginx_port
    modify_nginx_other
    judge "Nginx 配置修改"
}

nginx_reality_conf_add() {
    touch ${nginx_conf}
    cat >${nginx_conf} <<EOF

stream {
    map \$ssl_preread_server_name \$stream_map {
        include ${nginx_conf_dir}/*.serverNames;
    }
 
    upstream reality {
        server 127.0.0.1:9443;
    }

    server {
        listen 443 reuseport;
        proxy_pass \$stream_map;
        ssl_preread on;
        #proxy_protocol on;
    }
}
EOF
    modify_nginx_other
    judge "Nginx 配置修改"
}

nginx_reality_serverNames_add () {
    touch ${nginx_conf_dir}/${serverNames}.serverNames
    cat >${nginx_conf_dir}/${serverNames}.serverNames <<EOF
${serverNames} reality;
EOF
    # modify_nginx_reality_serverNames
    judge "Nginx serverNames 配置修改"

}

nginx_servers_conf_add() {
    touch ${nginx_upstream_conf}
    cat >${nginx_upstream_conf} <<EOF
upstream xray-ws-server {
    include ${nginx_conf_dir}/*.wsServers;
}

upstream xray-grpc-server {
    include ${nginx_conf_dir}/*.grpcServers;
}
EOF
    nginx_servers_add
    judge "Nginx servers 配置修改"
}

enable_process_systemd() {
    if [[ ${tls_mode} == "TLS" ]] || [[ ${reality_add_nginx} == "on" ]]; then
        [[ -f "${nginx_systemd_file}" ]] && systemctl enable nginx && judge "设置 Nginx 开机自启"
    fi
    systemctl enable xray
    judge "设置 Xray 开机自启"
}

disable_process_systemd() {
    if [[ ${tls_mode} == "TLS" ]] || [[ ${reality_add_nginx} == "on" ]]; then
        [[ -f "${nginx_systemd_file}" ]] && systemctl stop nginx && systemctl disable nginx && judge "关闭 Nginx 开机自启"
    fi
    systemctl disable xray
    judge "关闭 Xray 开机自启"
}

stop_service_all() {
    [[ -f "${nginx_systemd_file}" ]] && systemctl stop nginx && systemctl disable nginx
    systemctl stop xray
    systemctl disable xray
    echo -e "${OK} ${GreenBG} 停止已有服务 ${Font}"
}

service_restart() {
    systemctl daemon-reload
    if [[ ${tls_mode} == "TLS" ]] || [[ ${reality_add_nginx} == "on" ]]; then
        [[ -f "${nginx_systemd_file}" ]] && systemctl restart nginx && judge "Nginx 重启"
    fi
    systemctl restart xray
    judge "Xray 重启"
}

service_start() {
    if [[ ${tls_mode} == "TLS" ]] || [[ ${reality_add_nginx} == "on" ]]; then
        [[ -f "${nginx_systemd_file}" ]] && systemctl start nginx && judge "Nginx 启动"
    fi
    systemctl start xray
    judge "Xray 启动"
}

service_stop() {
    if [[ ${tls_mode} == "TLS" ]] || [[ ${reality_add_nginx} == "on" ]]; then
        [[ -f "${nginx_systemd_file}" ]] && systemctl stop nginx && judge "Nginx 停止"
    fi
    systemctl stop xray
    judge "Xray 停止"
}

acme_cron_update() {
    if [[ ${tls_mode} == "TLS" ]]; then
        local crontab_file
        if [[ "${ID}" == "centos" ]]; then
            crontab_file="/var/spool/cron/root"
        else
            crontab_file="/var/spool/cron/crontabs/root"
        fi
        if [[ -f "${ssl_update_file}" ]] && [[ $(crontab -l | grep -c "ssl_update.sh") == "1" ]]; then
            echo -e "\n${Warning} ${GreenBG} 新版本已自动设置证书自动更新 ${Font}"
            echo -e "${Warning} ${GreenBG} 老版本请及时删除 废弃的 改版证书自动更新! ${Font}"
            echo -e "${GreenBG} 已设置改版证书自动更新 ${Font}"
            echo -e "${GreenBG} 是否需要删除改版证书自动更新 (请删除) [${Red}Y${Font}${GreenBG}/N]? ${Font}"
            read -r remove_acme_cron_update_fq
            case $remove_acme_cron_update_fq in
            [nN][oO] | [nN]) ;;
            *)
                sed -i "/ssl_update.sh/d" ${crontab_file}
                rm -rf ${ssl_update_file}
                judge "删除改版证书自动更新"
                ;;

            esac
        else
            echo -e "\n${OK} ${GreenBG} 新版本已自动设置证书自动更新 ${Font}"
            # echo -e "${GreenBG} 是否设置证书自动更新 (新版本无需设置) [Y/${Red}N${Font}${GreenBG}]? ${Font}"
            # read -r acme_cron_update_fq
            # case $acme_cron_update_fq in
            # [yY][eE][sS] | [yY])
            #     # if [[ "${ssl_self}" != "on" ]]; then
            #     #     wget -N -P ${idleleo_dir} --no-check-certificate https://raw.githubusercontent.com/hello-yunshu/Xray_bash_onekey/main/ssl_update.sh && chmod +x ${ssl_update_file}
            #     #     if [[ $(crontab -l | grep -c "acme.sh") -lt 1 ]]; then
            #     #         echo "0 3 15 * * bash ${ssl_update_file}" >>${crontab_file}
            #     #     else
            #     #         sed -i "/acme.sh/c 0 3 15 * * bash ${ssl_update_file}" ${crontab_file}
            #     #     fi
            #     #     judge "设置证书自动更新"
            #     # else
            #     #     echo -e "${Error} ${RedBG} 自定义证书不支持此操作! ${Font}"
            #     # fi
            #     echo -e "${Error} ${RedBG} 新版本请勿使用! ${Font}"
            #     ;;
            # *) ;;
            # esac
        fi
    else
        echo -e "${Error} ${RedBG} 当前模式不支持此操作! ${Font}"
    fi
}

check_cert_status() {
    if [[ ${tls_mode} == "TLS" ]]; then
        host="$(info_extraction host)"
        if [[ -d "$HOME/.acme.sh/${host}_ecc" ]] && [[ -f "$HOME/.acme.sh/${host}_ecc/${host}.key" ]] && [[ -f "$HOME/.acme.sh/${host}_ecc/${host}.cer" ]]; then
            modifyTime=$(stat "$HOME/.acme.sh/${host}_ecc/${host}.cer" | sed -n '7,6p' | awk '{print $2" "$3" "$4" "$5}')
            modifyTime=$(date +%s -d "${modifyTime}")
            currentTime=$(date +%s)
            ((stampDiff = currentTime - modifyTime))
            ((days = stampDiff / 86400))
            ((remainingDays = 90 - days))
            tlsStatus=${remainingDays}
            [[ ${remainingDays} -le 0 ]] && tlsStatus="${Red}已过期${Font}"
            echo -e "\n${Green}证书生成日期: $(date -d "@${modifyTime}" +"%F %H:%M:%S")${Font}"
            echo -e "${Green}证书生成天数: ${days}${Font}"
            echo -e "${Green}证书剩余天数: ${tlsStatus}${Font}\n"
            if [[ ${remainingDays} -le 0 ]]; then
                echo -e "\n${Warning} ${YellowBG} 是否立即更新证书 [Y/${Red}N${Font}${YellowBG}]? ${Font}"
                read -r cert_update_manuel_fq
                case $cert_update_manuel_fq in
                [yY][eE][sS] | [yY])
                    systemctl stop xray
                    judge "Xray 停止"
                    cert_update_manuel
                    ;;
                *) ;;
                esac
            fi
        else
            echo -e "${Error} ${RedBG} 证书签发工具不存在, 请确认是否证书为脚本签发! ${Font}"
        fi
    else
        echo -e "${Error} ${RedBG} 当前模式不支持此操作! ${Font}"
    fi
}

cert_update_manuel() {
    if [[ ${tls_mode} == "TLS" ]]; then
        if [[ -f "${amce_sh_file}" ]]; then
            "/root/.acme.sh"/acme.sh --cron --home "/root/.acme.sh"
        else
            echo -e "${Error} ${RedBG} 证书签发工具不存在, 请确认是否证书为脚本签发! ${Font}"
        fi
        host="$(info_extraction host)"
        "$HOME"/.acme.sh/acme.sh --installcert -d "${host}" --fullchainpath ${ssl_chainpath}/xray.crt --keypath ${ssl_chainpath}/xray.key --ecc
        judge "证书更新"
        service_restart
    else
        echo -e "${Error} ${RedBG} 当前模式不支持此操作! ${Font}"
    fi
}

set_fail2ban() {
    mf_remote_url="https://raw.githubusercontent.com/hello-yunshu/Xray_bash_onekey/main/fail2ban_manager.sh"
    if [ ! -f "${idleleo_dir}/fail2ban_manager.sh" ]; then
        echo -e "${Info} ${Green} 本地文件 fail2ban_manager.sh 不存在，正在下载... ${Font}"
        curl -sL "$mf_remote_url" -o "${idleleo_dir}/fail2ban_manager.sh"
        if [ $? -ne 0 ]; then
            echo -e "${Error} ${RedBG} 下载失败，请手动下载并安装新版本 ${Font}"
            return 1
        fi
        chmod +x "${idleleo_dir}/fail2ban_manager.sh"
    fi
    source "${idleleo_dir}/fail2ban_manager.sh"
}

clean_logs() {
    local cron_file logrotate_config
    echo -e "\n${Green} 检测到日志文件大小如下: ${Font}"
    echo -e "${Green}$(du -sh /var/log/xray ${nginx_dir}/logs)${Font}"
    timeout "即将清除!"
    for i in $(find /var/log/xray/ ${nginx_dir}/logs -name "*.log"); do cat /dev/null >"$i"; done
    judge "日志清理"
    
    #以下为兼容代码，1个大版本后未来删除
    if [[ "${ID}" == "centos" ]]; then
        cron_file="/var/spool/cron/root"
    else
        cron_file="/var/spool/cron/crontabs/root"
    fi

    if [[ $(grep -c "find /var/log/xray/ /etc/nginx/logs -name" "$cron_file") -ne '0' ]]; then
        echo -e "${Warning} ${YellowBG} 已设置旧版自动清理日志任务 ${Font}"
        echo -e "${GreenBG} 是否需要删除旧版自动清理日志任务 [${Red}Y${Font}${GreenBG}/N]? ${Font}"
        read -r delete_task
        case $delete_task in
        [nN][oO] | [nN])
            echo -e "${OK} ${Green} 保留现有自动清理日志任务 ${Font}"
            return
            ;;
        *)
            sed -i "/find \/var\/log\/xray\/ \/etc\/nginx\/logs -name/d" "$cron_file"
            judge "删除旧版自动清理日志任务"
            ;;
        esac
    fi
    #兼容代码结束

    echo -e "\n${GreenBG} 是否需要设置自动清理日志 [${Red}Y${Font}${GreenBG}/N]? ${Font}"
    read -r auto_clean_logs_fq
    case $auto_clean_logs_fq in
    [nN][oO] | [nN])
        timeout "清空屏幕!"
        clear
        ;;
    *)
        echo -e "${OK} ${Green} 将在 每周三 04:00 自动清空日志 ${Font}"

        # Set up logrotate configuration
        logrotate_config="/etc/logrotate.d/custom_log_cleanup"

        if [[ -f "$logrotate_config" ]]; then
            echo -e "${Warning} ${YellowBG} 已设置自动清理日志任务 ${Font}"
            echo -e "${GreenBG} 是否需要删除现有自动清理日志任务 [Y/${Red}N${Font}${GreenBG}]? ${Font}"
            read -r delete_task
            case $delete_task in
            [yY][eE][sS] | [yY])
                rm -f "$logrotate_config"
                judge "删除自动清理日志任务"
                ;;
            *)
                echo -e "${OK} ${Green} 保留现有自动清理日志任务 ${Font}"
                return
                ;;
            esac
        fi

        # Create new logrotate configuration file
        echo "/var/log/xray/*.log ${nginx_dir}/logs/*.log {" > "$logrotate_config"
        echo "    weekly" >> "$logrotate_config"
        echo "    rotate 3" >> "$logrotate_config"
        echo "    compress" >> "$logrotate_config"
        echo "    missingok" >> "$logrotate_config"
        echo "    notifempty" >> "$logrotate_config"
        echo "    create 640 root adm" >> "$logrotate_config"
        echo "}" >> "$logrotate_config"
        
        judge "设置自动清理日志"
        ;;
    esac
}

vless_qr_config_tls_ws() {
    cat >${xray_qr_config_file} <<-EOF
{
    "shell_mode": "${shell_mode}",
    "ws_grpc_mode": "${ws_grpc_mode}",
    "host": "${domain}",
    "ip_version": "${ip_version}",
    "port": "${port}",
    "ws_port": "${artxport}",
    "grpc_port": "${artgport}",
    "tls": "TLS",
    "email": "${custom_email}",
    "idc": "${UUID5_char}",
    "id": "${UUID}",
    "net": "ws/gRPC",
    "path": "${artpath}",
    "serviceName": "${artserviceName}",
    "shell_version": "${shell_version}",
    "xray_version": "${xray_version}",
    "nginx_build_version": "${nginx_build_version}"
}
EOF
    info_extraction_all=$(jq -rc . ${xray_qr_config_file})
}

vless_qr_config_reality() {
    cat >${xray_qr_config_file} <<-EOF
{
    "shell_mode": "${shell_mode}",
    "ws_grpc_mode": "${ws_grpc_mode}",
    "host": "${local_ip}",
    "ip_version": "${ip_version}",
    "port": "${port}",
    "email": "${custom_email}",
    "idc": "${UUID5_char}",
    "id": "${UUID}",
    "net": "raw",
    "tls": "Reality",
    "target": "${target}",
    "serverNames":"${serverNames}",
    "privateKey":"${privateKey}",
    "publicKey":"${publicKey}",
    "shortIds":"${shortIds}",
    "reality_add_nginx": "${reality_add_nginx}",
    "reality_add_more": "${reality_add_more}",
    "ws_port": "${artxport}",
    "grpc_port": "${artgport}",
    "ws_path": "${artpath}",
    "grpc_serviceName": "${artserviceName}",
    "shell_version": "${shell_version}",
    "xray_version": "${xray_version}"
}
EOF
    if [[ ${reality_add_nginx} != "off" ]]; then
        jq ". + {\"nginx_build_version\": \"${nginx_build_version}\"}" "${xray_qr_config_file}" > "${xray_qr_config_file}.tmp"
        mv "${xray_qr_config_file}.tmp" "${xray_qr_config_file}"
    fi
    info_extraction_all=$(jq -rc . ${xray_qr_config_file})
}

vless_qr_config_ws_only() {
    cat >${xray_qr_config_file} <<-EOF
{
    "shell_mode": "${shell_mode}",
    "ws_grpc_mode": "${ws_grpc_mode}",
    "host": "${local_ip}",
    "ip_version": "${ip_version}",
    "ws_port": "${artxport}",
    "grpc_port": "${artgport}",
    "tls": "None",
    "email": "${custom_email}",
    "idc": "${UUID5_char}",
    "id": "${UUID}",
    "net": "ws/gRPC",
    "path": "${artpath}",
    "serviceName": "${artserviceName}",
    "shell_version": "${shell_version}",
    "xray_version": "${xray_version}"
}
EOF
    info_extraction_all=$(jq -rc . ${xray_qr_config_file})
}

vless_urlquote() {
    [[ $# = 0 ]] && return 1
    echo "import urllib.request;print(urllib.request.quote('$1'));" | python3
}

vless_qr_link_image() {
    if [[ ${tls_mode} == "TLS" ]]; then
        if [[ ${ws_grpc_mode} == "onlyws" ]]; then
            vless_ws_link="vless://$(info_extraction id)@$(vless_urlquote $(info_extraction host)):$(info_extraction port)?path=%2f$(vless_urlquote $(info_extraction path))%3Fed%3D2048&security=tls&encryption=none&host=$(vless_urlquote $(info_extraction host))&type=ws#$(vless_urlquote $(info_extraction host))+ws%E5%8D%8F%E8%AE%AE"
        elif [[ ${ws_grpc_mode} == "onlygRPC" ]]; then
            vless_grpc_link="vless://$(info_extraction id)@$(vless_urlquote $(info_extraction host)):$(info_extraction port)?serviceName=$(vless_urlquote $(info_extraction serviceName))&security=tls&encryption=none&host=$(vless_urlquote $(info_extraction host))&type=grpc#$(vless_urlquote $(info_extraction host))+gRPC%E5%8D%8F%E8%AE%AE"
        elif [[ ${ws_grpc_mode} == "all" ]]; then
            vless_ws_link="vless://$(info_extraction id)@$(vless_urlquote $(info_extraction host)):$(info_extraction port)?path=%2f$(vless_urlquote $(info_extraction path))%3Fed%3D2048&security=tls&encryption=none&host=$(vless_urlquote $(info_extraction host))&type=ws#$(vless_urlquote $(info_extraction host))+ws%E5%8D%8F%E8%AE%AE"
            vless_grpc_link="vless://$(info_extraction id)@$(vless_urlquote $(info_extraction host)):$(info_extraction port)?serviceName=$(vless_urlquote $(info_extraction serviceName))&security=tls&encryption=none&host=$(vless_urlquote $(info_extraction host))&type=grpc#$(vless_urlquote $(info_extraction host))+gRPC%E5%8D%8F%E8%AE%AE"
        fi
    elif [[ ${tls_mode} == "Reality" ]]; then
        vless_link="vless://$(info_extraction id)@$(vless_urlquote $(info_extraction host)):$(info_extraction port)?security=reality&flow=xtls-rprx-vision&fp=chrome&pbk=$(info_extraction publicKey)&sni=$(info_extraction serverNames)&target=$(info_extraction target)&sid=$(info_extraction shortIds)#$(vless_urlquote $(info_extraction host))+Reality%E5%8D%8F%E8%AE%AE"
        if [[ ${ws_grpc_mode} == "onlyws" ]]; then
            vless_ws_link="vless://$(info_extraction id)@$(vless_urlquote $(info_extraction host)):$(info_extraction ws_port)?path=%2f$(vless_urlquote $(info_extraction path))%3Fed%3D2048&encryption=none&type=ws#$(vless_urlquote $(info_extraction host))+%E5%8D%95%E7%8B%ACws%E5%8D%8F%E8%AE%AE"
        elif [[ ${ws_grpc_mode} == "onlygRPC" ]]; then
            vless_grpc_link="vless://$(info_extraction id)@$(vless_urlquote $(info_extraction host)):$(info_extraction grpc_port)?serviceName=$(vless_urlquote $(info_extraction serviceName))&encryption=none&type=grpc#$(vless_urlquote $(info_extraction host))+%E5%8D%95%E7%8B%ACgrpc%E5%8D%8F%E8%AE%AE"
        elif [[ ${ws_grpc_mode} == "all" ]]; then
            vless_ws_link="vless://$(info_extraction id)@$(vless_urlquote $(info_extraction host)):$(info_extraction ws_port)?path=%2f$(vless_urlquote $(info_extraction path))%3Fed%3D2048&encryption=none&type=ws#$(vless_urlquote $(info_extraction host))+%E5%8D%95%E7%8B%ACws%E5%8D%8F%E8%AE%AE"
            vless_grpc_link="vless://$(info_extraction id)@$(vless_urlquote $(info_extraction host)):$(info_extraction grpc_port)?serviceName=$(vless_urlquote $(info_extraction serviceName))&encryption=none&type=grpc#$(vless_urlquote $(info_extraction host))+%E5%8D%95%E7%8B%ACgrpc%E5%8D%8F%E8%AE%AE"
        fi
    elif [[ ${tls_mode} == "None" ]]; then
        if [[ ${ws_grpc_mode} == "onlyws" ]]; then
            vless_ws_link="vless://$(info_extraction id)@$(vless_urlquote $(info_extraction host)):$(info_extraction ws_port)?path=%2f$(vless_urlquote $(info_extraction path))%3Fed%3D2048&encryption=none&type=ws#$(vless_urlquote $(info_extraction host))+%E5%8D%95%E7%8B%ACws%E5%8D%8F%E8%AE%AE"
        elif [[ ${ws_grpc_mode} == "onlygRPC" ]]; then
            vless_grpc_link="vless://$(info_extraction id)@$(vless_urlquote $(info_extraction host)):$(info_extraction grpc_port)?serviceName=$(vless_urlquote $(info_extraction serviceName))&encryption=none&type=grpc#$(vless_urlquote $(info_extraction host))+%E5%8D%95%E7%8B%ACgrpc%E5%8D%8F%E8%AE%AE"
        elif [[ ${ws_grpc_mode} == "all" ]]; then
            vless_ws_link="vless://$(info_extraction id)@$(vless_urlquote $(info_extraction host)):$(info_extraction ws_port)?path=%2f$(vless_urlquote $(info_extraction path))%3Fed%3D2048&encryption=none&type=ws#$(vless_urlquote $(info_extraction host))+%E5%8D%95%E7%8B%ACws%E5%8D%8F%E8%AE%AE"
            vless_grpc_link="vless://$(info_extraction id)@$(vless_urlquote $(info_extraction host)):$(info_extraction grpc_port)?serviceName=$(vless_urlquote $(info_extraction serviceName))&encryption=none&type=grpc#$(vless_urlquote $(info_extraction host))+%E5%8D%95%E7%8B%ACgrpc%E5%8D%8F%E8%AE%AE"
        fi
    fi
    {
        echo -e "\n${Red} —————————————— Xray 配置分享 —————————————— ${Font}"
        if [[ ${tls_mode} == "Reality" ]]; then
            echo -e "${Red} URL 分享链接:${Font} ${vless_link}"
            echo -e "$Red 二维码: $Font"
            echo -n "${vless_link}" | qrencode -o - -t utf8
            echo -e "\n"
        fi
        if [[ ${ws_grpc_mode} == "onlyws" ]]; then
            echo -e "${Red} ws URL 分享链接:${Font} ${vless_ws_link}"
            echo -e "$Red 二维码: $Font"
            echo -n "${vless_ws_link}" | qrencode -o - -t utf8
            echo -e "\n"
        elif [[ ${ws_grpc_mode} == "onlygRPC" ]]; then
            echo -e "${Red} gRPC URL 分享链接:${Font} ${vless_grpc_link}"
            echo -e "$Red 二维码: $Font"
            echo -n "${vless_grpc_link}" | qrencode -o - -t utf8
            echo -e "\n"
        elif [[ ${ws_grpc_mode} == "all" ]]; then
            echo -e "${Red} ws URL 分享链接:${Font} ${vless_ws_link}"
            echo -e "$Red 二维码: $Font"
            echo -n "${vless_ws_link}" | qrencode -o - -t utf8
            echo -e "\n"
            echo -e "${Red} gRPC URL 分享链接:${Font} ${vless_grpc_link}"
            echo -e "$Red 二维码: $Font"
            echo -n "${vless_grpc_link}" | qrencode -o - -t utf8
            echo -e "\n"
        fi
    } >>"${xray_info_file}"
}

vless_link_image_choice() {
    echo -e "\n${GreenBG} 请选择生成的分享链接种类: ${Font}"
    echo "1: V2RayN/V2RayNG/Qv2ray"
    read -rp "请输入: " link_version
    [[ -z ${link_version} ]] && link_version=1
    if [[ $link_version == 1 ]]; then
        vless_qr_link_image
    else
        vless_qr_link_image
    fi
}

info_extraction() {
    echo ${info_extraction_all} | jq -r ".$1"
    [[ 0 -ne $? ]] && read_config_status=0
}

basic_information() {
    {
        echo -e "\n"
        case ${shell_mode} in
        Nginx+ws+TLS)
            echo -e "${OK} ${GreenBG} Xray+Nginx+ws+TLS 安装成功 ${Font}"
            ;;
        Nginx+gRPC+TLS)
            echo -e "${OK} ${GreenBG} Xray+Nginx+grpc+TLS 安装成功 ${Font}"
            ;;
        Nginx+ws+gRPC+TLS)
            echo -e "${OK} ${GreenBG} Xray+Nginx+ws+gRPC+TLS 安装成功 ${Font}"
            ;;
        Reality)
            echo -e "${OK} ${GreenBG} Xray+Reality 安装成功 ${Font}"
            ;;
        Reality+ws)
            echo -e "${OK} ${GreenBG} Xray+Reality+ws 安装成功 ${Font}"
            ;;
        Reality+gRPC)
            echo -e "${OK} ${GreenBG} Xray+Reality+gRPC 安装成功 ${Font}"
            ;;
        Reality+ws+gRPC)
            echo -e "${OK} ${GreenBG} Xray+Reality+ws+gRPC 安装成功 ${Font}"
            ;;
        ws?ONLY)
            echo -e "${OK} ${GreenBG} ws ONLY 安装成功 ${Font}"
            ;;
        gRPC?ONLY)
            echo -e "${OK} ${GreenBG} gRPC ONLY 安装成功 ${Font}"
            ;;
        ws+gRPC?ONLY)
            echo -e "${OK} ${GreenBG} ws+gRPC ONLY 安装成功 ${Font}"
            ;;
        esac
        echo -e "\n${Warning} ${YellowBG} VLESS 目前分享链接规范为实验阶段, 请自行判断是否适用 ${Font}"
        echo -e "\n${Red} —————————————— Xray 配置信息 —————————————— ${Font}"
        echo -e "${Red} 主机 (host):${Font} $(info_extraction host) "
        if [[ ${tls_mode} == "None" ]]; then
            if [[ ${ws_grpc_mode} == "onlyws" ]]; then
                echo -e "${Red} ws 端口 (port):${Font} $(info_extraction ws_port) "
            elif [[ ${ws_grpc_mode} == "onlygRPC" ]]; then
                echo -e "${Red} gRPC 端口 (port):${Font} $(info_extraction grpc_port) "
            elif [[ ${ws_grpc_mode} == "all" ]]; then
                echo -e "${Red} ws 端口 (port):${Font} $(info_extraction ws_port) "
                echo -e "${Red} gRPC 端口 (port):${Font} $(info_extraction grpc_port) "
            fi
        else
            echo -e "${Red} 端口 (port):${Font} $(info_extraction port) "
        fi
        if [[ ${tls_mode} == "TLS" ]]; then
            if [[ ${ws_grpc_mode} == "onlyws" ]]; then
                echo -e "${Red} Xray ws 端口 (inbound_port):${Font} $(info_extraction ws_port) "
            elif [[ ${ws_grpc_mode} == "onlygRPC" ]]; then
                echo -e "${Red} Xray gRPC 端口 (inbound_port):${Font} $(info_extraction grpc_port) "
            elif [[ ${ws_grpc_mode} == "all" ]]; then
                echo -e "${Red} Xray ws 端口 (inbound_port):${Font} $(info_extraction ws_port) "
                echo -e "${Red} Xray gRPC 端口 (inbound_port):${Font} $(info_extraction grpc_port) "
            fi
        fi
        echo -e "${Red} UUIDv5 映射字符串:${Font} $(info_extraction idc)"
        echo -e "${Red} 用户id (UUID):${Font} $(info_extraction id)"

        echo -e "${Red} 加密 (encryption):${Font} None "
        echo -e "${Red} 传输协议 (network):${Font} $(info_extraction net) "
        echo -e "${Red} 底层传输安全 (tls):${Font} $(info_extraction tls) "  
        if [[ ${tls_mode} != "Reality" ]]; then
            if [[ ${ws_grpc_mode} == "onlyws" ]]; then
                echo -e "${Red} 路径 (path 不要落下/):${Font} /$(info_extraction path) "
            elif [[ ${ws_grpc_mode} == "onlygRPC" ]]; then
                echo -e "${Red} serviceName (不需要加/):${Font} $(info_extraction serviceName) "
            elif [[ ${ws_grpc_mode} == "all" ]]; then
                echo -e "${Red} 路径 (path 不要落下/):${Font} /$(info_extraction path) "
                echo -e "${Red} serviceName (不需要加/):${Font} $(info_extraction serviceName) "
            fi
        else
            echo -e "${Red} 流控 (flow):${Font} xtls-rprx-vision "
            echo -e "${Red} target:${Font} $(info_extraction target) "
            echo -e "${Red} serverNames:${Font} $(info_extraction serverNames) "
            echo -e "${Red} privateKey:${Font} $(info_extraction privateKey) "
            echo -e "${Red} publicKey:${Font} $(info_extraction publicKey) "
            echo -e "${Red} shortIds:${Font} $(info_extraction shortIds) "
            if [[ "$reality_add_more" == "on" ]]; then
                if [[ ${ws_grpc_mode} == "onlyws" ]]; then
                    echo -e "${Red} ws 端口 (port):${Font} $(info_extraction ws_port) "
                    echo -e "${Red} ws 路径 (不要落下/):${Font} /$(info_extraction ws_path) "
                elif [[ ${ws_grpc_mode} == "onlygRPC" ]]; then
                    echo -e "${Red} gRPC 端口 (port):${Font} $(info_extraction grpc_port) "
                    echo -e "${Red} gRPC serviceName (不需要加/):${Font} $(info_extraction grpc_serviceName) "
                elif [[ ${ws_grpc_mode} == "all" ]]; then
                    echo -e "${Red} ws 端口 (port):${Font} $(info_extraction ws_port) "
                    echo -e "${Red} ws 路径 (不要落下/):${Font} /$(info_extraction ws_path) "
                    echo -e "${Red} gRPC 端口 (port):${Font} $(info_extraction grpc_port) "
                    echo -e "${Red} gRPC serviceName (不需要加/):${Font} $(info_extraction grpc_serviceName) "
                fi
            fi
        fi
    } >"${xray_info_file}"
}

show_information() {
    cat "${xray_info_file}"
}

ssl_judge_and_install() {
    cd $HOME
    echo -e "\n${GreenBG} 即将申请证书, 支持使用自定义证书 ${Font}"
    echo -e "${Green} 如需使用自定义证书, 请按如下步骤:  ${Font}"
    echo -e " 1. 将证书文件重命名: 私钥(xray.key)、证书(xray.crt)"
    echo -e " 2. 将重命名后的证书文件放入 ${ssl_chainpath} 目录后再运行脚本"
    echo -e " 3. 重新运行脚本"
    echo -e "${GreenBG} 是否继续 [${Red}Y${Font}${GreenBG}/N]? ${Font}"
    read -r ssl_continue
    case $ssl_continue in
    [nN][oO] | [nN])
        exit 0
        ;;
    *)
        [[ $(grep "nogroup" /etc/group) ]] && cert_group="nogroup"
        if [[ -f "${ssl_chainpath}/xray.key" && -f "${ssl_chainpath}/xray.crt" ]] && [[ -f "$HOME/.acme.sh/${domain}_ecc/${domain}.key" && -f "$HOME/.acme.sh/${domain}_ecc/${domain}.cer" ]]; then
            echo -e "${GreenBG} 所有证书文件均已存在, 是否保留 [${Red}Y${Font}${GreenBG}/N]? ${Font}"
            read -r ssl_delete_1
            case $ssl_delete_1 in
            [nN][oO] | [nN])
                delete_tls_key_and_crt
                rm -rf ${ssl_chainpath}/*
                echo -e "${OK} ${GreenBG} 已删除 ${Font}"
                ssl_install
                acme
                ;;
            *)
                chown -fR nobody:${cert_group} ${ssl_chainpath}/*
                judge "证书应用"
                ;;
            esac
        elif [[ -f "${ssl_chainpath}/xray.key" || -f "${ssl_chainpath}/xray.crt" ]] && [[ ! -f "$HOME/.acme.sh/${domain}_ecc/${domain}.key" && ! -f "$HOME/.acme.sh/${domain}_ecc/${domain}.cer" ]]; then
            echo -e "${GreenBG} 证书文件已存在, 是否保留 [${Red}Y${Font}${GreenBG}/N]? ${Font}"
            read -r ssl_delete_2
            case $ssl_delete_2 in
            [nN][oO] | [nN])
                rm -rf ${ssl_chainpath}/*
                echo -e "${OK} ${GreenBG} 已删除 ${Font}"
                ssl_install
                acme
                ;;
            *)
                chown -fR nobody:${cert_group} ${ssl_chainpath}/*
                judge "证书应用"
                ssl_self="on"
                ;;
            esac
        elif [[ -f "$HOME/.acme.sh/${domain}_ecc/${domain}.key" && -f "$HOME/.acme.sh/${domain}_ecc/${domain}.cer" ]] && [[ ! -f "${ssl_chainpath}/xray.key" || ! -f "${ssl_chainpath}/xray.crt" ]]; then
            echo -e "${GreenBG} 证书签发残留文件已存在, 是否保留 [${Red}Y${Font}${GreenBG}/N]? ${Font}"
            read -r ssl_delete_3
            case $ssl_delete_3 in
            [nN][oO] | [nN])
                delete_tls_key_and_crt
                echo -e "${OK} ${GreenBG} 已删除 ${Font}"
                ssl_install
                acme
                ;;
            *)
                "$HOME"/.acme.sh/acme.sh --installcert -d "${domain}" --fullchainpath ${ssl_chainpath}/xray.crt --keypath ${ssl_chainpath}/xray.key --ecc
                chown -fR nobody:${cert_group} ${ssl_chainpath}/*
                judge "证书应用"
                ;;
            esac
        else
            ssl_install
            acme
        fi
        ;;
    esac
}

nginx_systemd() {
    cat >${nginx_systemd_file} <<EOF
[Unit]
Description=The NGINX HTTP and reverse proxy server
After=syslog.target network.target remote-fs.target nss-lookup.target

[Service]
Type=forking
PIDFile=${nginx_dir}/logs/nginx.pid
ExecStartPre=${nginx_dir}/sbin/nginx -t
ExecStart=${nginx_dir}/sbin/nginx -c ${nginx_dir}/conf/nginx.conf
ExecReload=${nginx_dir}/sbin/nginx -s reload
ExecStop=/bin/kill -s QUIT \$MAINPID
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

    judge "Nginx systemd ServerFile 添加"
    systemctl daemon-reload
}

tls_type() {
    if [[ -f "${nginx_conf}" ]] && [[ ${tls_mode} == "TLS" ]]; then
        echo -e "\n${GreenBG} 请选择支持的 TLS 版本 (default:2): ${Font}"
        echo -e "${GreenBG} 建议选择 TLS1.3 only (安全模式) ${Font}"
        echo -e "1: TLS1.2 and TLS1.3 (兼容模式)"
        echo -e "${Red}2${Font}: TLS1.3 only (安全模式)"
        read -rp "请输入: " tls_version
        [[ -z ${tls_version} ]] && tls_version=2
        if [[ $tls_version == 1 ]]; then
            # if [[ ${tls_mode} == "TLS" ]]; then
            #     sed -i "s/^\( *\)ssl_protocols\( *\).*/\1ssl_protocols\2TLSv1.2 TLSv1.3;/" $nginx_conf
            # else
            #     echo -e "${Error} ${RedBG} Reality 用且仅用 TLS1.3, 请选择 TLS1.3 only (安全模式)! ${Font}"
            #     tls_type
            # fi
            sed -i "s/^\( *\)ssl_protocols\( *\).*/\1ssl_protocols\2TLSv1.2 TLSv1.3;/" $nginx_conf
            echo -e "${OK} ${GreenBG} 已切换至 TLS1.2 and TLS1.3 ${Font}"
        else
            # if [[ ${tls_mode} == "TLS" ]]; then
            #     sed -i "s/^\( *\)ssl_protocols\( *\).*/\1ssl_protocols\2TLSv1.3;/" $nginx_conf
            # ## else
            #     ##sed -i "s/^\( *\)\"minVersion\".*/\1\"minVersion\": \"1.3\",/" ${xray_conf}
            # fi
            sed -i "s/^\( *\)ssl_protocols\( *\).*/\1ssl_protocols\2TLSv1.3;/" $nginx_conf
            echo -e "${OK} ${GreenBG} 已切换至 TLS1.3 only ${Font}"
        fi
        # if [[ ${tls_mode} == "TLS" ]]; then
        [[ -f "${nginx_systemd_file}" ]] && systemctl restart nginx && judge "Nginx 重启"
        # elif [[ ${tls_mode} == "Reality" ]]; then
        systemctl restart xray
        judge "Xray 重启"
        # fi
    else
        echo -e "${Error} ${RedBG} Nginx 或 配置文件不存在 或当前安装版本为 ws ONLY , 请正确安装脚本后执行${Font}"
    fi
}

revision_port() {
    if [[ ${tls_mode} == "TLS" ]]; then
        read_optimize "请输入连接端口 (默认值:443):" "port" 443 0 65535 "请输入 0-65535 之间的值!"
        modify_nginx_port
        [[ -f "${xray_qr_config_file}" ]] && sed -i "s/^\( *\)\"port\".*/\1\"port\": \"${port}\",/" ${xray_qr_config_file}
        echo -e "${Green} 连接端口号: ${port} ${Font}"
    elif [[ ${tls_mode} == "Reality" ]]; then
        read_optimize "请输入连接端口 (默认值:443):" "port" 443 0 65535 "请输入 0-65535 之间的值!"
        xport=$((RANDOM % 1000 + 20000))
        gport=$((RANDOM % 1000 + 30000))
        if [[ ${ws_grpc_mode} == "onlyws" ]]; then
            read_optimize "请输入 ws inbound_port:" "xport" "NULL" 0 65535 "请输入 0-65535 之间的值!"
            port_exist_check "${xport}"
            gport=$((RANDOM % 1000 + 30000))
            [[ -f "${xray_qr_config_file}" ]] && sed -i "s/^\( *\)\"ws_port\".*/\1\"ws_port\": \"${xport}\",/" ${xray_qr_config_file}
            echo -e "${Green} ws inbound_port: ${xport} ${Font}"
        elif [[ ${ws_grpc_mode} == "onlygrpc" ]]; then
            read_optimize "请输入 gRPC inbound_port:" "gport" "NULL" 0 65535 "请输入 0-65535 之间的值!"
            port_exist_check "${gport}"
            xport=$((RANDOM % 1000 + 20000))
            [[ -f "${xray_qr_config_file}" ]] && sed -i "s/^\( *\)\"grpc_port\".*/\1\"grpc_port\": \"${gport}\",/" ${xray_qr_config_file}
            echo -e "${Green} gRPC inbound_port: ${gport} ${Font}"
        elif [[ ${ws_grpc_mode} == "all" ]]; then
            read_optimize "请输入 ws inbound_port:" "xport" "NULL" 0 65535 "请输入 0-65535 之间的值!"
            read_optimize "请输入 gRPC inbound_port:" "gport" "NULL" 0 65535 "请输入 0-65535 之间的值!"
            port_exist_check "${xport}"
            port_exist_check "${gport}"
            [[ -f "${xray_qr_config_file}" ]] && sed -i "s/^\( *\)\"ws_port\".*/\1\"ws_port\": \"${xport}\",/" ${xray_qr_config_file}
            [[ -f "${xray_qr_config_file}" ]] && sed -i "s/^\( *\)\"grpc_port\".*/\1\"grpc_port\": \"${gport}\",/" ${xray_qr_config_file}
            echo -e "${Green} ws inbound_port: ${xport} ${Font}"
            echo -e "${Green} gRPC inbound_port: ${gport} ${Font}"
        fi
        modify_inbound_port
    elif [[ ${tls_mode} == "None" ]]; then
        if [[ ${ws_grpc_mode} == "onlyws" ]]; then
            read_optimize "请输入 ws inbound_port:" "xport" "NULL" 0 65535 "请输入 0-65535 之间的值!"
            port_exist_check "${xport}"
            gport=$((RANDOM % 1000 + 30000))
            echo -e "${Green} ws inbound_port: ${xport} ${Font}"
        elif [[ ${ws_grpc_mode} == "onlygrpc" ]]; then
            read_optimize "请输入 gRPC inbound_port:" "gport" "NULL" 0 65535 "请输入 0-65535 之间的值!"
            port_exist_check "${gport}"
            xport=$((RANDOM % 1000 + 20000))
            echo -e "${Green} gRPC inbound_port: ${gport} ${Font}"
        elif [[ ${ws_grpc_mode} == "all" ]]; then
            read_optimize "请输入 ws inbound_port:" "xport" "NULL" 0 65535 "请输入 0-65535 之间的值!"
            read_optimize "请输入 gRPC inbound_port:" "gport" "NULL" 0 65535 "请输入 0-65535 之间的值!"
            port_exist_check "${xport}"
            port_exist_check "${gport}"
            echo -e "${Green} ws inbound_port: ${xport} ${Font}"
            echo -e "${Green} gRPC inbound_port: ${gport} ${Font}"
        fi
        [[ -f "${xray_qr_config_file}" ]] && sed -i "s/^\( *\)\"ws_port\".*/\1\"ws_port\": \"${xport}\",/" ${xray_qr_config_file}
        [[ -f "${xray_qr_config_file}" ]] && sed -i "s/^\( *\)\"grpc_port\".*/\1\"grpc_port\": \"${gport}\",/" ${xray_qr_config_file}
        modify_inbound_port
    fi
}

show_user() {
    if [[ -f "${xray_qr_config_file}" ]] && [[ -f "${xray_conf}" ]] && [[ ${tls_mode} != "None" ]]; then
        echo -e "\n${GreenBG} 即将显示用户, 一次仅能显示一个 ${Font}"
        if [[ ${tls_mode} == "TLS" ]]; then
            echo -e "${GreenBG} 请选择 显示用户使用的协议 ws/gRPC ${Font}"
            echo -e "${Red}1${Font}: ws (默认)"
            echo "2: gRPC"
            read -rp "请输入: " choose_user_prot
            [[ -z ${choose_user_prot} ]] && choose_user_prot=1
            choose_user_prot=$((choose_user_prot - 1))
        elif [[ ${tls_mode} == "Reality" ]]; then
            choose_user_prot=0
        fi
        echo -e "\n${GreenBG} 请选择 要显示的用户编号: ${Font}"
        jq -r -c .inbounds[${choose_user_prot}].settings.clients[].email ${xray_conf} | awk '{print NR""": "$0}'
        read -rp "请输入: " show_user_index
        if [[ $(jq -r '.inbounds['${choose_user_prot}'].settings.clients|length' ${xray_conf}) -lt ${show_user_index} ]] || [[ ${show_user_index} == 0 ]]; then
            echo -e "${Error} ${RedBG} 选择错误! ${Font}"
            show_user
        elif [[ ${show_user_index} == 1 ]]; then
            echo -e "${Error} ${RedBG} 请直接在主菜单选择 [15] 显示主用户 ${Font}"
            timeout "回到菜单!"
            menu
        elif [[ ${show_user_index} -gt 1 ]]; then
            show_user_index=$((show_user_index - 1))
            user_email=$(jq -r -c '.inbounds['${choose_user_prot}'].settings.clients['${show_user_index}'].email' ${xray_conf})
            user_id=$(jq -r -c '.inbounds['${choose_user_prot}'].settings.clients['${show_user_index}'].id' ${xray_conf})
        elif [[ ! -z $(echo ${show_user_index} | sed 's/[0-9]//g') ]] || [[ ${show_user_index} == '' ]]; then
            echo -e "${Error} ${RedBG} 选择错误! ${Font}"
            show_user
        else
            echo -e "${Warning} ${YellowBG} 请先检测 Xray 是否正确安装! ${Font}"
            timeout "回到菜单!"
            menu
        fi
        if [[ ! -z ${user_email} ]] && [[ ! -z ${user_id} ]]; then
            echo -e "${Green} 用户名: ${user_email} ${Font}"
            echo -e "${Green} UUID: ${user_id} ${Font}"
            if [[ ${tls_mode} == "TLS" ]]; then
                if [[ ${choose_user_prot} == 0 ]]; then
                    user_vless_link="vless://${user_id}@$(vless_urlquote $(info_extraction host)):$(info_extraction port)?path=%2f$(vless_urlquote $(info_extraction path))%3Fed%3D2048&security=tls&encryption=none&host=$(vless_urlquote $(info_extraction host))&type=ws#$(vless_urlquote $(info_extraction host))+ws%E5%8D%8F%E8%AE%AE"
                elif [[ ${choose_user_prot} == 1 ]]; then
                    user_vless_link="vless://${user_id}@$(vless_urlquote $(info_extraction host)):$(info_extraction port)?serviceName=$(vless_urlquote $(info_extraction serviceName))&security=tls&encryption=none&host=$(vless_urlquote $(info_extraction host))&type=grpc#$(vless_urlquote $(info_extraction host))+gRPC%E5%8D%8F%E8%AE%AE"
                fi
            elif [[ ${tls_mode} == "Reality" ]]; then
                user_vless_link="vless://${user_id}@$(vless_urlquote $(info_extraction host)):$(info_extraction port)?security=tls&encryption=none&headerType=none&type=raw&flow=xtls-rprx-vision#$(vless_urlquote $(info_extraction host))+reality%E5%8D%8F%E8%AE%AE"
            fi
            echo -e "${Red} URL 分享链接:${Font} ${user_vless_link}"
            echo -n "${user_vless_link}" | qrencode -o - -t utf8
        fi
        echo -e "\n${GreenBG} 是否继续显示用户 [Y/${Red}N${Font}${GreenBG}]?  ${Font}"
        read -r show_user_continue
        case $show_user_continue in
        [yY][eE][sS] | [yY])
            show_user
            ;;
        *) ;;
        esac
    elif [[ ${tls_mode} == "None" ]]; then
        echo -e "${Warning} ${YellowBG} 此模式不支持删除用户! ${Font}"
    else
        echo -e "${Warning} ${YellowBG} 请先安装 Xray ! ${Font}"
    fi
}

add_user() {
    local choose_user_prot
    if [[ -f "${xray_qr_config_file}" ]] && [[ -f "${xray_conf}" ]] && [[ ${tls_mode} != "None" ]]; then
        service_stop
        echo -e "\n${GreenBG} 即将添加用户, 一次仅能添加一个 ${Font}"
        if [[ ${tls_mode} == "TLS" ]]; then
            echo -e "${GreenBG} 请选择 添加用户使用的协议 ws/gRPC ${Font}"
            echo -e "${Red}1${Font}: ws (默认)"
            echo "2: gRPC"
            read -rp "请输入: " choose_user_prot
            [[ -z ${choose_user_prot} ]] && choose_user_prot=1
            choose_user_prot=$((choose_user_prot - 1))
            local reality_user_more=""
        elif [[ ${tls_mode} == "Reality" ]]; then
            choose_user_prot=0
            reality_user_more="\"flow\":\"xtls-rprx-vision\","
        fi
        email_set
        UUID_set
        jq ".inbounds[${choose_user_prot}].settings.clients += [{\"id\": \"${UUID}\",\"${reality_user_more}\"level\": 0,\"email\": \"${custom_email}\"}]" ${xray_conf} > "${xray_conf}.tmp"
        judge "添加用户"
        mv "${xray_conf}.tmp" "${xray_conf}"
        jq ". += {\"multi_user\": \"yes\"}" ${xray_qr_config_file} > "${xray_qr_config_file}.tmp"
        mv "${xray_qr_config_file}.tmp" "${xray_qr_config_file}"
        echo -e "\n${GreenBG} 是否继续添加用户 [Y/${Red}N${Font}${GreenBG}]?  ${Font}"
        read -r add_user_continue
        case $add_user_continue in
        [yY][eE][sS] | [yY])
            add_user
            ;;
        *) ;;
        esac
        service_start
    elif [[ ${tls_mode} == "None" ]]; then
        echo -e "${Warning} ${YellowBG} 此模式不支持添加用户! ${Font}"
    else
        echo -e "${Warning} ${YellowBG} 请先安装 Xray ! ${Font}"
    fi
}

remove_user() {
    if [[ -f "${xray_qr_config_file}" ]] && [[ -f "${xray_conf}" ]] && [[ ${tls_mode} != "None" ]]; then
        service_stop
        echo -e "\n${GreenBG} 即将删除用户, 一次仅能删除一个 ${Font}"
        if [[ ${tls_mode} == "TLS" ]]; then
            echo -e "${GreenBG} 请选择 删除用户使用的协议 ws/gRPC ${Font}"
            echo -e "${Red}1${Font}: ws (默认)"
            echo "2: gRPC"
            read -rp "请输入: " choose_user_prot
            [[ -z ${choose_user_prot} ]] && choose_user_prot=1
            choose_user_prot=$((choose_user_prot - 1))
        elif [[ ${tls_mode} == "Reality" ]]; then
            choose_user_prot=0
        fi
        echo -e "\n${GreenBG} 请选择 要删除的用户编号 ${Font}"
        jq -r -c .inbounds[${choose_user_prot}].settings.clients[].email ${xray_conf} | awk '{print NR""": "$0}'
        read -rp "请输入: " del_user_index
        if [[ $(jq -r '.inbounds['${choose_user_prot}'].settings.clients|length' ${xray_conf}) -lt ${del_user_index} ]] || [[ ${show_user_index} == 0 ]]; then
            echo -e "${Error} ${RedBG} 选择错误! ${Font}"
            remove_user
        elif [[ ${del_user_index} == 1 ]]; then
            echo -e "\n${Error} ${RedBG} 请直接在主菜单修改主用户的 UUID/Email ! ${Font}"
            timeout "回到菜单!"
            menu
        elif [[ ${del_user_index} -gt 1 ]]; then
            del_user_index=$((del_user_index - 1))
            jq 'del(.inbounds['${choose_user_prot}'].settings.clients['${del_user_index}'])' ${xray_conf} > "${xray_conf}.tmp"
            judge "删除用户"
            mv "${xray_conf}.tmp" "${xray_conf}"
            echo -e "\n${GreenBG} 是否继续删除用户 [Y/${Red}N${Font}${GreenBG}]?  ${Font}"
            read -r remove_user_continue
            case $remove_user_continue in
            [yY][eE][sS] | [yY])
                remove_user
                ;;
            *) ;;
            esac
        elif [[ ! -z $(echo ${del_user_index} | sed 's/[0-9]//g') ]] || [[ ${del_user_index} == '' ]]; then
            echo -e "${Error} ${RedBG} 选择错误! ${Font}"
            remove_user
        else
            echo -e "${Warning} ${YellowBG} 请先检测 Xray 是否正确安装! ${Font}"
            timeout "回到菜单!"
            menu
        fi
        service_start
    elif [[ ${tls_mode} == "None" ]]; then
        echo -e "${Warning} ${YellowBG} 此模式不支持删除用户! ${Font}"
    else
        echo -e "${Warning} ${YellowBG} 请先安装 Xray ! ${Font}"
    fi
}

show_access_log() {
    [[ -f "${xray_access_log}" ]] && tail -f ${xray_access_log} || echo -e "${Error} ${RedBG} log文件不存在! ${Font}"
}

show_error_log() {
    [[ -f "${xray_error_log}" ]] && tail -f ${xray_error_log} || echo -e "${Error} ${RedBG} log文件不存在! ${Font}"
}

xray_status_add() {
    if [[ -f "${xray_conf}" ]]; then
        if [[ $(jq -r .stats ${xray_conf}) != null ]]; then
            echo -e "\n${GreenBG} 已配置 Xray 流量统计 ${Font}"
            echo -e "${GreenBG} 是否需要关闭此功能 [Y/${Red}N${Font}${GreenBG}]? ${Font}"
            read -r xray_status_add_fq
            case $xray_status_add_fq in
            [yY][eE][sS] | [yY])
                service_stop
                jq "del(.api)|del(.stats)|del(.policy)" ${xray_conf} > "${xray_conf}.tmp"
                judge "关闭 Xray 流量统计"
                mv "${xray_conf}.tmp" "${xray_conf}"
                service_start
                [[ -f "${xray_status_conf}" ]] && rm -rf ${xray_status_conf}
                ;;
            *) ;;
            esac
        else
            echo -e "\n${GreenBG} Xray 流量统计需要使用 api ${Font}"
            echo -e "${GreenBG} 可能会影响 Xray 性能 ${Font}"
            echo -e "${GreenBG} 是否继续 [Y/${Red}N${Font}${GreenBG}]? ${Font}"
            read -r xray_status_add_fq
            case $xray_status_add_fq in
            [yY][eE][sS] | [yY])
                    service_stop
                    wget -nc --no-check-certificate https://raw.githubusercontent.com/hello-yunshu/Xray_bash_onekey/main/status_config.json -O ${xray_status_conf}
                    jq ". += $(jq -c . ${xray_status_conf})" ${xray_conf} > "${xray_conf}.tmp"
                    judge "设置 Xray 流量统计"
                    mv "${xray_conf}.tmp" "${xray_conf}"
                    service_start
                ;;
            *) ;;
            esac
        fi
    else
        echo -e "${Warning} ${YellowBG} 请先安装 Xray ! ${Font}"
    fi
}

bbr_boost_sh() {
    if [[ -f "${idleleo_dir}/tcp.sh" ]]; then
        cd ${idleleo_dir} && chmod +x ./tcp.sh && ./tcp.sh
    else
        wget -N --no-check-certificate -P ${idleleo_dir} "https://raw.githubusercontent.com/ylx2016/Linux-NetSpeed/master/tcp.sh" && chmod +x ${idleleo_dir}/tcp.sh && ${idleleo_dir}/tcp.sh
    fi
}

mtproxy_sh() {
    wget -N --no-check-certificate "https://github.com/whunt1/onekeymakemtg/raw/master/mtproxy_go.sh" && chmod +x mtproxy_go.sh && bash mtproxy_go.sh
}

uninstall_all() {
    stop_service_all
    if [[ -f "${xray_bin_dir}/xray" ]]; then
        systemctl disable xray
        bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge
        [[ -d "${xray_conf_dir}" ]] && rm -rf ${xray_conf_dir}
        if [[ -f "${xray_qr_config_file}" ]]; then
            jq -r 'del(.xray_version)' ${xray_qr_config_file} > "${xray_qr_config_file}.tmp"
            mv "${xray_qr_config_file}.tmp" "${xray_qr_config_file}"
        fi
        echo -e "${OK} ${GreenBG} 已卸载 Xray ${Font}"
    fi
    if [[ -d "${nginx_dir}" ]]; then
        echo -e "${GreenBG} 是否卸载 Nginx [Y/${Red}N${Font}${GreenBG}]? ${Font}"
        read -r uninstall_nginx
        case $uninstall_nginx in
        [yY][eE][sS] | [yY])
            systemctl disable nginx
            rm -rf ${nginx_dir}
            rm -rf ${nginx_conf_dir}/*
            [[ -f "${nginx_systemd_file}" ]] && rm -rf ${nginx_systemd_file}
            if [[ -f "${xray_qr_config_file}" ]]; then
                jq 'del(.nginx_build_version)' ${xray_qr_config_file} > "${xray_qr_config_file}.tmp"
                mv "${xray_qr_config_file}.tmp" "${xray_qr_config_file}"
            fi
            echo -e "${OK} ${GreenBG} 已卸载 Nginx ${Font}"
            ;;
        *) ;;
        esac
    fi
    echo -e "${GreenBG} 是否删除所有脚本文件 [Y/${Red}N${Font}${GreenBG}]? ${Font}"
    read -r remove_all_idleleo_file_fq
    case $remove_all_idleleo_file_fq in
    [yY][eE][sS] | [yY])
        rm -rf ${idleleo_commend_file}
        rm -rf ${idleleo_dir}
        systemctl daemon-reload
        echo -e "${OK} ${GreenBG} 已删除所有文件 ${Font}"
        echo -e "${GreenBG} ヾ(￣▽￣) 拜拜~ ${Font}"
        exit 0
        ;;
    *)
        systemctl daemon-reload
        echo -e "${OK} ${GreenBG} 已保留脚本文件 (包含 SSL 证书等) ${Font}"
        ;;
    esac
    if [[ -f "${xray_qr_config_file}" ]]; then
        echo -e "${GreenBG} 是否保留配置文件 [Y/${Red}N${Font}${GreenBG}]? ${Font}"
        read -r remove_config_fq
        case $remove_config_fq in
        [yY][eE][sS] | [yY])
            echo -e "${OK} ${GreenBG} 已保留配置文件 ${Font}"
            ;;
        *)
            rm -rf ${xray_qr_config_file}
            echo -e "${OK} ${GreenBG} 已删除配置文件 ${Font}"
            ;;
        esac
    fi
}

delete_tls_key_and_crt() {
    [[ -f "$HOME/.acme.sh/acme.sh" ]] && /root/.acme.sh/acme.sh uninstall >/dev/null 2>&1
    [[ -d "$HOME/.acme.sh" ]] && rm -rf "$HOME/.acme.sh"
    echo -e "${OK} ${GreenBG} 已清空证书遗留文件 ${Font}"
}

timeout() {
    timeout=0
    timeout_str=""
    while [[ ${timeout} -le 30 ]]; do
        let timeout++
        timeout_str+="#"
    done
    let timeout=timeout+5
    while [[ ${timeout} -gt 0 ]]; do
        let timeout--
        if [[ ${timeout} -gt 25 ]]; then
            let timeout_color=32
            let timeout_bg=42
            timeout_index="3"
        elif [[ ${timeout} -gt 15 ]]; then
            let timeout_color=33
            let timeout_bg=43
            timeout_index="2"
        elif [[ ${timeout} -gt 5 ]]; then
            let timeout_color=31
            let timeout_bg=41
            timeout_index="1"
        else
            timeout_index="0"
        fi
        printf "${Warning} ${GreenBG} %d秒后将$1 ${Font} \033[${timeout_color};${timeout_bg}m%-s\033[0m \033[${timeout_color}m%d\033[0m \r" "$timeout_index" "$timeout_str" "$timeout_index"
        sleep 0.1
        timeout_str=${timeout_str%?}
        [[ ${timeout} -eq 0 ]] && printf "\n"
    done
}

judge_mode() {
    if [[ -f "${xray_qr_config_file}" ]]; then
        ws_grpc_mode=$(info_extraction ws_grpc_mode)
        tls_mode=$(info_extraction tls)
        
        case ${ws_grpc_mode} in
            onlyws) shell_mode="ws";;
            onlygRPC) shell_mode="gRPC";;
            all) shell_mode="ws+gRPC";;
            *);;
        esac
        
        case ${tls_mode} in
            TLS)
                shell_mode="Nginx+${shell_mode}+TLS"
                ;;
            Reality)
                reality_add_more=$(info_extraction reality_add_more)
                reality_add_nginx=$(info_extraction reality_add_nginx)
                
                if [[ ${reality_add_more} != "off" && ${reality_add_nginx} == "off" ]]; then
                    shell_mode="Reality+${shell_mode}"
                elif [[ ${reality_add_nginx} != "off" && ${reality_add_more} != "off" ]]; then
                    shell_mode="Nginx+Reality+${shell_mode}"
                elif [[ ${reality_add_nginx} != "off" && ${reality_add_more} == "off" ]]; then
                    shell_mode="Nginx+Reality"
                else
                    shell_mode="Reality"
                fi
                ;;
            None)
                shell_mode="${shell_mode} ONLY"
                ;;
            *)
                ;;
        esac
        old_tls_mode=${tls_mode}
    fi
}

install_xray_ws_tls() {
    is_root
    check_system
    dependency_install
    basic_optimization
    create_directory
    old_config_exist_check
    domain_check
    ws_grpc_choose
    port_set
    ws_inbound_port_set
    grpc_inbound_port_set
    firewall_set
    ws_path_set
    grpc_path_set
    email_set
    UUID_set
    ws_grpc_qr
    vless_qr_config_tls_ws
    stop_service_all
    xray_install
    port_exist_check 80
    port_exist_check "${port}"
    nginx_exist_check
    nginx_systemd
    web_camouflage
    nginx_ssl_conf_add
    ssl_judge_and_install
    nginx_conf_add
    nginx_servers_conf_add
    xray_conf_add
    tls_type
    basic_information
    enable_process_systemd
    acme_cron_update
    auto_update
    service_restart
    vless_link_image_choice
    show_information
}

install_xray_reality() {
    is_root
    check_system
    dependency_install
    basic_optimization
    create_directory
    old_config_exist_check
    ip_check
    xray_install
    port_set
    email_set
    UUID_set
    target_set
    serverNames_set
    keys_set
    shortIds_set
    xray_reality_add_more_choose
    ws_grpc_qr
    firewall_set
    stop_service_all
    # port_exist_check 80
    port_exist_check "${port}"
    reality_nginx_add_fq
    # nginx_exist_check
    # nginx_systemd
    # nginx_ssl_conf_add
    # ssl_judge_and_install
    # nginx_reality_conf_add
    xray_conf_add
    vless_qr_config_reality
    # tls_type
    basic_information
    enable_process_systemd
    # acme_cron_update
    auto_update
    service_restart
    vless_link_image_choice
    show_information
}

install_xray_ws_only() {
    is_root
    check_system
    dependency_install
    basic_optimization
    create_directory
    old_config_exist_check
    ip_check
    ws_grpc_choose
    ws_inbound_port_set
    grpc_inbound_port_set
    firewall_set
    ws_path_set
    grpc_path_set
    email_set
    UUID_set
    ws_grpc_qr
    vless_qr_config_ws_only
    stop_service_all
    xray_install
    port_exist_check "${xport}"
    port_exist_check "${gport}"
    xray_conf_add
    basic_information
    service_restart
    enable_process_systemd
    auto_update
    vless_link_image_choice
    show_information
}

update_sh() {
    ol_version=${shell_online_version}
    echo "${ol_version}" >${shell_version_tmp}
    [[ -z ${ol_version} ]] && echo -e "${Error} ${RedBG}  检测最新版本失败! ${Font}" && return 1
    echo "${shell_version}" >>${shell_version_tmp}
    newest_version=$(sort -rV ${shell_version_tmp} | head -1)
    oldest_version=$(sort -V ${shell_version_tmp} | head -1)
    version_difference=$(echo "(${newest_version:0:3}-${oldest_version:0:3})>0" | bc)
    if [[ ${shell_version} != ${newest_version} ]]; then
        if [[ ${auto_update} != "YES" ]]; then
            if [[ ${version_difference} == 1 ]]; then
                echo -e "\n${Warning} ${YellowBG} 存在新版本, 但版本跨度较大, 可能存在不兼容情况, 是否更新 [Y/${Red}N${Font}${YellowBG}]? ${Font}"
            else
                echo -e "\n${GreenBG} 存在新版本, 是否更新 [Y/${Red}N${Font}${GreenBG}]? ${Font}"
            fi
            read -r update_confirm
        else
            [[ -z ${ol_version} ]] && echo "检测 脚本 最新版本失败!" >>${log_file} && exit 1
            [[ ${version_difference} == 1 ]] && echo "脚本 版本差别过大, 跳过更新!" >>${log_file} && exit 1
            update_confirm="YES"
        fi
        case $update_confirm in
        [yY][eE][sS] | [yY])
            [[ -L "${idleleo_commend_file}" ]] && rm -f ${idleleo_commend_file}
            wget -N --no-check-certificate -P ${idleleo_dir} https://raw.githubusercontent.com/hello-yunshu/Xray_bash_onekey/main/install.sh && chmod +x ${idleleo_dir}/install.sh
            ln -s ${idleleo_dir}/install.sh ${idleleo_commend_file}
            clear
            echo -e "${OK} ${GreenBG} 更新完成 ${Font}"
            [[ ${version_difference} == 1 ]] && echo -e "${Warning} ${YellowBG} 脚本版本跨度较大, 若服务无法正常运行请卸载后重装! ${Font}"
            ;;
        *) ;;
        esac
    else
        clear
        echo -e "${OK} ${GreenBG} 当前版本为最新版本 ${Font}"
    fi

}

check_file_integrity() {
    if [[ ! -L "${idleleo_commend_file}" ]] && [[ ! -f "${idleleo_dir}/install.sh" ]]; then
        check_system
        pkg_install "bc,jq,wget"
        [[ ! -d "${idleleo_dir}" ]] && mkdir -p ${idleleo_dir}
        [[ ! -d "${idleleo_dir}/tmp" ]] && mkdir -p ${idleleo_dir}/tmp
        wget -N --no-check-certificate -P ${idleleo_dir} https://raw.githubusercontent.com/hello-yunshu/Xray_bash_onekey/main/install.sh && chmod +x ${idleleo_dir}/install.sh
        judge "下载最新脚本"
        ln -s ${idleleo_dir}/install.sh ${idleleo_commend_file}
        clear
        source "$idleleo"
    fi
}

read_version() {
    shell_online_version="$(check_version shell_online_version)"
    xray_version="$(check_version xray_online_version)"
    nginx_build_version="$(check_version nginx_build_online_version)"
}

maintain() {
    echo -e "${Error} ${RedBG} 该选项暂时无法使用! ${Font}"
    echo -e "${Error} ${RedBG} $1 ${Font}"
    exit 0
}

list() {
    case $1 in
    '-1' | '--install-tls')
        shell_mode="Nginx+ws+TLS"
        tls_mode="TLS"
        install_xray_ws_tls
        ;;
    '-2' | '--install-reality')
        shell_mode="Reality"
        tls_mode="Reality"
        install_xray_reality
        ;;
    '-3' | '--install-none')
        echo -e "\n${Warning} ${YellowBG} 此模式推荐用于负载均衡, 一般情况不推荐使用, 是否安装 [Y/${Red}N${Font}${YellowBG}]? ${Font}"
        read -r wsonly_fq
        case $wsonly_fq in
        [yY][eE][sS] | [yY])
            shell_mode="ws ONLY"
            tls_mode="None"
            install_xray_ws_only
            ;;
        *) ;;
        esac
        ;;
    '-4' | '--add-upstream')
        nginx_upstream_server_set
        ;;
    '-5' | '--add-servernames')
        nginx_servernames_server_set
        ;;
    '-au' | '--auto-update')
        auto_update
        ;;
    '-c' | '--clean-logs')
        clean_logs
        ;;
    '-cs' | '--cert-status')
        check_cert_status
        ;;
    '-cu' | '--cert-update')
        cert_update_manuel
        ;;
    '-cau' | '--cert-auto-update')
        acme_cron_update
        ;;
    '-f' | '--set-fail2ban')
        set_fail2ban
        ;;
    '-h' | '--help')
        show_help
        ;;
    '-n' | '--nginx-update')
        [[ $2 == "auto_update" ]] && auto_update="YES" && log_file="${log_dir}/auto_update.log"
        nginx_update
        ;;
    '-p' | '--port-set')
        revision_port
        firewall_set
        service_restart
        ;;
    '--purge' | '--uninstall')
        uninstall_all
        ;;
    '-s' | '-show')
        clear
        basic_information
        vless_qr_link_image
        show_information
        ;;
    '-tcp' | '--tcp')
        bbr_boost_sh
        ;;
    '-tls' | '--tls')
        tls_type
        ;;
    '-u' | '--update')
        [[ $2 == "auto_update" ]] && auto_update="YES" && log_file="${log_dir}/auto_update.log"
        update_sh
        ;;
    '-uu' | '--uuid-set')
        UUID_set
        modify_UUID
        service_restart
        ;;
    '-xa' | '--xray-access')
        clear
        show_access_log
        ;;
    '-xe' | '--xray-error')
        clear
        show_error_log
        ;;
    '-x' | '--xray-update')
        [[ $2 == "auto_update" ]] && auto_update="YES" && log_file="${log_dir}/auto_update.log"
        xray_update
        ;;
    *)
        menu
        ;;
    esac
}

show_help() {
    echo "usage: idleleo [OPTION]"
    echo
    echo 'OPTION:'
    echo '  -1, --install-tls           安装 Xray (Nginx+ws/gRPC+TLS)'
    echo '  -2, --install-reality       安装 Xray (Nginx+Reality+ws/gRPC)'
    echo '  -3, --install-none          安装 Xray (ws/gRPC ONLY)'
    echo '  -4, --add-upstream          变更 Nginx 负载均衡配置'
    echo '  -5, --add-servernames       变更 Nginx serverNames 配置'
    echo '  -au, --auto-update          设置自动更新'
    echo '  -c, --clean-logs            清除日志文件'
    echo '  -cs, --cert-status          查看证书状态'
    echo '  -cu, --cert-update          更新证书有效期'
    echo '  -cau, --cert-auto-update    设置证书自动更新'
    echo '  -f, --set-fail2ban          设置 Fail2ban 防暴力破解'
    echo '  -h, --help                  显示帮助'
    echo '  -n, --nginx-update          更新 Nginx'
    echo '  -p, --port-set              变更 port'
    echo '  --purge, --uninstall        脚本卸载'
    echo '  -s, --show                  显示安装信息'
    echo '  -tcp, --tcp                 配置 TCP 加速'
    echo '  -tls, --tls                 修改 TLS 配置'
    echo '  -u, --update                升级脚本'
    echo '  -uu, --uuid-set             变更 UUIDv5/映射字符串'
    echo '  -xa, --xray-access          显示 Xray 访问信息'
    echo '  -xe, --xray-error           显示 Xray 错误信息'
    echo '  -x, --xray-update           更新 Xray'
    exit 0
}

idleleo_commend() {
    if [[ -L "${idleleo_commend_file}" ]] || [[ -f "${idleleo_dir}/install.sh" ]]; then
        ##在线运行与本地脚本比对
        [[ ! -L "${idleleo_commend_file}" ]] && chmod +x ${idleleo_dir}/install.sh && ln -s ${idleleo_dir}/install.sh ${idleleo_commend_file}
        old_version=$(grep "shell_version=" ${idleleo_dir}/install.sh | head -1 | awk -F '=|"' '{print $3}')
        echo "${old_version}" >${shell_version_tmp}
        echo "${shell_version}" >>${shell_version_tmp}
        oldest_version=$(sort -V ${shell_version_tmp} | head -1)
        version_difference=$(echo "(${shell_version:0:3}-${oldest_version:0:3})>0" | bc)
        if [[ -z ${old_version} ]]; then
            wget -N --no-check-certificate -P ${idleleo_dir} https://raw.githubusercontent.com/hello-yunshu/Xray_bash_onekey/main/install.sh && chmod +x ${idleleo_dir}/install.sh
            judge "下载最新脚本"
            clear
            source "$idleleo"
        elif [[ ${shell_version} != ${oldest_version} ]]; then
            if [[ ${version_difference} == 1 ]]; then
                ## echo -e "${Warning} ${YellowBG} 脚本版本跨度较大, 可能存在不兼容情况, 是否继续使用 [Y/${Red}N${Font}${YellowBG}]? ${Font}" 紧急更新
                echo -e "${Warning} ${YellowBG} 此版本需要${Red}Xray版本在1.6.2及以上${Font}, 是否继续使用 [Y/${Red}N${Font}${YellowBG}]? ${Font}"
                read -r update_sh_fq
                case $update_sh_fq in
                [yY][eE][sS] | [yY])
                    rm -rf ${idleleo_dir}/install.sh
                    wget -N --no-check-certificate -P ${idleleo_dir} https://raw.githubusercontent.com/hello-yunshu/Xray_bash_onekey/main/install.sh && chmod +x ${idleleo_dir}/install.sh
                    judge "下载最新脚本"
                    clear
                    ## echo -e "${Warning} ${YellowBG} 脚本版本跨度较大, 若服务无法正常运行请卸载后重装!\n ${Font}" 紧急更新
                    echo -e "${Warning} ${YellowBG} 务必保证${Red}Xray版本在1.6.2及以上${Font}, 否则将无法正常使用!\n ${Font}"
                    ;;
                *)
                    source "$idleleo"
                    ;;
                esac
            else
                rm -rf ${idleleo_dir}/install.sh
                wget -N --no-check-certificate -P ${idleleo_dir} https://raw.githubusercontent.com/hello-yunshu/Xray_bash_onekey/main/install.sh && chmod +x ${idleleo_dir}/install.sh
                judge "下载最新脚本"
                clear
            fi
            source "$idleleo"
        else
            ol_version=${shell_online_version}
            echo "${ol_version}" >${shell_version_tmp}
            [[ -z ${ol_version} ]] && shell_need_update="${Red}[检测失败!]${Font}"
            echo "${shell_version}" >>${shell_version_tmp}
            newest_version=$(sort -rV ${shell_version_tmp} | head -1)
            if [[ ${shell_version} != ${newest_version} ]]; then
                shell_need_update="${Red}[有新版!]${Font}"
                shell_emoji="${Red}>_<${Font}"
            else
                shell_need_update="${Green}[最新版]${Font}"
                shell_emoji="${Green}^O^${Font}"
            fi
            if [[ -f "${xray_qr_config_file}" ]]; then
                if [[ "$(info_extraction nginx_build_version)" == "null" ]] || [[ ! -f "${nginx_dir}/sbin/nginx" ]]; then
                    nginx_need_update="${Green}[未安装]${Font}"
                elif [[ ${nginx_build_version} != $(info_extraction nginx_build_version) ]]; then
                    nginx_need_update="${Green}[有新版]${Font}"
                else
                    nginx_need_update="${Green}[最新版]${Font}"
                fi
                if [[ -f "${xray_qr_config_file}" ]] && [[ -f "${xray_conf}" ]] && [[ -f "${xray_bin_dir}/xray" ]]; then
                    xray_online_version=$(check_version xray_online_version)
                    ##xray_online_version=$(check_version xray_online_pre_version)
                    if [[ "$(info_extraction xray_version)" == "null" ]]; then
                        xray_need_update="${Green}[已安装] (版本未知)${Font}"
                    elif [[ ${xray_version} != $(info_extraction xray_version) ]] && [[ $(info_extraction xray_version) != ${xray_online_version} ]]; then
                        xray_need_update="${Red}[有新版!]${Font}"
                        ### xray_need_update="${Red}[请务必更新!]${Font}"
                    elif [[ ${xray_version} == $(info_extraction xray_version) ]] || [[ $(info_extraction xray_version) == ${xray_online_version} ]]; then
                        if [[ $(info_extraction xray_version) != ${xray_online_version} ]]; then
                            xray_need_update="${Green}[有测试版]${Font}"
                        else
                            xray_need_update="${Green}[最新版]${Font}"
                        fi
                    fi
                else
                    xray_need_update="${Red}[未安装]${Font}"
                fi
            else
                nginx_need_update="${Green}[未安装]${Font}"
                xray_need_update="${Red}[未安装]${Font}"
            fi
        fi
    fi
}

check_program() {
    if [[ -n $(pgrep nginx) ]]; then
        nignx_status="${Green}运行中..${Font}"
    elif [[ ${tls_mode} == "None" ]] || [[ ${reality_add_nginx} == "off" ]]; then
        nignx_status="${Green}无需测试${Font}"
    else
        nignx_status="${Red}未运行${Font}"
    fi
    if [[ -n $(pgrep xray) ]]; then
        xray_status="${Green}运行中..${Font}"
    else
        xray_status="${Red}未运行${Font}"
    fi
}

curl_local_connect() {
    curl -Is -o /dev/null -w %{http_code} "https://$1/$2"
}

check_xray_local_connect() {
    if [[ -f "${xray_qr_config_file}" ]]; then
        xray_local_connect_status="${Red}无法连通${Font}"
        if [[ ${tls_mode} == "TLS" ]]; then
            [[ ${ws_grpc_mode} == "onlyws" ]] && [[ $(curl_local_connect $(info_extraction host) $(info_extraction path)) == "400" ]] && xray_local_connect_status="${Green}本地正常${Font}"
            [[ ${ws_grpc_mode} == "onlygrpc" ]] && [[ $(curl_local_connect $(info_extraction host) $(info_extraction serviceName)) == "502" ]] && xray_local_connect_status="${Green}本地正常${Font}"
            [[ ${ws_grpc_mode} == "all" ]] && [[ $(curl_local_connect $(info_extraction host) $(info_extraction serviceName)) == "502" && $(curl_local_connect $(info_extraction host) $(info_extraction path)) == "400" ]] && xray_local_connect_status="${Green}本地正常${Font}"
        elif [[ ${tls_mode} == "Reality" ]]; then
            #[[ $(curl_local_connect $(info_extraction host)) == "302" ]] && xray_local_connect_status="${Green}本地正常${Font}"
            xray_local_connect_status="${Green}无需测试${Font}"
        elif [[ ${tls_mode} == "None" ]]; then
            xray_local_connect_status="${Green}无需测试${Font}"
        fi
    else
        xray_local_connect_status="${Red}未安装${Font}"
    fi
}

check_online_version_connect() {
    xray_online_version_status=$(curl_local_connect "www.idleleo.com" "api/xray_shell_versions")
    if [[ ${xray_online_version_status} != "200" ]]; then
        if [[ ${xray_online_version_status} == "403" ]]; then
            echo -e "${Error} ${RedBG} 脚本维护中.. 请稍后再试! ${Font}"
        else
            echo -e "${Error} ${RedBG} 无法检测所需依赖的在线版本, 请稍后再试! ${Font}"
        fi
        sleep 0.5
        exit 0
    fi
}

menu() {

    echo -e "\nXray 安装管理脚本 ${Red}[${shell_version}]${Font} ${shell_emoji}"
    echo -e "--- authored by hello-yunshu ---"
    echo -e "--- changed by www.idleleo.com ---"
    echo -e "--- https://github.com/hello-yunshu ---\n"
    echo -e "当前模式: ${shell_mode}\n"

    echo -e "可以使用${RedW} idleleo ${Font}命令管理脚本${Font}\n"

    echo -e "—————————————— ${GreenW}版本检测${Font} ——————————————"
    echo -e "脚本:  ${shell_need_update}"
    echo -e "Xray:  ${xray_need_update}"
    echo -e "Nginx: ${nginx_need_update}"
    echo -e "—————————————— ${GreenW}运行状态${Font} ——————————————"
    echo -e "Xray:   ${xray_status}"
    echo -e "Nginx:  ${nignx_status}"
    echo -e "连通性: ${xray_local_connect_status}"
    echo -e "—————————————— ${GreenW}升级向导${Font} ——————————————"
    echo -e "${Green}0.${Font}  升级 脚本"
    echo -e "${Green}1.${Font}  升级 Xray"
    echo -e "${Green}2.${Font}  升级 Nginx"
    echo -e "—————————————— ${GreenW}安装向导${Font} ——————————————"
    echo -e "${Green}3.${Font}  安装 Xray (Nginx+ws/gRPC+TLS)"
    echo -e "${Green}4.${Font}  安装 Xray (Reality+ws/gRPC+Nginx)"
    echo -e "${Green}5.${Font}  安装 Xray (ws/gRPC ONLY)"
    echo -e "—————————————— ${GreenW}配置变更${Font} ——————————————"
    echo -e "${Green}6.${Font}  变更 UUIDv5/映射字符串"
    echo -e "${Green}7.${Font}  变更 port"
    echo -e "${Green}8.${Font}  变更 TLS 版本"
    echo -e "${Green}9.${Font}  变更 Nginx 负载均衡配置"
    echo -e "${Green}10.${Font} 变更 Nginx serverNames 配置"
    echo -e "—————————————— ${GreenW}用户管理${Font} ——————————————"
    echo -e "${Green}11.${Font} 查看 Xray 用户"
    echo -e "${Green}12.${Font} 添加 Xray 用户"
    echo -e "${Green}13.${Font} 删除 Xray 用户"
    echo -e "—————————————— ${GreenW}查看信息${Font} ——————————————"
    echo -e "${Green}14.${Font} 查看 Xray 实时访问日志"
    echo -e "${Green}15.${Font} 查看 Xray 实时错误日志"
    echo -e "${Green}16.${Font} 查看 Xray 配置信息"
    echo -e "—————————————— ${GreenW}服务相关${Font} ——————————————"
    echo -e "${Green}17.${Font} 重启 所有服务"
    echo -e "${Green}18.${Font} 启动 所有服务"
    echo -e "${Green}19.${Font} 停止 所有服务"
    echo -e "${Green}20.${Font} 查看 所有服务"
    echo -e "—————————————— ${GreenW}证书相关${Font} ——————————————"
    echo -e "${Green}21.${Font} 查看 证书状态"
    echo -e "${Green}22.${Font} 更新 证书有效期"
    echo -e "${Green}23.${Font} 设置 证书自动更新"
    echo -e "—————————————— ${GreenW}其他选项${Font} ——————————————"
    echo -e "${Green}24.${Font} 配置 自动更新"
    echo -e "${Green}25.${Font} 设置 TCP 加速"
    echo -e "${Green}26.${Font} 设置 Fail2ban 防暴力破解"
    echo -e "${Green}27.${Font} 设置 Xray 流量统计"
    echo -e "${Green}28.${Font} 清除 日志文件"
    echo -e "${Green}29.${Font} 测试 服务器网速"
    echo -e "—————————————— ${GreenW}卸载向导${Font} ——————————————"
    echo -e "${Green}30.${Font} 卸载 脚本"
    echo -e "${Green}31.${Font} 清空 证书文件"
    echo -e "${Green}32.${Font} 退出 \n"

    read -rp "请输入数字: " menu_num
    case $menu_num in
    0)
        update_sh
        source "$idleleo"
        ;;
    1)
        xray_update
        timeout "清空屏幕!"
        clear
        source "$idleleo"
        ;;
    2)
        echo -e "\n${Red}[不建议]${Font} 频繁升级 Nginx, 请确认 Nginx 有升级的必要! "
        timeout "开始升级!"
        nginx_update
        timeout "清空屏幕!"
        clear
        source "$idleleo"
        ;;
    3)
        shell_mode="Nginx+ws+TLS"
        tls_mode="TLS"
        install_xray_ws_tls
        source "$idleleo"
        ;;
    4)
        shell_mode="Reality"
        tls_mode="Reality"
        install_xray_reality
        source "$idleleo"
        ;;
    5)
        echo -e "\n${Warning} ${YellowBG} 此模式推荐用于负载均衡, 一般情况不推荐使用, 是否安装 [Y/${Red}N${Font}${YellowBG}]? ${Font}"
        read -r wsonly_fq
        case $wsonly_fq in
        [yY][eE][sS] | [yY])
            shell_mode="ws ONLY"
            tls_mode="None"
            install_xray_ws_only
            ;;
        *) ;;
        esac
        source "$idleleo"
        ;;
    6)
        UUID_set
        modify_UUID
        service_restart
        vless_qr_link_image
        timeout "清空屏幕!"
        clear
        menu
        ;;
    7)
        revision_port
        firewall_set
        service_restart
        vless_qr_link_image
        timeout "清空屏幕!"
        clear
        menu
        ;;
    8)
        tls_type
        timeout "清空屏幕!"
        clear
        menu
        ;;
    9)
        nginx_upstream_server_set
        timeout "清空屏幕!"
        clear
        menu
        ;;
    10)
        nginx_servernames_server_set
        timeout "清空屏幕!"
        clear
        menu
        ;;
    11)
        show_user
        timeout "回到菜单!"
        menu
        ;;
    12)
        add_user
        timeout "回到菜单!"
        menu
        ;;
    13)
        remove_user
        timeout "回到菜单!"
        menu
        ;;
    14)
        clear
        show_access_log
        ;;
    15)
        clear
        show_error_log
        ;;
    16)
        clear
        basic_information
        vless_qr_link_image
        show_information
        menu
        ;;
    17)
        service_restart
        timeout "清空屏幕!"
        clear
        menu
        ;;
    18)
        service_start
        timeout "清空屏幕!"
        clear
        source "$idleleo"
        ;;
    19)
        service_stop
        timeout "清空屏幕!"
        clear
        source "$idleleo"
        ;;
    20)
        if [[ ${tls_mode} == "TLS" ]] || [[ ${reality_add_nginx} == "on" ]]; then
            systemctl status nginx
        fi
        systemctl status xray
        menu
        ;;
    21)
        check_cert_status
        timeout "回到菜单!"
        menu
        ;;
    22)
        cert_update_manuel
        timeout "回到菜单!"
        menu
        ;;
    23)
        acme_cron_update
        timeout "回到菜单!"
        clear
        menu
        ;;
    24)
        auto_update
        timeout "清空屏幕!"
        clear
        menu
        ;;
    25)
        clear
        bbr_boost_sh
        ;;
    26)
        set_fail2ban
        menu
        ;;
    27)
        xray_status_add
        timeout "回到菜单!"
        menu
        ;;
    28)
        clean_logs
        menu
        ;;
    29)
        clear
        bash <(curl -Lso- https://git.io/Jlkmw)
        ;;
    20)
        uninstall_all
        timeout "清空屏幕!"
        clear
        source "$idleleo"
        ;;
    31)
        delete_tls_key_and_crt
        rm -rf ${ssl_chainpath}/*
        timeout "清空屏幕!"
        clear
        menu
        ;;
    32)
        timeout "清空屏幕!"
        clear
        exit 0
        ;;
    *)
        clear
        echo -e "${Error} ${RedBG} 请输入正确的数字! ${Font}"
        menu
        ;;
    esac
}

check_file_integrity
check_online_version_connect
read_version
judge_mode
idleleo_commend
check_program
check_xray_local_connect
list "$@"
