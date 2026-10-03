#!/usr/bin/env bash
#
# https://github.com/P3TERX/warp.sh
# Description: Cloudflare WARP Installer
# System Required: Debian, Ubuntu, Fedora, CentOS, Oracle Linux, Arch Linux
# Version: 1.0.43_Final
#
# MIT License
#
# Copyright (c) 2021-2024 P3TERX <https://p3terx.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#

shVersion='1.0.43_Final'

FontColor_Red="\033[31m"
FontColor_Red_Bold="\033[1;31m"
FontColor_Green="\033[32m"
FontColor_Green_Bold="\033[1;32m"
FontColor_Yellow="\033[33m"
FontColor_Yellow_Bold="\033[1;33m"
FontColor_Purple="\033[35m"
FontColor_Purple_Bold="\033[1;35m"
FontColor_Suffix="\033[0m"

WARP_CLI_ACCEPT_TOS=''
WARP_CLI_HELP=''
WARP_CLI_LAST_OUTPUT=''
WARP_CLI_LAST_STATUS=0

warp_cli_detect() {
    if [[ -n ${WARP_CLI_HELP} ]]; then
        return
    fi
    WARP_CLI_HELP="$(warp-cli --help 2>&1 || true)"
    if echo "${WARP_CLI_HELP}" | grep -q -- '--accept-tos'; then
        WARP_CLI_ACCEPT_TOS='--accept-tos'
    fi
}

warp_cli_run() {
    warp_cli_detect
    if [[ -n ${WARP_CLI_ACCEPT_TOS} ]]; then
        warp-cli ${WARP_CLI_ACCEPT_TOS} "$@"
    else
        warp-cli "$@"
    fi
}

warp_cli_try() {
    local output status
    output="$(warp_cli_run "$@" 2>&1)"
    status=$?
    WARP_CLI_LAST_OUTPUT="${output}"
    WARP_CLI_LAST_STATUS=${status}
    echo "${output}"
    if [[ ${status} -eq 0 ]]; then
        return 0
    fi
    if echo "${output}" | grep -qi 'unrecognized subcommand'; then
        return 2
    fi
    return ${status}
}

warp_cli_registration_show() {
    local output status
    output="$(warp_cli_try registration show)"
    status=$?
    if [[ ${status} -eq 0 ]]; then
        echo "${output}"
        return 0
    fi
    if [[ ${status} -eq 2 ]]; then
        output="$(warp_cli_try account)"
        status=$?
    fi
    echo "${output}"
    return ${status}
}

warp_cli_registration_new() {
    local output status
    output="$(warp_cli_try registration new)"
    status=$?
    if [[ ${status} -eq 0 ]]; then
        echo "${output}"
        return 0
    fi
    if [[ ${status} -eq 2 ]]; then
        output="$(warp_cli_try register)"
        status=$?
    fi
    echo "${output}"
    return ${status}
}

warp_cli_is_registered() {
    local output status
    output="$(warp_cli_registration_show 2>&1)"
    status=$?
    if echo "${output}" | grep -qiE 'missing|not registered|no registration'; then
        return 1
    fi
    if [[ ${status} -ne 0 ]]; then
        return 1
    fi
    return 0
}

warp_cli_connect() {
    warp_cli_run connect
}

warp_cli_disconnect() {
    warp_cli_run disconnect
}

warp_cli_enable_always_on() {
    warp_cli_detect
    if echo "${WARP_CLI_HELP}" | grep -qi 'always-on'; then
        warp_cli_run enable-always-on || true
    fi
}

warp_cli_disable_always_on() {
    warp_cli_detect
    if echo "${WARP_CLI_HELP}" | grep -qi 'always-on'; then
        warp_cli_run disable-always-on || true
    fi
}

warp_cli_mode_proxy() {
    local output status
    output="$(warp_cli_try mode proxy)"
    status=$?
    if [[ ${status} -eq 0 ]]; then
        echo "${output}"
        return 0
    fi
    if [[ ${status} -eq 2 ]]; then
        output="$(warp_cli_try set-mode proxy)"
        status=$?
        if [[ ${status} -eq 0 ]]; then
            echo "${output}"
            return 0
        fi
    fi
    echo "${output}"
    return ${status}
}

log() {
    local LEVEL="$1"
    local MSG="$2"
    case "${LEVEL}" in
    INFO)
        local LEVEL="[${FontColor_Green}${LEVEL}${FontColor_Suffix}]"
        local MSG="${LEVEL} ${MSG}"
        ;;
    WARN)
        local LEVEL="[${FontColor_Yellow}${LEVEL}${FontColor_Suffix}]"
        local MSG="${LEVEL} ${MSG}"
        ;;
    ERROR)
        local LEVEL="[${FontColor_Red}${LEVEL}${FontColor_Suffix}]"
        local MSG="${LEVEL} ${MSG}"
        ;;
    *) ;;
    esac
    echo -e "${MSG}"
}

if [[ $(uname -s) != Linux ]]; then
    log ERROR "This operating system is not supported."
    exit 1
fi

if [[ $(id -u) != 0 ]]; then
    log ERROR "This script must be run as root."
    exit 1
fi

if [[ -z $(command -v curl) ]]; then
    log ERROR "cURL is not installed."
    exit 1
fi

WGCF_Profile='wgcf-profile.conf'
WGCF_ProfileDir="/etc/warp"
WGCF_ProfilePath="${WGCF_ProfileDir}/${WGCF_Profile}"

WireGuard_Interface='wgcf'
WireGuard_ConfPath="/etc/wireguard/${WireGuard_Interface}.conf"

WireGuard_Interface_DNS_IPv4='8.8.8.8,8.8.4.4'
WireGuard_Interface_DNS_IPv6='2001:4860:4860::8888,2001:4860:4860::8844'
WireGuard_Interface_DNS_46="${WireGuard_Interface_DNS_IPv4},${WireGuard_Interface_DNS_IPv6}"
WireGuard_Interface_DNS_64="${WireGuard_Interface_DNS_IPv6},${WireGuard_Interface_DNS_IPv4}"
WireGuard_Interface_Rule_table='51888'
WireGuard_Interface_Rule_fwmark='51888'
WireGuard_Interface_MTU='1280'

WireGuard_Peer_Endpoint_IP4='162.159.192.1'
WireGuard_Peer_Endpoint_IP6='2606:4700:d0::a29f:c001'
WireGuard_Peer_Endpoint_IPv4="${WireGuard_Peer_Endpoint_IP4}:2408"
WireGuard_Peer_Endpoint_IPv6="[${WireGuard_Peer_Endpoint_IP6}]:2408"
WireGuard_Peer_Endpoint_Domain='engage.cloudflareclient.com:2408'
WireGuard_Peer_AllowedIPs_IPv4='0.0.0.0/0'
WireGuard_Peer_AllowedIPs_IPv6='::/0'
WireGuard_Peer_AllowedIPs_DualStack='0.0.0.0/0,::/0'

TestIPv4_1='1.0.0.1'
TestIPv4_2='9.9.9.9'
TestIPv6_1='2606:4700:4700::1001'
TestIPv6_2='2620:fe::fe'
CF_Trace_URL='https://www.cloudflare.com/cdn-cgi/trace'

Usque_BinPath='/usr/local/bin/usque'
Usque_ConfigDir='/etc/usque'
Usque_ConfigPath="${Usque_ConfigDir}/config.json"
Usque_SettingsPath="${Usque_ConfigDir}/proxy.conf"
Usque_Service='usque-warp'
Usque_ServicePath="/etc/systemd/system/${Usque_Service}.service"
Usque_Bind='127.0.0.1'
Usque_Port='40000'

Get_System_Info() {
    source /etc/os-release
    SysInfo_OS_CodeName="${VERSION_CODENAME}"
    SysInfo_OS_Name_lowercase="${ID}"
    SysInfo_OS_Name_Full="${PRETTY_NAME}"
    SysInfo_RelatedOS="${ID_LIKE}"
    SysInfo_Kernel="$(uname -r)"
    SysInfo_Kernel_Ver_major="$(uname -r | awk -F . '{print $1}')"
    SysInfo_Kernel_Ver_minor="$(uname -r | awk -F . '{print $2}')"
    SysInfo_Arch="$(uname -m)"
    SysInfo_Virt="$(systemd-detect-virt)"
    case ${SysInfo_RelatedOS} in
    *fedora* | *rhel*)
        SysInfo_OS_Ver_major="$(rpm -E '%{rhel}')"
        ;;
    *)
        SysInfo_OS_Ver_major="$(echo ${VERSION_ID} | cut -d. -f1)"
        ;;
    esac
}

Print_System_Info() {
    echo -e "
System Information
---------------------------------------------------
  Operating System: ${SysInfo_OS_Name_Full}
      Linux Kernel: ${SysInfo_Kernel}
      Architecture: ${SysInfo_Arch}
    Virtualization: ${SysInfo_Virt}
---------------------------------------------------
"
}

Install_Requirements_Debian() {
    if [[ ! $(command -v gpg) ]]; then
        apt update
        apt install gnupg -y
    fi
    if [[ ! $(apt list 2>/dev/null | grep apt-transport-https | grep installed) ]]; then
        apt update
        apt install apt-transport-https -y
    fi
}

Install_WARP_Client_Debian() {
    if [[ ${SysInfo_OS_Name_lowercase} = ubuntu ]]; then
        case ${SysInfo_OS_CodeName} in
        noble | jammy | focal | bionic | xenial) ;;
        *)
            log ERROR "This operating system is not supported."
            exit 1
            ;;
        esac
    elif [[ ${SysInfo_OS_Name_lowercase} = debian ]]; then
        case ${SysInfo_OS_CodeName} in
        trixie | bookworm | bullseye | buster | stretch) ;;
        *)
            log ERROR "This operating system is not supported."
            exit 1
            ;;
        esac
    fi
    Install_Requirements_Debian
    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ ${SysInfo_OS_CodeName} main" | tee /etc/apt/sources.list.d/cloudflare-client.list
    apt update
    apt install cloudflare-warp -y
}

Install_WARP_Client_CentOS() {
    if [[ ${SysInfo_OS_Ver_major} = 8 ]]; then
        rpm --import https://pkg.cloudflareclient.com/pubkey.gpg
        curl -fsSL https://pkg.cloudflareclient.com/cloudflare-warp-ascii.repo | tee /etc/yum.repos.d/cloudflare-warp.repo
        yum update -y
        yum install cloudflare-warp -y
    else
        log ERROR "This operating system is not supported."
        exit 1
    fi
}

Check_WARP_Client() {
    WARP_Client_Status=$(systemctl is-active warp-svc)
    WARP_Client_SelfStart=$(systemctl is-enabled warp-svc 2>/dev/null)
}

Install_WARP_Client() {
    Print_System_Info
    log INFO "Installing Cloudflare WARP Client..."
    if [[ ${SysInfo_Arch} != x86_64 ]]; then
        log ERROR "This CPU architecture is not supported: ${SysInfo_Arch}"
        exit 1
    fi
    case ${SysInfo_OS_Name_lowercase} in
    *debian* | *ubuntu*)
        Install_WARP_Client_Debian
        ;;
    *centos* | *rhel*)
        Install_WARP_Client_CentOS
        ;;
    *)
        if [[ ${SysInfo_RelatedOS} = *rhel* || ${SysInfo_RelatedOS} = *fedora* ]]; then
            Install_WARP_Client_CentOS
        else
            log ERROR "This operating system is not supported."
            exit 1
        fi
        ;;
    esac
    Check_WARP_Client
    if [[ ${WARP_Client_Status} = active ]]; then
        log INFO "Cloudflare WARP Client installed successfully!"
    else
        log ERROR "warp-svc failure to run!"
        journalctl -u warp-svc --no-pager
        exit 1
    fi
}

Uninstall_WARP_Client() {
    log INFO "Uninstalling Cloudflare WARP Client..."
    case ${SysInfo_OS_Name_lowercase} in
    *debian* | *ubuntu*)
        apt purge cloudflare-warp -y
        rm -f /etc/apt/sources.list.d/cloudflare-client.list /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
        ;;
    *centos* | *rhel*)
        yum remove cloudflare-warp -y
        ;;
    *)
        if [[ ${SysInfo_RelatedOS} = *rhel* || ${SysInfo_RelatedOS} = *fedora* ]]; then
            yum remove cloudflare-warp -y
        else
            log ERROR "This operating system is not supported."
            exit 1
        fi
        ;;
    esac
}

Restart_WARP_Client() {
    log INFO "Restarting Cloudflare WARP Client..."
    systemctl restart warp-svc
    Check_WARP_Client
    if [[ ${WARP_Client_Status} = active ]]; then
        log INFO "Cloudflare WARP Client has been restarted."
    else
        log ERROR "Cloudflare WARP Client failure to run!"
        journalctl -u warp-svc --no-pager
        exit 1
    fi
}

Init_WARP_Client() {
    Check_WARP_Client
    if [[ ${WARP_Client_SelfStart} != enabled || ${WARP_Client_Status} != active ]]; then
        if [[ -z $(command -v warp-cli) ]]; then
            Install_WARP_Client
        elif ! systemctl enable warp-svc --now; then
            log ERROR "Failed to enable Cloudflare WARP Client."
            return 1
        fi
    fi
    if ! warp_cli_is_registered; then
        log INFO "Cloudflare WARP Account Registration in progress..."
        if ! warp_cli_registration_new; then
            log ERROR "Cloudflare WARP Account registration failed."
            return 1
        fi
    fi
}

Connect_WARP() {
    log INFO "Connecting to WARP..."
    if ! warp_cli_connect; then
        log ERROR "Failed to connect to WARP."
        return 1
    fi
    log INFO "Enable WARP Always-On..."
    warp_cli_enable_always_on
}

Disconnect_WARP() {
    log INFO "Disable WARP Always-On..."
    warp_cli_disable_always_on
    log INFO "Disconnect from WARP..."
    warp_cli_disconnect
}

Disable_WARP_Client() {
    local load_state
    if ! load_state=$(systemctl show warp-svc --property=LoadState --value); then
        log ERROR "Failed to check Cloudflare WARP Client."
        return 1
    fi
    if [[ ${load_state} = not-found ]]; then
        log INFO "Cloudflare WARP Client is not installed."
        return 0
    fi
    if systemctl is-active --quiet warp-svc && command -v warp-cli >/dev/null 2>&1; then
        Disconnect_WARP || log WARN "Failed to disconnect WARP; stopping the service."
    fi
    log INFO "Disabling Cloudflare WARP Client..."
    if ! systemctl disable warp-svc --now; then
        log ERROR "Failed to disable Cloudflare WARP Client."
        return 1
    fi
    log INFO "Cloudflare WARP Client is stopped and disabled. Configuration has been preserved."
}

Set_WARP_Mode_Proxy() {
    log INFO "Setting up WARP Proxy Mode..."
    if ! warp_cli_mode_proxy; then
        if echo "${WARP_CLI_LAST_OUTPUT}" | grep -qiE 'unrecognized subcommand|invalid|unknown'; then
            log ERROR "WARP CLI proxy mode is not supported in this version."
        else
            log ERROR "Failed to set WARP Proxy Mode."
        fi
        return 1
    fi
}

Enable_WARP_Client_Proxy() {
    Init_WARP_Client || return 1
    Set_WARP_Mode_Proxy || return 1
    Connect_WARP || return 1
    Print_WARP_Client_Status
}

Get_WARP_Proxy_Port() {
    WARP_Proxy_Port='40000'
}

Get_WARP_Upstream_Protocol() {
    local settings protocol
    WARP_Upstream_Protocol_zh='未检测'
    WARP_Upstream_Protocol_en='Unknown'
    if [[ ${WARP_Client_Status} != active ]] || ! command -v warp-cli >/dev/null 2>&1; then
        return 0
    fi
    settings=$(warp_cli_run settings 2>/dev/null) || return 0
    protocol=$(printf '%s\n' "${settings}" | awk '
        tolower($0) ~ /tunnel protocol[[:space:]]*:/ {
            sub(/^.*:[[:space:]]*/, "")
            sub(/[[:space:]]+$/, "")
            print
            exit
        }')
    case ${protocol,,} in
    wireguard)
        WARP_Upstream_Protocol_zh='WireGuard / UDP'
        WARP_Upstream_Protocol_en='WireGuard / UDP'
        ;;
    masque)
        WARP_Upstream_Protocol_zh='MASQUE'
        WARP_Upstream_Protocol_en='MASQUE'
        ;;
    esac
}

Print_Delimiter() {
    printf '=%.0s' $(seq $(tput cols))
    echo
}

Install_wgcf() {
    curl -fsSL git.io/wgcf.sh | bash
}

Uninstall_wgcf() {
    rm -f /usr/local/bin/wgcf
}

Register_WARP_Account() {
    while [[ ! -f wgcf-account.toml ]]; do
        Install_wgcf
        log INFO "Cloudflare WARP Account registration in progress..."
        yes | wgcf register
        sleep 5
    done
}

Generate_WGCF_Profile() {
    while [[ ! -f ${WGCF_Profile} ]]; do
        Register_WARP_Account
        log INFO "WARP WireGuard profile (wgcf-profile.conf) generation in progress..."
        wgcf generate
    done
    Uninstall_wgcf
}

Backup_WGCF_Profile() {
    mkdir -p ${WGCF_ProfileDir}
    mv -f wgcf* ${WGCF_ProfileDir}
}

Read_WGCF_Profile() {
    WireGuard_Interface_PrivateKey=$(cat ${WGCF_ProfilePath} | grep ^PrivateKey | cut -d= -f2- | awk '$1=$1')
    WireGuard_Interface_Address=$(cat ${WGCF_ProfilePath} | grep ^Address | cut -d= -f2- | awk '$1=$1' | sed ":a;N;s/\n/,/g;ta")
    WireGuard_Peer_PublicKey=$(cat ${WGCF_ProfilePath} | grep ^PublicKey | cut -d= -f2- | awk '$1=$1')
    WireGuard_Interface_Address_IPv4=$(echo ${WireGuard_Interface_Address} | cut -d, -f1 | cut -d'/' -f1)
    WireGuard_Interface_Address_IPv6=$(echo ${WireGuard_Interface_Address} | cut -d, -f2 | cut -d'/' -f1)
}

Load_WGCF_Profile() {
    if [[ -f ${WGCF_Profile} ]]; then
        Backup_WGCF_Profile
        Read_WGCF_Profile
    elif [[ -f ${WGCF_ProfilePath} ]]; then
        Read_WGCF_Profile
    else
        Generate_WGCF_Profile
        Backup_WGCF_Profile
        Read_WGCF_Profile
    fi
}

Install_WireGuardTools_Debian() {
    case ${SysInfo_OS_Ver_major} in
    10)
        if [[ -z $(grep "^deb.*buster-backports.*main" /etc/apt/sources.list{,.d/*}) ]]; then
            echo "deb http://deb.debian.org/debian buster-backports main" | tee /etc/apt/sources.list.d/backports.list
        fi
        ;;
    *)
        if [[ ${SysInfo_OS_Ver_major} -lt 10 ]]; then
            log ERROR "This operating system is not supported."
            exit 1
        fi
        ;;
    esac
    apt update
    apt install iproute2 openresolv -y
    apt install wireguard-tools --no-install-recommends -y
}

Install_WireGuardTools_Ubuntu() {
    apt update
    apt install iproute2 openresolv -y
    apt install wireguard-tools --no-install-recommends -y
}

Install_WireGuardTools_CentOS() {
    yum install epel-release -y || yum install https://dl.fedoraproject.org/pub/epel/epel-release-latest-${SysInfo_OS_Ver_major}.noarch.rpm -y
    yum install iproute iptables wireguard-tools -y
}

Install_WireGuardTools_Fedora() {
    dnf install iproute iptables wireguard-tools -y
}

Install_WireGuardTools_Arch() {
    pacman -Sy iproute2 openresolv wireguard-tools --noconfirm
}

Install_WireGuardTools() {
    log INFO "Installing wireguard-tools..."
    case ${SysInfo_OS_Name_lowercase} in
    *debian*)
        Install_WireGuardTools_Debian
        ;;
    *ubuntu*)
        Install_WireGuardTools_Ubuntu
        ;;
    *centos* | *rhel*)
        Install_WireGuardTools_CentOS
        ;;
    *fedora*)
        Install_WireGuardTools_Fedora
        ;;
    *arch*)
        Install_WireGuardTools_Arch
        ;;
    *)
        if [[ ${SysInfo_RelatedOS} = *rhel* || ${SysInfo_RelatedOS} = *fedora* ]]; then
            Install_WireGuardTools_CentOS
        else
            log ERROR "This operating system is not supported."
            exit 1
        fi
        ;;
    esac
}

Install_WireGuardGo() {
    case ${SysInfo_Virt} in
    openvz | lxc*)
        curl -fsSL git.io/wireguard-go.sh | bash
        ;;
    *)
        if [[ ${SysInfo_Kernel_Ver_major} -lt 5 || ${SysInfo_Kernel_Ver_minor} -lt 6 ]]; then
            curl -fsSL git.io/wireguard-go.sh | bash
        fi
        ;;
    esac
}

Check_WireGuard() {
    WireGuard_Status=$(systemctl is-active wg-quick@${WireGuard_Interface})
    WireGuard_SelfStart=$(systemctl is-enabled wg-quick@${WireGuard_Interface} 2>/dev/null)
}

Install_WireGuard() {
    Print_System_Info
    Check_WireGuard
    if [[ ${WireGuard_SelfStart} != enabled || ${WireGuard_Status} != active ]]; then
        Install_WireGuardTools
        Install_WireGuardGo
    else
        log INFO "WireGuard is installed and running."
    fi
}

Start_WireGuard() {
    Check_WARP_Client
    log INFO "Starting WireGuard..."
    if [[ ${WARP_Client_Status} = active ]]; then
        systemctl stop warp-svc
        systemctl enable wg-quick@${WireGuard_Interface} --now
        systemctl start warp-svc
    else
        systemctl enable wg-quick@${WireGuard_Interface} --now
    fi
    Check_WireGuard
    if [[ ${WireGuard_Status} = active ]]; then
        log INFO "WireGuard is running."
    else
        log ERROR "WireGuard failure to run!"
        journalctl -u wg-quick@${WireGuard_Interface} --no-pager
        exit 1
    fi
}

Restart_WireGuard() {
    Check_WARP_Client
    log INFO "Restarting WireGuard..."
    if [[ ${WARP_Client_Status} = active ]]; then
        systemctl stop warp-svc
        systemctl restart wg-quick@${WireGuard_Interface}
        systemctl start warp-svc
    else
        systemctl restart wg-quick@${WireGuard_Interface}
    fi
    Check_WireGuard
    if [[ ${WireGuard_Status} = active ]]; then
        log INFO "WireGuard has been restarted."
    else
        log ERROR "WireGuard failure to run!"
        journalctl -u wg-quick@${WireGuard_Interface} --no-pager
        exit 1
    fi
}

Enable_IPv6_Support() {
    if [[ $(sysctl -a | grep 'disable_ipv6.*=.*1') || $(cat /etc/sysctl.{conf,d/*} | grep 'disable_ipv6.*=.*1') ]]; then
        sed -i '/disable_ipv6/d' /etc/sysctl.{conf,d/*}
        echo 'net.ipv6.conf.all.disable_ipv6 = 0' >/etc/sysctl.d/ipv6.conf
        sysctl -w net.ipv6.conf.all.disable_ipv6=0
    fi
}

Enable_WireGuard() {
    Enable_IPv6_Support
    Check_WireGuard
    if [[ ${WireGuard_SelfStart} = enabled ]]; then
        Restart_WireGuard
    else
        Start_WireGuard
    fi
}

Stop_WireGuard() {
    Check_WARP_Client
    if [[ ${WireGuard_Status} = active ]]; then
        log INFO "Stoping WireGuard..."
        if [[ ${WARP_Client_Status} = active ]]; then
            systemctl stop warp-svc
            systemctl stop wg-quick@${WireGuard_Interface}
            systemctl start warp-svc
        else
            systemctl stop wg-quick@${WireGuard_Interface}
        fi
        Check_WireGuard
        if [[ ${WireGuard_Status} != active ]]; then
            log INFO "WireGuard has been stopped."
        else
            log ERROR "WireGuard stop failure!"
        fi
    else
        log INFO "WireGuard is stopped."
    fi
}

Disable_WireGuard() {
    Check_WARP_Client
    Check_WireGuard
    if [[ ${WireGuard_SelfStart} = enabled || ${WireGuard_Status} = active ]]; then
        log INFO "Disabling WireGuard..."
        if [[ ${WARP_Client_Status} = active ]]; then
            systemctl stop warp-svc
            systemctl disable wg-quick@${WireGuard_Interface} --now
            systemctl start warp-svc
        else
            systemctl disable wg-quick@${WireGuard_Interface} --now
        fi
        Check_WireGuard
        if [[ ${WireGuard_SelfStart} != enabled && ${WireGuard_Status} != active ]]; then
            log INFO "WireGuard has been disabled."
        else
            log ERROR "WireGuard disable failure!"
        fi
    else
        log INFO "WireGuard is disabled."
    fi
}

Print_WireGuard_Log() {
    journalctl -u wg-quick@${WireGuard_Interface} -f
}

Check_Network_Status_IPv4() {
    if ping -c1 -W1 ${TestIPv4_1} >/dev/null 2>&1 || ping -c1 -W1 ${TestIPv4_2} >/dev/null 2>&1; then
        IPv4Status='on'
    else
        IPv4Status='off'
    fi
}

Check_Network_Status_IPv6() {
    if ping6 -c1 -W1 ${TestIPv6_1} >/dev/null 2>&1 || ping6 -c1 -W1 ${TestIPv6_2} >/dev/null 2>&1; then
        IPv6Status='on'
    else
        IPv6Status='off'
    fi
}

Check_Network_Status() {
    Disable_WireGuard
    Check_Network_Status_IPv4
    Check_Network_Status_IPv6
}

Check_IPv4_addr() {
    IPv4_addr=$(
        ip route get ${TestIPv4_1} 2>/dev/null | grep -oP 'src \K\S+' ||
            ip route get ${TestIPv4_2} 2>/dev/null | grep -oP 'src \K\S+'
    )
}

Check_IPv6_addr() {
    IPv6_addr=$(
        ip route get ${TestIPv6_1} 2>/dev/null | grep -oP 'src \K\S+' ||
            ip route get ${TestIPv6_2} 2>/dev/null | grep -oP 'src \K\S+'
    )
}

Get_IP_addr() {
    Check_Network_Status
    if [[ ${IPv4Status} = on ]]; then
        log INFO "Getting the network interface IPv4 address..."
        Check_IPv4_addr
        if [[ ${IPv4_addr} ]]; then
            log INFO "IPv4 Address: ${IPv4_addr}"
        else
            log WARN "Network interface IPv4 address not obtained."
        fi
    fi
    if [[ ${IPv6Status} = on ]]; then
        log INFO "Getting the network interface IPv6 address..."
        Check_IPv6_addr
        if [[ ${IPv6_addr} ]]; then
            log INFO "IPv6 Address: ${IPv6_addr}"
        else
            log WARN "Network interface IPv6 address not obtained."
        fi
    fi
}

Get_WireGuard_Interface_MTU() {
    log INFO "Getting the best MTU value for WireGuard..."
    MTU_Preset=1500
    MTU_Increment=10
    if [[ ${IPv4Status} = off && ${IPv6Status} = on ]]; then
        CMD_ping='ping6'
        MTU_TestIP_1="${TestIPv6_1}"
        MTU_TestIP_2="${TestIPv6_2}"
    else
        CMD_ping='ping'
        MTU_TestIP_1="${TestIPv4_1}"
        MTU_TestIP_2="${TestIPv4_2}"
    fi
    while true; do
        if ${CMD_ping} -c1 -W1 -s$((${MTU_Preset} - 28)) -Mdo ${MTU_TestIP_1} >/dev/null 2>&1 || ${CMD_ping} -c1 -W1 -s$((${MTU_Preset} - 28)) -Mdo ${MTU_TestIP_2} >/dev/null 2>&1; then
            MTU_Increment=1
            MTU_Preset=$((${MTU_Preset} + ${MTU_Increment}))
        else
            MTU_Preset=$((${MTU_Preset} - ${MTU_Increment}))
            if [[ ${MTU_Increment} = 1 ]]; then
                break
            fi
        fi
        if [[ ${MTU_Preset} -le 1360 ]]; then
            log WARN "MTU is set to the lowest value."
            MTU_Preset='1360'
            break
        fi
    done
    WireGuard_Interface_MTU=$((${MTU_Preset} - 80))
    log INFO "WireGuard MTU: ${WireGuard_Interface_MTU}"
}

Generate_WireGuardProfile_Interface() {
    Get_WireGuard_Interface_MTU
    log INFO "WireGuard profile (${WireGuard_ConfPath}) generation in progress..."
    cat <<EOF >${WireGuard_ConfPath}
# Generated by P3TERX/warp.sh
# Visit https://github.com/P3TERX/warp.sh for more information

[Interface]
PrivateKey = ${WireGuard_Interface_PrivateKey}
Address = ${WireGuard_Interface_Address}
DNS = ${WireGuard_Interface_DNS}
MTU = ${WireGuard_Interface_MTU}
EOF
}

Generate_WireGuardProfile_Interface_Rule_TableOff() {
    cat <<EOF >>${WireGuard_ConfPath}
Table = off
EOF
}

Generate_WireGuardProfile_Interface_Rule_IPv4_nonGlobal() {
    cat <<EOF >>${WireGuard_ConfPath}
PostUP = ip -4 route add default dev ${WireGuard_Interface} table ${WireGuard_Interface_Rule_table}
PostUP = ip -4 rule add from ${WireGuard_Interface_Address_IPv4} lookup ${WireGuard_Interface_Rule_table}
PostDown = ip -4 rule delete from ${WireGuard_Interface_Address_IPv4} lookup ${WireGuard_Interface_Rule_table}
PostUP = ip -4 rule add fwmark ${WireGuard_Interface_Rule_fwmark} lookup ${WireGuard_Interface_Rule_table}
PostDown = ip -4 rule delete fwmark ${WireGuard_Interface_Rule_fwmark} lookup ${WireGuard_Interface_Rule_table}
PostUP = ip -4 rule add table main suppress_prefixlength 0
PostDown = ip -4 rule delete table main suppress_prefixlength 0
EOF
}

Generate_WireGuardProfile_Interface_Rule_IPv6_nonGlobal() {
    cat <<EOF >>${WireGuard_ConfPath}
PostUP = ip -6 route add default dev ${WireGuard_Interface} table ${WireGuard_Interface_Rule_table}
PostUP = ip -6 rule add from ${WireGuard_Interface_Address_IPv6} lookup ${WireGuard_Interface_Rule_table}
PostDown = ip -6 rule delete from ${WireGuard_Interface_Address_IPv6} lookup ${WireGuard_Interface_Rule_table}
PostUP = ip -6 rule add fwmark ${WireGuard_Interface_Rule_fwmark} lookup ${WireGuard_Interface_Rule_table}
PostDown = ip -6 rule delete fwmark ${WireGuard_Interface_Rule_fwmark} lookup ${WireGuard_Interface_Rule_table}
PostUP = ip -6 rule add table main suppress_prefixlength 0
PostDown = ip -6 rule delete table main suppress_prefixlength 0
EOF
}

Generate_WireGuardProfile_Interface_Rule_DualStack_nonGlobal() {
    Generate_WireGuardProfile_Interface_Rule_TableOff
    Generate_WireGuardProfile_Interface_Rule_IPv4_nonGlobal
    Generate_WireGuardProfile_Interface_Rule_IPv6_nonGlobal
}

Generate_WireGuardProfile_Interface_Rule_IPv4_Global_srcIP() {
    cat <<EOF >>${WireGuard_ConfPath}
PostUp = ip -4 rule add from ${IPv4_addr} lookup main prio 18
PostDown = ip -4 rule delete from ${IPv4_addr} lookup main prio 18
EOF
}

Generate_WireGuardProfile_Interface_Rule_IPv6_Global_srcIP() {
    cat <<EOF >>${WireGuard_ConfPath}
PostUp = ip -6 rule add from ${IPv6_addr} lookup main prio 18
PostDown = ip -6 rule delete from ${IPv6_addr} lookup main prio 18
EOF
}

Generate_WireGuardProfile_Peer() {
    cat <<EOF >>${WireGuard_ConfPath}

[Peer]
PublicKey = ${WireGuard_Peer_PublicKey}
AllowedIPs = ${WireGuard_Peer_AllowedIPs}
Endpoint = ${WireGuard_Peer_Endpoint}
EOF
}

Check_WARP_Client_Status() {
    Check_WARP_Client
    case ${WARP_Client_Status} in
    active)
        WARP_Client_Status_en="${FontColor_Green}Running${FontColor_Suffix}"
        WARP_Client_Status_zh="${FontColor_Green}运行中${FontColor_Suffix}"
        ;;
    *)
        WARP_Client_Status_en="${FontColor_Red}Stopped${FontColor_Suffix}"
        WARP_Client_Status_zh="${FontColor_Red}未运行${FontColor_Suffix}"
        ;;
    esac
}

Check_WARP_Proxy_Status() {
    Check_WARP_Client
    Get_WARP_Upstream_Protocol
    if [[ ${WARP_Client_Status} = active ]]; then
        Get_WARP_Proxy_Port
        WARP_Proxy_Status=$(curl -sx "socks5h://127.0.0.1:${WARP_Proxy_Port}" ${CF_Trace_URL} --connect-timeout 2 | grep warp | cut -d= -f2)
        if [[ -z ${WARP_Proxy_Status} ]]; then
            WARP_Proxy_Status=$(curl -x "http://127.0.0.1:${WARP_Proxy_Port}" ${CF_Trace_URL} --connect-timeout 2 | grep warp | cut -d= -f2)
        fi
    else
        unset WARP_Proxy_Status
    fi
    case ${WARP_Proxy_Status} in
    on)
        WARP_Proxy_Status_en="${FontColor_Green}${WARP_Proxy_Port}${FontColor_Suffix}"
        WARP_Proxy_Status_zh="${WARP_Proxy_Status_en}"
        ;;
    plus)
        WARP_Proxy_Status_en="${FontColor_Green}${WARP_Proxy_Port}(WARP+)${FontColor_Suffix}"
        WARP_Proxy_Status_zh="${WARP_Proxy_Status_en}"
        ;;
    *)
        WARP_Proxy_Status_en="${FontColor_Red}Off${FontColor_Suffix}"
        WARP_Proxy_Status_zh="${FontColor_Red}未开启${FontColor_Suffix}"
        ;;
    esac
}

Check_WireGuard_Status() {
    Check_WireGuard
    case ${WireGuard_Status} in
    active)
        WireGuard_Status_en="${FontColor_Green}Running${FontColor_Suffix}"
        WireGuard_Status_zh="${FontColor_Green}运行中${FontColor_Suffix}"
        ;;
    *)
        WireGuard_Status_en="${FontColor_Red}Stopped${FontColor_Suffix}"
        WireGuard_Status_zh="${FontColor_Red}未运行${FontColor_Suffix}"
        ;;
    esac
}

Check_WARP_WireGuard_Status() {
    Check_Network_Status_IPv4
    if [[ ${IPv4Status} = on ]]; then
        WARP_IPv4_Status=$(curl -s4 ${CF_Trace_URL} --connect-timeout 2 | grep warp | cut -d= -f2)
    else
        unset WARP_IPv4_Status
    fi
    case ${WARP_IPv4_Status} in
    on)
        WARP_IPv4_Status_en="${FontColor_Green}WARP${FontColor_Suffix}"
        WARP_IPv4_Status_zh="${WARP_IPv4_Status_en}"
        ;;
    plus)
        WARP_IPv4_Status_en="${FontColor_Green}WARP+${FontColor_Suffix}"
        WARP_IPv4_Status_zh="${WARP_IPv4_Status_en}"
        ;;
    off)
        WARP_IPv4_Status_en="Normal"
        WARP_IPv4_Status_zh="正常"
        ;;
    *)
        Check_Network_Status_IPv4
        if [[ ${IPv4Status} = on ]]; then
            WARP_IPv4_Status_en="Normal"
            WARP_IPv4_Status_zh="正常"
        else
            WARP_IPv4_Status_en="${FontColor_Red}Unconnected${FontColor_Suffix}"
            WARP_IPv4_Status_zh="${FontColor_Red}未连接${FontColor_Suffix}"
        fi
        ;;
    esac
    Check_Network_Status_IPv6
    if [[ ${IPv6Status} = on ]]; then
        WARP_IPv6_Status=$(curl -s6 ${CF_Trace_URL} --connect-timeout 2 | grep warp | cut -d= -f2)
    else
        unset WARP_IPv6_Status
    fi
    case ${WARP_IPv6_Status} in
    on)
        WARP_IPv6_Status_en="${FontColor_Green}WARP${FontColor_Suffix}"
        WARP_IPv6_Status_zh="${WARP_IPv6_Status_en}"
        ;;
    plus)
        WARP_IPv6_Status_en="${FontColor_Green}WARP+${FontColor_Suffix}"
        WARP_IPv6_Status_zh="${WARP_IPv6_Status_en}"
        ;;
    off)
        WARP_IPv6_Status_en="Normal"
        WARP_IPv6_Status_zh="正常"
        ;;
    *)
        Check_Network_Status_IPv6
        if [[ ${IPv6Status} = on ]]; then
            WARP_IPv6_Status_en="Normal"
            WARP_IPv6_Status_zh="正常"
        else
            WARP_IPv6_Status_en="${FontColor_Red}Unconnected${FontColor_Suffix}"
            WARP_IPv6_Status_zh="${FontColor_Red}未连接${FontColor_Suffix}"
        fi
        ;;
    esac
    if [[ ${WireGuard_Status} = active && ${IPv4Status} = off && ${IPv6Status} = off ]]; then
        log ERROR "Cloudflare WARP network anomaly, WireGuard tunnel established failed."
        Disable_WireGuard
        exit 1
    fi
}

Check_ALL_Status() {
    Check_WARP_Client_Status
    Check_WARP_Proxy_Status
    Check_WireGuard_Status
    Check_WARP_WireGuard_Status
    Check_Usque_Status
}

Print_WARP_Client_Status() {
    log INFO "Status check in progress..."
    sleep 3
    Check_WARP_Client_Status
    Check_WARP_Proxy_Status
    echo -e "
 ----------------------------
 WARP Client\t: ${WARP_Client_Status_en}
 SOCKS5 Port (upstream: ${WARP_Upstream_Protocol_en})\t: ${WARP_Proxy_Status_en}
 ----------------------------
"
    log INFO "Done."
}

Print_WARP_WireGuard_Status() {
    log INFO "Status check in progress..."
    Check_WireGuard_Status
    Check_WARP_WireGuard_Status
    echo -e "
 ----------------------------
 WireGuard\t: ${WireGuard_Status_en}
 IPv4 Network\t: ${WARP_IPv4_Status_en}
 IPv6 Network\t: ${WARP_IPv6_Status_en}
 ----------------------------
"
    log INFO "Done."
}

Print_ALL_Status() {
    log INFO "Status check in progress..."
    Check_ALL_Status
    echo -e "
 ----------------------------
 WARP Client\t: ${WARP_Client_Status_en}
 SOCKS5 Port (upstream: ${WARP_Upstream_Protocol_en})\t: ${WARP_Proxy_Status_en}
 ----------------------------
 WireGuard\t: ${WireGuard_Status_en}
 IPv4 Network\t: ${WARP_IPv4_Status_en}
 IPv6 Network\t: ${WARP_IPv6_Status_en}
 ----------------------------
 usque\t\t: ${Usque_Status_en}
 SOCKS5 (upstream: HTTP/2 / TCP+TLS): ${Usque_Listen_Address_en}
 ----------------------------
"
}

View_WireGuard_Profile() {
    Print_Delimiter
    cat ${WireGuard_ConfPath}
    Print_Delimiter
}

Check_WireGuard_Peer_Endpoint() {
    if ping -c1 -W1 ${WireGuard_Peer_Endpoint_IP4} >/dev/null 2>&1; then
        WireGuard_Peer_Endpoint="${WireGuard_Peer_Endpoint_IPv4}"
    elif ping6 -c1 -W1 ${WireGuard_Peer_Endpoint_IP6} >/dev/null 2>&1; then
        WireGuard_Peer_Endpoint="${WireGuard_Peer_Endpoint_IPv6}"
    else
        WireGuard_Peer_Endpoint="${WireGuard_Peer_Endpoint_Domain}"
    fi
}

Set_WARP_IPv4() {
    Install_WireGuard
    Get_IP_addr
    Load_WGCF_Profile
    if [[ ${IPv4Status} = off && ${IPv6Status} = on ]]; then
        WireGuard_Interface_DNS="${WireGuard_Interface_DNS_64}"
    else
        WireGuard_Interface_DNS="${WireGuard_Interface_DNS_46}"
    fi
    WireGuard_Peer_AllowedIPs="${WireGuard_Peer_AllowedIPs_IPv4}"
    Check_WireGuard_Peer_Endpoint
    Generate_WireGuardProfile_Interface
    if [[ -n ${IPv4_addr} ]]; then
        Generate_WireGuardProfile_Interface_Rule_IPv4_Global_srcIP
    fi
    Generate_WireGuardProfile_Peer
    View_WireGuard_Profile
    Enable_WireGuard
    Print_WARP_WireGuard_Status
}

Set_WARP_IPv6() {
    Install_WireGuard
    Get_IP_addr
    Load_WGCF_Profile
    if [[ ${IPv4Status} = off && ${IPv6Status} = on ]]; then
        WireGuard_Interface_DNS="${WireGuard_Interface_DNS_64}"
    else
        WireGuard_Interface_DNS="${WireGuard_Interface_DNS_46}"
    fi
    WireGuard_Peer_AllowedIPs="${WireGuard_Peer_AllowedIPs_IPv6}"
    Check_WireGuard_Peer_Endpoint
    Generate_WireGuardProfile_Interface
    if [[ -n ${IPv6_addr} ]]; then
        Generate_WireGuardProfile_Interface_Rule_IPv6_Global_srcIP
    fi
    Generate_WireGuardProfile_Peer
    View_WireGuard_Profile
    Enable_WireGuard
    Print_WARP_WireGuard_Status
}

Set_WARP_DualStack() {
    Install_WireGuard
    Get_IP_addr
    Load_WGCF_Profile
    WireGuard_Interface_DNS="${WireGuard_Interface_DNS_46}"
    WireGuard_Peer_AllowedIPs="${WireGuard_Peer_AllowedIPs_DualStack}"
    Check_WireGuard_Peer_Endpoint
    Generate_WireGuardProfile_Interface
    if [[ -n ${IPv4_addr} ]]; then
        Generate_WireGuardProfile_Interface_Rule_IPv4_Global_srcIP
    fi
    if [[ -n ${IPv6_addr} ]]; then
        Generate_WireGuardProfile_Interface_Rule_IPv6_Global_srcIP
    fi
    Generate_WireGuardProfile_Peer
    View_WireGuard_Profile
    Enable_WireGuard
    Print_WARP_WireGuard_Status
}

Set_WARP_DualStack_nonGlobal() {
    Install_WireGuard
    Get_IP_addr
    Load_WGCF_Profile
    WireGuard_Interface_DNS="${WireGuard_Interface_DNS_46}"
    WireGuard_Peer_AllowedIPs="${WireGuard_Peer_AllowedIPs_DualStack}"
    Check_WireGuard_Peer_Endpoint
    Generate_WireGuardProfile_Interface
    Generate_WireGuardProfile_Interface_Rule_DualStack_nonGlobal
    Generate_WireGuardProfile_Peer
    View_WireGuard_Profile
    Enable_WireGuard
    Print_WARP_WireGuard_Status
}

Usque_Require_Command() {
    local command_name
    for command_name in "$@"; do
        if ! command -v "${command_name}" >/dev/null 2>&1; then
            log ERROR "Required command is not installed: ${command_name}"
            return 1
        fi
    done
}

Usque_Require_Systemd() {
    Usque_Require_Command systemctl || return 1
    if ! systemctl show --property=Version --value >/dev/null 2>&1; then
        log ERROR "A running systemd instance is required for usque."
        return 1
    fi
}

Validate_Usque_Settings() {
    local bind="${1-${Usque_Bind}}" port="${2-${Usque_Port}}" octet
    local -a octets
    if [[ ! ${bind} =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
        log ERROR "usque bind address must be an IPv4 address."
        return 1
    fi
    IFS=. read -r -a octets <<< "${bind}"
    for octet in "${octets[@]}"; do
        if (( 10#${octet} > 255 )) || [[ ${octet} != 0 && ${octet} = 0* ]]; then
            log ERROR "Invalid usque IPv4 address: ${bind}"
            return 1
        fi
    done
    if [[ ! ${port} =~ ^[0-9]{1,5}$ ]] || (( 10#${port} < 1 || 10#${port} > 65535 )); then
        log ERROR "usque port must be between 1 and 65535."
        return 1
    fi
}

Load_Usque_Settings() {
    local bind='127.0.0.1' port='40000' line seen_bind=0 seen_port=0
    if [[ -e ${Usque_SettingsPath} || -L ${Usque_SettingsPath} ]]; then
        if [[ ! -f ${Usque_SettingsPath} || ! -r ${Usque_SettingsPath} || -L ${Usque_SettingsPath} ]]; then
            log ERROR "Cannot read usque settings: ${Usque_SettingsPath}"
            return 1
        fi
        while IFS= read -r line || [[ -n ${line} ]]; do
            case "${line}" in
            '' | \#*) ;;
            bind=*)
                (( seen_bind == 0 )) || return 1
                bind="${line#bind=}"
                seen_bind=1
                ;;
            port=*)
                (( seen_port == 0 )) || return 1
                port="${line#port=}"
                seen_port=1
                ;;
            *)
                log ERROR "Invalid usque settings; only bind and port are supported."
                return 1
                ;;
            esac
        done < "${Usque_SettingsPath}"
    fi
    Validate_Usque_Settings "${bind}" "${port}" || return 1
    Usque_Bind="${bind}"
    Usque_Port="$((10#${port}))"
}

Check_Usque_Port() {
    local port="${1:-${Usque_Port}}" allow_self="${2:-no}" listeners line main_pid=''
    Usque_Require_Command ss || return 1
    if ! listeners=$(ss -H -ltnp "sport = :${port}" 2>/dev/null); then
        log ERROR "Failed to inspect TCP listening ports."
        return 1
    fi
    [[ -z ${listeners} ]] && return 0
    if [[ ${allow_self} = yes ]]; then
        main_pid=$(systemctl show "${Usque_Service}" --property=MainPID --value 2>/dev/null)
    fi
    while IFS= read -r line; do
        if [[ ${main_pid} =~ ^[1-9][0-9]*$ && ${line} = *"pid=${main_pid},"* ]]; then
            continue
        fi
        log ERROR "TCP port ${port} is already in use by another process."
        return 1
    done <<< "${listeners}"
}

Write_Usque_Service() {
    local unit_tmp
    unit_tmp=$(mktemp "${Usque_ServicePath}.XXXXXX") || return 1
    if ! cat > "${unit_tmp}" <<EOF
[Unit]
Description=usque Cloudflare WARP SOCKS5 proxy (HTTP/2)
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
UMask=0077
Environment="HTTP_PROXY=" "HTTPS_PROXY=" "ALL_PROXY=" "http_proxy=" "https_proxy=" "all_proxy="
ExecStart="${Usque_BinPath}" -c "${Usque_ConfigPath}" socks --http2 --always-reconnect -b ${Usque_Bind} -p ${Usque_Port}
Restart=on-failure
RestartSec=5
TimeoutStartSec=20
TimeoutStopSec=15

[Install]
WantedBy=multi-user.target
EOF
    then
        rm -f "${unit_tmp}"
        return 1
    fi
    if ! chmod 644 "${unit_tmp}" || ! mv -f "${unit_tmp}" "${Usque_ServicePath}"; then
        rm -f "${unit_tmp}"
        return 1
    fi
}

Wait_Usque_Proxy() {
    local attempt listeners main_pid
    for (( attempt=0; attempt<10; attempt++ )); do
        if systemctl is-active --quiet "${Usque_Service}"; then
            main_pid=$(systemctl show "${Usque_Service}" --property=MainPID --value 2>/dev/null)
            listeners=$(ss -H -ltnp "sport = :${Usque_Port}" 2>/dev/null) || return 1
            if [[ ${main_pid} =~ ^[1-9][0-9]*$ && ${listeners} = *"pid=${main_pid},"* ]]; then
                return 0
            fi
        fi
        sleep 1
    done
    log ERROR "usque failed to listen on ${Usque_Bind}:${Usque_Port}; check the service logs in menu 9, option 7."
    return 1
}

Install_Usque() {
    local arch tag release asset staging checksum actual running=no
    Usque_Require_Systemd || return 1
    Usque_Require_Command curl unzip sha256sum ss install mktemp || return 1
    case $(uname -m) in
    x86_64 | amd64) arch='amd64' ;;
    aarch64 | arm64) arch='arm64' ;;
    armv5*) arch='armv5' ;;
    armv6*) arch='armv6' ;;
    armv7* | armv8l) arch='armv7' ;;
    *) log ERROR "Unsupported usque CPU architecture: $(uname -m)"; return 1 ;;
    esac
    if ! release=$(curl -fsSL --connect-timeout 10 --max-time 60 'https://api.github.com/repos/Diniboy1123/usque/releases/latest'); then
        log ERROR "Failed to find the latest stable usque release."
        return 1
    fi
    tag=$(printf '%s\n' "${release}" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
    if [[ ! ${tag} =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log ERROR "Invalid stable usque release version."
        return 1
    fi
    asset="usque_${tag#v}_linux_${arch}.zip"
    install -d -m 755 "$(dirname "${Usque_BinPath}")" || return 1
    staging=$(mktemp -d "${Usque_BinPath}.install.XXXXXX") || return 1
    if ! curl -fsSL --connect-timeout 10 --max-time 60 -o "${staging}/${asset}" "https://github.com/Diniboy1123/usque/releases/download/${tag}/${asset}" ||
        ! curl -fsSL --connect-timeout 10 --max-time 60 -o "${staging}/checksums.txt" "https://github.com/Diniboy1123/usque/releases/download/${tag}/checksums.txt"; then
        log ERROR "Failed to download usque; the installed binary was preserved."
        rm -rf "${staging}"
        return 1
    fi
    checksum=$(awk -v name="${asset}" '$2 == name || $2 == "*" name {print $1}' "${staging}/checksums.txt")
    actual=$(sha256sum "${staging}/${asset}") || actual=''
    actual="${actual%% *}"
    if [[ ! ${checksum} =~ ^[0-9a-fA-F]{64}$ || ${actual,,} != "${checksum,,}" ]]; then
        log ERROR "usque SHA256 verification failed; the installed binary was preserved."
        rm -rf "${staging}"
        return 1
    fi
    if ! unzip -p "${staging}/${asset}" usque > "${staging}/usque" ||
        [[ ! -s ${staging}/usque ]] || ! chmod 755 "${staging}/usque" ||
        ! "${staging}/usque" -c /dev/null version >/dev/null 2>&1; then
        log ERROR "Failed to extract or execute usque; the installed binary was preserved."
        rm -rf "${staging}"
        return 1
    fi
    if systemctl is-active --quiet "${Usque_Service}"; then
        running=yes
        Load_Usque_Settings || { rm -rf "${staging}"; return 1; }
    fi
    if [[ -e ${Usque_BinPath} ]]; then
        if [[ ! -f ${Usque_BinPath} || -L ${Usque_BinPath} ]] || ! cp -p "${Usque_BinPath}" "${staging}/previous"; then
            log ERROR "Cannot back up the installed usque binary."
            rm -rf "${staging}"
            return 1
        fi
    elif [[ ${running} = yes ]]; then
        log ERROR "Cannot update a running usque service without its original binary."
        rm -rf "${staging}"
        return 1
    fi
    if ! mv -f "${staging}/usque" "${Usque_BinPath}"; then
        rm -rf "${staging}"
        return 1
    fi
    if [[ ${running} = yes ]] && { ! systemctl restart "${Usque_Service}" || ! Wait_Usque_Proxy; }; then
        log ERROR "The updated usque failed to start; restoring the previous binary."
        if ! mv -f "${staging}/previous" "${Usque_BinPath}"; then
            log ERROR "Failed to restore the previous binary; backup retained at ${staging}/previous."
            return 1
        fi
        if ! systemctl restart "${Usque_Service}" || ! Wait_Usque_Proxy; then
            log ERROR "Failed to restart the restored usque binary."
        fi
        rm -rf "${staging}"
        return 1
    fi
    rm -rf "${staging}"
    log INFO "usque ${tag} installed successfully."
}

Prepare_Usque_Config() {
    local output
    install -d -m 700 "${Usque_ConfigDir}" || return 1
    if [[ ! -e ${Usque_ConfigPath} && ! -L ${Usque_ConfigPath} ]]; then
        if [[ -e ./config.json ]]; then
            if [[ ! -f ./config.json || ! -s ./config.json ]] || ! install -m 600 ./config.json "${Usque_ConfigPath}"; then
                log ERROR "Failed to import config.json; fix the existing account file before retrying."
                return 1
            fi
        else
            Usque_Require_Command timeout env || return 1
            log INFO "Registering a new usque account and accepting Cloudflare's terms of service..."
            if ! (umask 077; timeout 90 env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u http_proxy -u https_proxy -u all_proxy "${Usque_BinPath}" -c "${Usque_ConfigPath}" register --accept-tos >/dev/null 2>&1); then
                log ERROR "usque account registration failed. Any generated account file has been preserved."
                return 1
            fi
        fi
    fi
    if [[ ! -f ${Usque_ConfigPath} || ! -s ${Usque_ConfigPath} || -L ${Usque_ConfigPath} ]]; then
        log ERROR "The existing usque account file is invalid; it was preserved for manual repair."
        return 1
    fi
    chmod 600 "${Usque_ConfigPath}" || return 1
    # The version command runs upstream's config loader without starting a tunnel.
    output=$("${Usque_BinPath}" -c "${Usque_ConfigPath}" version 2>&1) || return 1
    if [[ ${output} = *'Config file not found:'* ]]; then
        log ERROR "Cannot parse the existing usque account file; it was preserved for manual repair."
        return 1
    fi
}

Enable_Usque_Proxy() {
    Usque_Require_Systemd || return 1
    Usque_Require_Command ss install mktemp || return 1
    Load_Usque_Settings || return 1
    if systemctl is-active --quiet "${Usque_Service}"; then
        Check_Usque_Port "${Usque_Port}" yes || return 1
        Wait_Usque_Proxy || return 1
        systemctl enable "${Usque_Service}" || return 1
        log INFO "usque is already running at ${Usque_Bind}:${Usque_Port}."
        return 0
    fi
    [[ -x ${Usque_BinPath} ]] || Install_Usque || return 1
    Check_Usque_Port || return 1
    Prepare_Usque_Config || return 1
    if [[ ! -e ${Usque_SettingsPath} ]]; then
        (umask 077; printf 'bind=%s\nport=%s\n' "${Usque_Bind}" "${Usque_Port}" > "${Usque_SettingsPath}") || return 1
    fi
    if ! Write_Usque_Service || ! systemctl daemon-reload ||
        ! systemctl enable --now "${Usque_Service}" || ! Wait_Usque_Proxy; then
        log ERROR "Failed to enable usque SOCKS5 proxy."
        return 1
    fi
    log INFO "usque SOCKS5 proxy enabled at ${Usque_Bind}:${Usque_Port} (HTTP/2)."
}

Disable_Usque_Proxy() {
    local load_state
    Usque_Require_Systemd || return 1
    load_state=$(systemctl show "${Usque_Service}" --property=LoadState --value) || return 1
    if [[ ${load_state} = not-found ]]; then
        log INFO "usque service is not installed."
        return 0
    fi
    if ! systemctl disable --now "${Usque_Service}"; then
        log ERROR "Failed to stop and disable usque."
        return 1
    fi
    log INFO "usque stopped and disabled. Account and proxy settings were preserved."
}

Restart_Usque_Proxy() {
    Usque_Require_Systemd || return 1
    Usque_Require_Command ss || return 1
    Load_Usque_Settings || return 1
    [[ -x ${Usque_BinPath} ]] || { log ERROR "usque is not installed."; return 1; }
    Check_Usque_Port "${Usque_Port}" yes || return 1
    if ! systemctl restart "${Usque_Service}" || ! Wait_Usque_Proxy; then
        log ERROR "Failed to restart usque."
        return 1
    fi
    log INFO "usque SOCKS5 proxy restarted."
}

Configure_Usque_Proxy() {
    local bind port previous_bind previous_port backup running=no had_settings=no had_unit=no failed=no restore_failed=no
    Usque_Require_Systemd || return 1
    Usque_Require_Command ss install mktemp || return 1
    Load_Usque_Settings || return 1
    previous_bind="${Usque_Bind}"
    previous_port="${Usque_Port}"
    if (( $# == 0 )); then
        read -r -p "监听 IPv4 地址 [${Usque_Bind}]: " bind || return 1
        read -r -p "SOCKS5 端口（上游：HTTP/2 / TCP+TLS）[${Usque_Port}]: " port || return 1
    else
        bind="$1"
        port="${2:-${Usque_Port}}"
    fi
    bind="${bind:-${Usque_Bind}}"
    port="${port:-${Usque_Port}}"
    Validate_Usque_Settings "${bind}" "${port}" || return 1
    port="$((10#${port}))"
    if systemctl is-active --quiet "${Usque_Service}"; then running=yes; fi
    Check_Usque_Port "${port}" "${running}" || return 1
    install -d -m 700 "${Usque_ConfigDir}" || return 1
    backup=$(mktemp -d "${Usque_ConfigDir}/.proxy.XXXXXX") || return 1
    if [[ -e ${Usque_SettingsPath} ]]; then
        had_settings=yes
        cp -p "${Usque_SettingsPath}" "${backup}/proxy.conf" || { rm -rf "${backup}"; return 1; }
    fi
    if [[ -e ${Usque_ServicePath} ]]; then
        had_unit=yes
        cp -p "${Usque_ServicePath}" "${backup}/service" || { rm -rf "${backup}"; return 1; }
    fi
    Usque_Bind="${bind}"
    Usque_Port="${port}"
    if ! (umask 077; printf 'bind=%s\nport=%s\n' "${bind}" "${port}" > "${backup}/new.conf") ||
        ! mv -f "${backup}/new.conf" "${Usque_SettingsPath}" ||
        ! Write_Usque_Service || ! systemctl daemon-reload; then
        failed=yes
    elif [[ ${running} = yes ]] && { ! systemctl restart "${Usque_Service}" || ! Wait_Usque_Proxy; }; then
        failed=yes
    fi
    if [[ ${failed} = yes ]]; then
        Usque_Bind="${previous_bind}"
        Usque_Port="${previous_port}"
        if [[ ${had_settings} = yes ]]; then
            cp -p "${backup}/proxy.conf" "${Usque_SettingsPath}" || restore_failed=yes
        else
            rm -f "${Usque_SettingsPath}" || restore_failed=yes
        fi
        if [[ ${had_unit} = yes ]]; then
            cp -p "${backup}/service" "${Usque_ServicePath}" || restore_failed=yes
        else
            rm -f "${Usque_ServicePath}" || restore_failed=yes
        fi
        if [[ ${restore_failed} = yes ]]; then
            log ERROR "Failed to restore configuration files; backups retained in ${backup}."
            return 1
        fi
        if ! systemctl daemon-reload || { [[ ${running} = yes ]] && { ! systemctl restart "${Usque_Service}" || ! Wait_Usque_Proxy; }; }; then
            log ERROR "Configuration restored, but the previous usque service could not be restarted."
            rm -rf "${backup}"
            return 1
        fi
        rm -rf "${backup}"
        log ERROR "Failed to apply usque settings; the previous configuration was restored."
        return 1
    fi
    rm -rf "${backup}"
    log INFO "usque proxy configured at ${Usque_Bind}:${Usque_Port}."
}

Test_Usque_Proxy() {
    local trace bind
    Usque_Require_Systemd || return 1
    Usque_Require_Command curl ss || return 1
    Load_Usque_Settings || return 1
    if ! systemctl is-active --quiet "${Usque_Service}"; then
        log ERROR "usque is not running; enable it before testing the proxy."
        return 1
    fi
    Check_Usque_Port "${Usque_Port}" yes || return 1
    Wait_Usque_Proxy || return 1
    bind="${Usque_Bind}"
    [[ ${bind} = 0.0.0.0 ]] && bind='127.0.0.1'
    if ! trace=$(curl -fsS --noproxy '' --proxy "socks5h://${bind}:${Usque_Port}" --connect-timeout 5 --max-time 15 "${CF_Trace_URL}"); then
        log ERROR "Failed to connect through the usque SOCKS5 proxy."
        return 1
    fi
    if ! printf '%s\n' "${trace}" | grep -qE '^warp=(on|plus)$'; then
        log ERROR "usque proxy did not return an active WARP trace."
        return 1
    fi
    printf '%s\n' "${trace}"
    log INFO "usque SOCKS5 proxy test passed."
}

Print_Usque_Log() {
    Usque_Require_Command journalctl || return 1
    journalctl -u "${Usque_Service}" -n 80 --no-pager
}

Uninstall_Usque() {
    Disable_Usque_Proxy || return 1
    if ! rm -f "${Usque_BinPath}" "${Usque_ServicePath}" || ! systemctl daemon-reload; then
        log ERROR "Failed to uninstall usque."
        return 1
    fi
    systemctl reset-failed "${Usque_Service}" >/dev/null 2>&1 || true
    log INFO "usque uninstalled. Account and proxy settings remain in ${Usque_ConfigDir}."
}

Check_Usque_Status() {
    local enabled output
    Usque_Status='not-installed'
    Usque_Status_zh='未安装'
    Usque_Status_en='Not installed'
    Usque_Version='-'
    Usque_SelfStart_zh='未启用'
    Usque_SelfStart_en='Disabled'
    Usque_Listen_Address_zh='配置异常（请检查 proxy.conf）'
    Usque_Listen_Address_en='Invalid proxy.conf'
    if Load_Usque_Settings; then
        Usque_Listen_Address_zh="socks5://${Usque_Bind}:${Usque_Port}"
        Usque_Listen_Address_en="${Usque_Listen_Address_zh}"
    fi
    if [[ -x ${Usque_BinPath} ]]; then
        output=$("${Usque_BinPath}" -c /dev/null version 2>/dev/null)
        Usque_Version=$(printf '%s\n' "${output}" | sed -n 's/^usque version: //p' | head -n 1)
        Usque_Version="${Usque_Version:--}"
        Usque_Status='inactive'
        Usque_Status_zh='未运行'
        Usque_Status_en='Stopped'
    fi
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl is-active --quiet "${Usque_Service}"; then
            Usque_Status='active'
            Usque_Status_zh='运行中'
            Usque_Status_en='Running'
        elif systemctl is-failed --quiet "${Usque_Service}"; then
            Usque_Status='failed'
            Usque_Status_zh='启动失败'
            Usque_Status_en='Failed'
        fi
        enabled=$(systemctl is-enabled "${Usque_Service}" 2>/dev/null)
        if [[ ${enabled} = enabled ]]; then
            Usque_SelfStart_zh='已启用'
            Usque_SelfStart_en='Enabled'
        fi
    fi
}

Menu_Title="${FontColor_Yellow_Bold}Cloudflare WARP 一键安装脚本${FontColor_Suffix} ${FontColor_Red}[${shVersion}]${FontColor_Suffix} by ${FontColor_Purple_Bold}P3TERX.COM${FontColor_Suffix}"

Menu_WARP_Client() {
    Check_WARP_Client
    Get_WARP_Upstream_Protocol
    clear
    echo -e "
${Menu_Title}

 -------------------------
 WARP 客户端状态 : ${WARP_Client_Status_zh}
 SOCKS5 代理端口（上游：${WARP_Upstream_Protocol_zh}）: ${WARP_Proxy_Status_zh}
 -------------------------

管理 WARP 官方客户端：

 ${FontColor_Green_Bold}0${FontColor_Suffix}. 返回主菜单
 -
 ${FontColor_Green_Bold}1${FontColor_Suffix}. 开启 SOCKS5 代理（上游：${WARP_Upstream_Protocol_zh}）
 ${FontColor_Green_Bold}2${FontColor_Suffix}. 关闭 SOCKS5 代理（上游：${WARP_Upstream_Protocol_zh}）
 ${FontColor_Green_Bold}3${FontColor_Suffix}. 重启 WARP 官方客户端
 ${FontColor_Green_Bold}4${FontColor_Suffix}. 卸载 WARP 官方客户端
 ${FontColor_Green_Bold}5${FontColor_Suffix}. 关闭 WARP 官方客户端（保留配置，禁用开机启动）
"
    unset MenuNumber
    read -p "请输入选项: " MenuNumber
    echo
    case ${MenuNumber} in
    0)
        Start_Menu
        ;;
    1)
        Enable_WARP_Client_Proxy
        ;;
    2)
        Disconnect_WARP
        ;;
    3)
        Restart_WARP_Client
        ;;
    4)
        Uninstall_WARP_Client
        ;;
    5)
        Disable_WARP_Client
        ;;
    *)
        log ERROR "无效输入！"
        sleep 2s
        Menu_WARP_Client
        ;;
    esac
}

Menu_WARP_WireGuard() {
    clear
    echo -e "
${Menu_Title}

 -------------------------
 WireGuard 状态 : ${WireGuard_Status_zh}
 IPv4 网络状态  : ${WARP_IPv4_Status_zh}
 IPv6 网络状态  : ${WARP_IPv6_Status_zh}
 -------------------------

管理 WARP WireGuard：

 ${FontColor_Green_Bold}0${FontColor_Suffix}. 返回主菜单
 -
 ${FontColor_Green_Bold}1${FontColor_Suffix}. 查看 WARP WireGuard 日志
 ${FontColor_Green_Bold}2${FontColor_Suffix}. 重启 WARP WireGuard 服务
 ${FontColor_Green_Bold}3${FontColor_Suffix}. 关闭 WARP WireGuard 网络
"
    unset MenuNumber
    read -p "请输入选项: " MenuNumber
    echo
    case ${MenuNumber} in
    0)
        Start_Menu
        ;;
    1)
        Print_WireGuard_Log
        ;;
    2)
        Restart_WireGuard
        ;;
    3)
        Disable_WireGuard
        ;;
    *)
        log ERROR "无效输入！"
        sleep 2s
        Menu_Other
        ;;
    esac
}

Menu_Usque() {
    local choice
    Check_Usque_Status || return 1
    clear
    echo -e "
${Menu_Title}

管理 usque（WARP 代理）：

 -------------------------
 usque 版本    : ${Usque_Version}
 服务状态     : ${Usque_Status_zh}
 SOCKS5 地址（上游：HTTP/2 / TCP+TLS）: ${Usque_Listen_Address_zh}
 开机启动     : ${Usque_SelfStart_zh}
 账户配置     : ${Usque_ConfigPath}
 -------------------------

 ${FontColor_Green_Bold}0${FontColor_Suffix}. 返回主菜单
 -
 ${FontColor_Green_Bold}1${FontColor_Suffix}. 安装或更新 usque
 ${FontColor_Green_Bold}2${FontColor_Suffix}. 开启 SOCKS5 代理（上游：HTTP/2 / TCP+TLS）
 ${FontColor_Green_Bold}3${FontColor_Suffix}. 关闭 SOCKS5 代理（上游：HTTP/2 / TCP+TLS）
 ${FontColor_Green_Bold}4${FontColor_Suffix}. 重启 SOCKS5 代理（上游：HTTP/2 / TCP+TLS）
 ${FontColor_Green_Bold}5${FontColor_Suffix}. 修改监听地址和端口
 ${FontColor_Green_Bold}6${FontColor_Suffix}. 检查代理连通性
 ${FontColor_Green_Bold}7${FontColor_Suffix}. 查看服务日志
 ${FontColor_Green_Bold}8${FontColor_Suffix}. 卸载 usque（保留账户配置）
"
    read -rp "请输入选项: " choice || return 1
    echo
    case ${choice} in
    0) Start_Menu ;;
    1) Install_Usque ;;
    2) Enable_Usque_Proxy ;;
    3) Disable_Usque_Proxy ;;
    4) Restart_Usque_Proxy ;;
    5) Configure_Usque_Proxy ;;
    6) Test_Usque_Proxy ;;
    7) Print_Usque_Log ;;
    8) Uninstall_Usque ;;
    *) log ERROR "无效输入！"; return 1 ;;
    esac
}

Start_Menu() {
    log INFO "正在检查状态..."
    Check_ALL_Status
    clear
    echo -e "
${Menu_Title}

 -------------------------
 WARP 客户端状态 : ${WARP_Client_Status_zh}
 SOCKS5 代理端口（上游：${WARP_Upstream_Protocol_zh}）: ${WARP_Proxy_Status_zh}
 -------------------------
 WireGuard 状态 : ${WireGuard_Status_zh}
 IPv4 网络状态  : ${WARP_IPv4_Status_zh}
 IPv6 网络状态  : ${WARP_IPv6_Status_zh}
 -------------------------

 ${FontColor_Green_Bold}1${FontColor_Suffix}. 安装 Cloudflare WARP 官方客户端
 ${FontColor_Green_Bold}2${FontColor_Suffix}. 自动配置 WARP 客户端 SOCKS5 代理（上游：${WARP_Upstream_Protocol_zh}）
 ${FontColor_Green_Bold}3${FontColor_Suffix}. 管理 Cloudflare WARP 官方客户端
 -
 ${FontColor_Green_Bold}4${FontColor_Suffix}. 安装 WireGuard 相关组件
 ${FontColor_Green_Bold}5${FontColor_Suffix}. 自动配置 WARP WireGuard IPv4 网络
 ${FontColor_Green_Bold}6${FontColor_Suffix}. 自动配置 WARP WireGuard IPv6 网络
 ${FontColor_Green_Bold}7${FontColor_Suffix}. 自动配置 WARP WireGuard 双栈全局网络
 ${FontColor_Green_Bold}8${FontColor_Suffix}. 管理 WARP WireGuard 网络
 -
 ${FontColor_Green_Bold}9${FontColor_Suffix}. 管理 usque（WARP 代理）
"
    unset MenuNumber
    read -p "请输入选项: " MenuNumber
    echo
    case ${MenuNumber} in
    1)
        Install_WARP_Client
        ;;
    2)
        Enable_WARP_Client_Proxy
        ;;
    3)
        Menu_WARP_Client
        ;;
    4)
        Install_WireGuard
        ;;
    5)
        Set_WARP_IPv4
        ;;
    6)
        Set_WARP_IPv6
        ;;
    7)
        Set_WARP_DualStack
        ;;
    8)
        Menu_WARP_WireGuard
        ;;
    9)
        Menu_Usque
        ;;
    *)
        log ERROR "无效输入！"
        sleep 2s
        Start_Menu
        ;;
    esac
}

Print_Usage() {
    echo -e "
Cloudflare WARP Installer [${shVersion}]

USAGE:
    bash <(curl -fsSL git.io/warp.sh) [SUBCOMMAND]

SUBCOMMANDS:
    install         Install Cloudflare WARP Official Linux Client
    uninstall       uninstall Cloudflare WARP Official Linux Client
    restart         Restart Cloudflare WARP Official Linux Client
    proxy           Enable WARP Client SOCKS5 Proxy (upstream: client tunnel protocol; port: 40000)
    unproxy         Disable WARP Client Proxy Mode
    wg              Install WireGuard and related components
    wg4             Configuration WARP IPv4 Global Network (with WireGuard), all IPv4 outbound data over the WARP network
    wg6             Configuration WARP IPv6 Global Network (with WireGuard), all IPv6 outbound data over the WARP network
    wgd             Configuration WARP Dual Stack Global Network (with WireGuard), all outbound data over the WARP network
    wgx             Configuration WARP Non-Global Network (with WireGuard), set fwmark or interface IP Address to use the WARP network
    rwg             Restart WARP WireGuard service
    dwg             Disable WARP WireGuard service
    status          Prints status information
    version         Prints version information
    help            Prints this message or the help of the given subcommand(s)
    menu            Chinese management menu, including usque SOCKS5 (upstream: HTTP/2 / TCP+TLS)
"
}

cat <<-'EOM'

[0;1;35;95m__[0m        [0;1;34;94m__[0;1;35;95m_[0m    [0;1;33;93m_[0;1;32;92m__[0;1;36;96m_[0m  [0;1;34;94m_[0;1;35;95m__[0;1;31;91m_[0m    [0;1;32;92m_[0;1;36;96m__[0m           [0;1;36;96m_[0m        [0;1;32;92m_[0m [0;1;36;96m_[0m           
[0;1;31;91m\[0m [0;1;33;93m\[0m      [0;1;34;94m/[0m [0;1;35;95m/[0m [0;1;31;91m\[0m  [0;1;32;92m|[0m  [0;1;36;96m_[0m [0;1;34;94m\[0;1;35;95m|[0m  [0;1;31;91m_[0m [0;1;33;93m\[0m  [0;1;36;96m|_[0m [0;1;34;94m_[0;1;35;95m|_[0m [0;1;31;91m_[0;1;33;93m_[0m  [0;1;32;92m_[0;1;36;96m__[0;1;34;94m|[0m [0;1;35;95m|_[0m [0;1;31;91m_[0;1;33;93m_[0m [0;1;32;92m_|[0m [0;1;36;96m|[0m [0;1;34;94m|[0m [0;1;35;95m_[0;1;31;91m__[0m [0;1;33;93m_[0m [0;1;32;92m_[0;1;36;96m_[0m 
 [0;1;33;93m\[0m [0;1;32;92m\[0m [0;1;36;96m/[0;1;34;94m\[0m [0;1;35;95m/[0m [0;1;31;91m/[0m [0;1;33;93m_[0m [0;1;32;92m\[0m [0;1;36;96m|[0m [0;1;34;94m|_[0;1;35;95m)[0m [0;1;31;91m|[0m [0;1;33;93m|_[0;1;32;92m)[0m [0;1;36;96m|[0m  [0;1;34;94m|[0m [0;1;35;95m|[0;1;31;91m|[0m [0;1;33;93m'_[0m [0;1;32;92m\[0;1;36;96m/[0m [0;1;34;94m__[0;1;35;95m|[0m [0;1;31;91m__[0;1;33;93m/[0m [0;1;32;92m_`[0m [0;1;36;96m|[0m [0;1;34;94m|[0m [0;1;35;95m|[0;1;31;91m/[0m [0;1;33;93m_[0m [0;1;32;92m\[0m [0;1;36;96m'_[0;1;34;94m_|[0m
  [0;1;36;96m\[0m [0;1;34;94mV[0m  [0;1;35;95mV[0m [0;1;31;91m/[0m [0;1;33;93m_[0;1;32;92m__[0m [0;1;36;96m\[0;1;34;94m|[0m  [0;1;35;95m_[0m [0;1;31;91m<[0;1;33;93m|[0m  [0;1;32;92m_[0;1;36;96m_/[0m   [0;1;35;95m|[0m [0;1;31;91m|[0;1;33;93m|[0m [0;1;32;92m|[0m [0;1;36;96m|[0m [0;1;34;94m\_[0;1;35;95m_[0m [0;1;31;91m\[0m [0;1;33;93m||[0m [0;1;32;92m([0;1;36;96m_|[0m [0;1;34;94m|[0m [0;1;35;95m|[0m [0;1;31;91m|[0m  [0;1;32;92m__[0;1;36;96m/[0m [0;1;34;94m|[0m   
   [0;1;34;94m\[0;1;35;95m_/[0;1;31;91m\_[0;1;33;93m/_[0;1;32;92m/[0m   [0;1;34;94m\_[0;1;35;95m\_[0;1;31;91m|[0m [0;1;33;93m\_[0;1;32;92m\_[0;1;36;96m|[0m     [0;1;31;91m|_[0;1;33;93m__[0;1;32;92m|_[0;1;36;96m|[0m [0;1;34;94m|_[0;1;35;95m|_[0;1;31;91m__[0;1;33;93m/\[0;1;32;92m__[0;1;36;96m\_[0;1;34;94m_,[0;1;35;95m_|[0;1;31;91m_|[0;1;33;93m_|[0;1;32;92m\_[0;1;36;96m__[0;1;34;94m|_[0;1;35;95m|[0m   
                                                                    
Copyright (C) P3TERX.COM | https://github.com/P3TERX/warp.sh

EOM

if [ $# -ge 1 ]; then
    Get_System_Info
    case ${1} in
    install)
        Install_WARP_Client
        ;;
    uninstall)
        Uninstall_WARP_Client
        ;;
    restart)
        Restart_WARP_Client
        ;;
    proxy | socks5 | s5)
        Enable_WARP_Client_Proxy
        ;;
    unproxy | unsocks5 | uns5)
        Disconnect_WARP
        ;;
    wg)
        Install_WireGuard
        ;;
    wg4 | 4)
        Set_WARP_IPv4
        ;;
    wg6 | 6)
        Set_WARP_IPv6
        ;;
    wgd | d)
        Set_WARP_DualStack
        ;;
    wgx | x)
        Set_WARP_DualStack_nonGlobal
        ;;
    rwg)
        Restart_WireGuard
        ;;
    dwg)
        Disable_WireGuard
        ;;
    status)
        Print_ALL_Status
        ;;
    help)
        Print_Usage
        ;;
    version)
        echo "${shVersion}"
        ;;
    menu)
        Start_Menu
        ;;
    *)
        log ERROR "Invalid Parameters: $*"
        Print_Usage
        exit 1
        ;;
    esac
else
    Print_Usage
fi
