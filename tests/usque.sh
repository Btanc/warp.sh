#!/usr/bin/env bash
# Isolated regression tests: never source the installer's top-level code.
set -u
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SUITE=$(mktemp -d)
trap 'rm -rf -- "$SUITE"' EXIT
awk '/^[[:alnum:]_]+\(\) \{$/ { copying=1 } copying { print } /^\}$/ { copying=0 }' \
    < <(tr -d '\r' < "${WARP_TEST_SCRIPT:-$ROOT/warp.sh}") > "$SUITE/functions.sh"
source "$SUITE/functions.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_file() { [[ -f $1 ]] || fail "missing file: $1"; }
assert_eq() { [[ $1 == "$2" ]] || fail "$3: expected [$2], got [$1]"; }
assert_contains() { grep -qE -- "$2" "$1" || fail "$3"; }
assert_absent() { ! grep -qE -- "$2" "$1" || fail "$3"; }
expect_ok() {
    "$@" > "$CASE/output" 2>&1
    local status=$?
    [[ $status == 0 ]] || { cat "$CASE/output" >&2; fail "$* returned $status"; }
}
expect_failure() {
    "$@" > "$CASE/output" 2>&1
    local status=$?
    [[ $status != 0 ]] || fail "$* unexpectedly succeeded"
}
record() {
    printf '%s' "$1" >> "$OPS"
    shift
    (($# == 0)) || printf ' <%s>' "$@" >> "$OPS"
    printf '\n' >> "$OPS"
}

setup_case() {
    CASE=$(mktemp -d "$SUITE/case.XXXXXX")
    OPS="$CASE/operations"
    : > "$OPS"
    Usque_BinPath="$CASE/bin/usque"
    Usque_ConfigDir="$CASE/account"
    Usque_ConfigPath="$Usque_ConfigDir/config.json"
    Usque_SettingsPath="$Usque_ConfigDir/proxy.conf"
    Usque_Service=usque-warp
    Usque_ServicePath="$CASE/unit/usque-warp.service"
    Usque_Bind=127.0.0.1
    Usque_Port=40000
    CF_Trace_URL=https://www.cloudflare.com/cdn-cgi/trace
    SysInfo_Architecture=x86_64
    SysInfo_OS_Name_lowercase=ubuntu
    WARP_Client_Status=active WARP_CLI_HELP='' WARP_CLI_ACCEPT_TOS=''
    FontColor_Suffix='' FontColor_Red='' FontColor_Green='' FontColor_Yellow=''
    FontColor_Red_Bold='' FontColor_Green_Bold='' FontColor_Yellow_Bold=''
    mkdir -p "$CASE/bin" "$CASE/unit" "$CASE/fixtures"
    MOCK_DOWNLOAD_FAIL=0 MOCK_HASH_FAIL=0 MOCK_ARCHIVE_FAIL=0 MOCK_PORT_BUSY=0
    MOCK_START_FAIL=0 MOCK_REGISTER_FAIL=0 MOCK_CURL_FAIL=0
    MOCK_SS_FAIL=0 MOCK_NO_LISTENER=0
    MOCK_MISSING_COMMAND=''
    MOCK_WARP_PROTOCOL='WireGuard' MOCK_WARP_FAIL=0
    export CASE OPS MOCK_REGISTER_FAIL
    make_release_fixture
}

# Every network/service entry point is a shell mock; downloads only copy fixtures.
command() {
    if [[ ${1:-} == -v && ${2:-} == "$MOCK_MISSING_COMMAND" ]]; then return 1; fi
    builtin command "$@"
}
curl() {
    record curl "$@"
    [[ $MOCK_CURL_FAIL == 0 && $MOCK_DOWNLOAD_FAIL == 0 ]] || return 22
    local output='' url='' arg
    while (($#)); do
        arg=$1; shift
        case "$arg" in
            -o|--output) output=$1; shift ;;
            https://*) url=$arg ;;
        esac
    done
    case "$url" in
        */cdn-cgi/trace) printf 'ip=203.0.113.1\nwarp=on\n' ;;
        *api.github.com*) cat "$CASE/fixtures/release.json" ;;
        *SHA256*|*sha256*|*checksums*)
            if [[ -n $output ]]; then cp "$CASE/fixtures/checksums.txt" "$output"; else cat "$CASE/fixtures/checksums.txt"; fi ;;
        *)
            [[ -n $output && -f $CASE/fixtures/archive.zip ]] || return 22
            cp "$CASE/fixtures/archive.zip" "$output" ;;
    esac
}
systemctl() {
    record systemctl "$@"
    local action='' arg
    for arg in "$@"; do [[ $arg == --* ]] || { action=$arg; break; }; done
    case "$action" in
        is-active) [[ -f $CASE/active ]] ;;
        is-enabled) if [[ -f $CASE/enabled ]]; then printf 'enabled\n'; else printf 'disabled\n'; return 1; fi ;;
        start|restart)
            if [[ $MOCK_START_FAIL == 1 ]]; then MOCK_START_FAIL=0; return 1; fi
            touch "$CASE/active" ;;
        stop) rm -f "$CASE/active" ;;
        enable)
            touch "$CASE/enabled"
            if [[ " $* " == *' --now '* ]]; then
                if [[ $MOCK_START_FAIL == 1 ]]; then MOCK_START_FAIL=0; return 1; fi
                touch "$CASE/active"
            fi ;;
        disable) rm -f "$CASE/enabled"; [[ " $* " != *' --now '* ]] || rm -f "$CASE/active" ;;
        daemon-reload|reset-failed) return 0 ;;
        status) [[ -f $CASE/active ]] ;;
        show)
            case "$*" in
                *MainPID*) if [[ -f $CASE/active ]]; then printf '43\n'; else printf '0\n'; fi ;;
                *LoadState*) if [[ -f $Usque_ServicePath ]]; then printf 'loaded\n'; else printf 'not-found\n'; fi ;;
                *Version*) printf '255\n' ;;
            esac ;;
        *) return 1 ;;
    esac
}
ss() {
    record ss "$@"
    [[ $MOCK_SS_FAIL == 0 ]] || return 1
    [[ $MOCK_NO_LISTENER == 0 ]] || return 0
    if [[ $MOCK_PORT_BUSY == 1 ]]; then
        printf 'LISTEN 0 128 127.0.0.1:40000 0.0.0.0:* users:(("warp-svc",pid=42,fd=3))\n'
    elif [[ -f $CASE/active ]]; then
        printf 'LISTEN 0 128 %s:%s 0.0.0.0:* users:(("usque",pid=43,fd=3))\n' "$Usque_Bind" "$Usque_Port"
    fi
}
warp-cli() {
    record warp-cli "$@"
    [[ $MOCK_WARP_FAIL == 0 ]] || return 1
    case "$*" in *--help*) printf 'Usage: warp-cli\n' ;; *settings*) printf 'WARP tunnel protocol: %s\n' "$MOCK_WARP_PROTOCOL" ;; esac
}
journalctl() { record journalctl "$@"; printf 'usque mock log\n'; }
sleep() { :; }
uname() { case "${1:-}" in -m) printf 'x86_64\n' ;; -s) printf 'Linux\n' ;; *) command uname "$@" ;; esac; }
sha256sum() {
    if [[ $MOCK_HASH_FAIL == 1 ]]; then printf '%064d  %s\n' 0 "${@: -1}"; else command sha256sum "$@"; fi
}
tar() { [[ $MOCK_ARCHIVE_FAIL == 0 ]] || return 1; command tar "$@"; }
unzip() { record unzip "$@"; [[ $MOCK_ARCHIVE_FAIL == 0 ]] || return 1; cat "$CASE/fixtures/usque"; }
kill() { record FORBIDDEN-kill "$@"; return 1; }
pkill() { record FORBIDDEN-pkill "$@"; return 1; }
killall() { record FORBIDDEN-killall "$@"; return 1; }
apt() { record FORBIDDEN-apt "$@"; return 1; }
apt-get() { record FORBIDDEN-apt-get "$@"; return 1; }
yum() { record FORBIDDEN-yum "$@"; return 1; }
ip() { record FORBIDDEN-ip "$@"; return 1; }
wg() { record FORBIDDEN-wg "$@"; return 1; }

install_mock_binary() {
    cat > "$Usque_BinPath" <<'BIN'
#!/usr/bin/env bash
printf 'usque' >> "$OPS"; printf ' <%s>' "$@" >> "$OPS"; printf '\n' >> "$OPS"
config='' action=''
while (($#)); do
    case "$1" in
        -c|--config) config=$2; shift 2 ;;
        register) action=register; shift ;;
        --version|version) printf 'usque version: v1.0.0\n'; exit 0 ;;
        *) shift ;;
    esac
done
if [[ $action == register ]]; then
    [[ ${MOCK_REGISTER_FAIL:-0} == 0 && -n $config ]] || exit 1
    printf '{"private_key":"PRIVATE-KEY-MUST-STAY-SECRET","id":"test-account"}\n' > "$config"
fi
BIN
    chmod +x "$Usque_BinPath"
}
existing_account() {
    install_mock_binary
    mkdir -p "$Usque_ConfigDir"
    printf '{"private_key":"PRIVATE-KEY-MUST-STAY-SECRET","id":"existing-account"}\n' > "$Usque_ConfigPath"
    chmod 600 "$Usque_ConfigPath"
}

make_release_fixture() {
    printf 'mock zip archive\n' > "$CASE/fixtures/archive.zip"
    local hash
    hash=$(command sha256sum "$CASE/fixtures/archive.zip")
    printf '%s  usque_1.0.1_linux_amd64.zip\n' "${hash%% *}" > "$CASE/fixtures/checksums.txt"
    printf '{"tag_name":"v1.0.1","assets":[{"name":"usque_1.0.1_linux_amd64.zip","browser_download_url":"https://github.com/Diniboy1123/usque/releases/download/v1.0.1/usque_1.0.1_linux_amd64.zip"},{"name":"checksums.txt","browser_download_url":"https://github.com/Diniboy1123/usque/releases/download/v1.0.1/checksums.txt"}]}\n' > "$CASE/fixtures/release.json"
    install_mock_binary
    sed 's/v1.0.0/v1.0.1/' "$Usque_BinPath" > "$CASE/fixtures/usque"
    rm "$Usque_BinPath"
}

test_default_settings() {
    expect_ok Load_Usque_Settings
    assert_eq "$Usque_Bind" 127.0.0.1 'default bind'
    assert_eq "$Usque_Port" 40000 'default port'
}

test_settings_not_executed() {
    mkdir -p "$Usque_ConfigDir"
    printf 'bind=127.0.0.1\nport=40000\ntouch %s/injected\n' "$CASE" > "$Usque_SettingsPath"
    Load_Usque_Settings > "$CASE/output" 2>&1 || true
    [[ ! -e $CASE/injected ]] || fail 'settings executed shell commands'
    printf 'bind=$(touch %s/injected)\nport=40000\n' "$CASE" > "$Usque_SettingsPath"
    expect_failure Load_Usque_Settings
    [[ ! -e $CASE/injected ]] || fail 'settings executed command substitution'
}

test_invalid_settings_rejected() {
    existing_account
    local bind port
    for bind in localhost '127.0.0.1;id' 999.0.0.1; do
        expect_failure Configure_Usque_Proxy "$bind" 40000
    done
    for port in 0 65536 '-1' '40000;id' abc; do
        expect_failure Configure_Usque_Proxy 127.0.0.1 "$port"
    done
    assert_absent "$OPS" 'systemctl <(enable|start|restart)>' 'invalid input changed service'
}

test_existing_account_enable_and_repeat() {
    existing_account
    cp "$Usque_ConfigPath" "$CASE/account.before"
    expect_ok Enable_Usque_Proxy
    assert_file "$CASE/enabled"
    assert_file "$CASE/active"
    expect_ok Enable_Usque_Proxy
    cmp -s "$CASE/account.before" "$Usque_ConfigPath" || fail 'existing account changed'
    assert_absent "$OPS" 'usque .*<register>' 'existing account registered again'
    assert_absent "$CASE/output" 'PRIVATE-KEY-MUST-STAY-SECRET' 'account secret printed'
    assert_file "$Usque_ServicePath"
    assert_contains "$Usque_ServicePath" --http2 'unit does not force HTTP/2'
    assert_contains "$Usque_ServicePath" "-c[ =]+\"?$Usque_ConfigPath" 'unit lacks absolute config path'
    assert_absent "$Usque_ServicePath" --local-dns 'unit enables local DNS'
}

test_first_registration_is_private() {
    install_mock_binary
    expect_ok Enable_Usque_Proxy
    assert_file "$Usque_ConfigPath"
    assert_eq "$(stat -c '%a' "$Usque_ConfigPath")" 600 'account permissions'
    assert_contains "$OPS" '<register>' 'account registration not performed'
    assert_contains "$OPS" "<$Usque_ConfigPath>" 'registration did not use explicit config path'
    assert_absent "$CASE/output" 'PRIVATE-KEY-MUST-STAY-SECRET' 'registration secret printed'
}

test_registration_failure_does_not_start_service() {
    install_mock_binary
    MOCK_REGISTER_FAIL=1
    expect_failure Enable_Usque_Proxy
    assert_absent "$OPS" 'systemctl <(start|enable|restart)>' 'failed registration started service'
    assert_absent "$CASE/output" 'PRIVATE-KEY-MUST-STAY-SECRET' 'failed registration printed secret'
}

test_status_and_logs() {
    existing_account
    expect_ok Enable_Usque_Proxy
    expect_ok Check_Usque_Status
    assert_eq "$Usque_Status" active 'running service status'
    assert_eq "$Usque_SelfStart_en" Enabled 'autostart status'
    assert_eq "$Usque_Version" v1.0.0 'installed version'
    assert_eq "$Usque_Proxy_Status" on 'owned listener proxy status'
    expect_ok Print_Usque_Log
    assert_contains "$OPS" '^journalctl <-u> <usque-warp>' 'log command targets wrong service'
}

test_proxy_status_tracks_owned_listener() {
    existing_account
    expect_ok Enable_Usque_Proxy
    expect_ok Check_Usque_Status
    assert_eq "$Usque_Proxy_Status" on 'running proxy status'
    MOCK_PORT_BUSY=1
    expect_ok Check_Usque_Status
    assert_eq "$Usque_Status" active 'foreign listener changed service status'
    assert_eq "$Usque_Proxy_Status" off 'foreign PID was reported as working usque proxy'
    MOCK_PORT_BUSY=0 MOCK_NO_LISTENER=1
    expect_ok Check_Usque_Status
    assert_eq "$Usque_Proxy_Status" off 'active service without listener reported proxy on'
    MOCK_NO_LISTENER=0 MOCK_MISSING_COMMAND=ss
    expect_ok Check_Usque_Status
    assert_eq "$Usque_Proxy_Status" unknown 'missing ss was reported as a verified proxy status'
    MOCK_MISSING_COMMAND='' MOCK_SS_FAIL=1
    expect_ok Check_Usque_Status
    assert_eq "$Usque_Proxy_Status" unknown 'failed ss query was reported as a verified proxy status'
    MOCK_SS_FAIL=0
    expect_ok Disable_Usque_Proxy
    expect_ok Check_Usque_Status
    assert_eq "$Usque_Status" inactive 'stopped service status'
    assert_eq "$Usque_Proxy_Status" off 'stopped proxy status'
}

test_disable_only_usque_and_keeps_account() {
    existing_account
    expect_ok Enable_Usque_Proxy
    : > "$OPS"
    expect_ok Disable_Usque_Proxy
    assert_file "$Usque_ConfigPath"
    [[ ! -e $CASE/active && ! -e $CASE/enabled ]] || fail 'service remains active/enabled'
    assert_absent "$OPS" 'warp-cli|FORBIDDEN|<(warp-svc|wg-quick|wgcf)>' 'disable touched another client'
}

test_foreign_listener_is_not_killed() {
    existing_account
    MOCK_PORT_BUSY=1
    expect_failure Enable_Usque_Proxy
    assert_absent "$OPS" 'FORBIDDEN|systemctl <(start|enable|restart|stop)>' 'port conflict changed another service'
}

test_start_failure_does_not_fall_back() {
    existing_account
    MOCK_START_FAIL=1
    expect_failure Enable_Usque_Proxy
    assert_contains "$Usque_ServicePath" --http2 'failed startup discarded HTTP/2 setting'
    assert_absent "$OPS" '<(socks|tunnel)>|FORBIDDEN' 'startup failure attempted direct tunnel fallback'
    assert_absent "$Usque_ServicePath" --local-dns 'startup failure enabled local DNS'
}

test_missing_dependencies_fail() {
    existing_account
    MOCK_MISSING_COMMAND=ss
    expect_failure Enable_Usque_Proxy
    assert_absent "$OPS" 'systemctl <(enable|start|restart)>' 'missing ss started service'
    MOCK_MISSING_COMMAND=unzip
    expect_failure Install_Usque
    assert_absent "$OPS" '^curl' 'missing unzip started release download'
}

test_trace_uses_proxy_even_with_no_proxy() {
    existing_account
    expect_ok Enable_Usque_Proxy
    : > "$OPS"
    NO_PROXY='*' no_proxy='*' expect_ok Test_Usque_Proxy
    assert_contains "$OPS" '<--(socks5-hostname|proxy)>.*(127.0.0.1:40000|socks5h://127.0.0.1:40000)' 'trace lacks SOCKS5 proxy'
    assert_contains "$OPS" '<--noproxy> <>' 'trace can bypass proxy with NO_PROXY'
}

test_trace_rejects_another_proxy() {
    existing_account
    MOCK_PORT_BUSY=1
    expect_failure Test_Usque_Proxy
    assert_absent "$OPS" '^curl' 'inactive usque tested another client on the same port'
    touch "$CASE/active"
    : > "$OPS"
    expect_failure Test_Usque_Proxy
    assert_absent "$OPS" '^curl' 'usque tested a listener belonging to another service PID'
}

test_inactive_wireguard_with_blocked_icmp() {
    WireGuard_Status=inactive
    TestIPv4_1=1.0.0.1 TestIPv4_2=9.9.9.9
    TestIPv6_1=2606:4700:4700::1001 TestIPv6_2=2620:fe::fe
    ping() { record ping "$@"; return 1; }
    ping6() { record ping6 "$@"; return 1; }
    Disable_WireGuard() { record FORBIDDEN-disable-wireguard; }
    # The installer intentionally unsets offline trace values; it does not use nounset.
    # A marker after the call detects even an erroneous `exit 0` in the function.
    check_offline_status() {
        (
            set +u
            Check_WARP_WireGuard_Status
            record wireguard-status-returned
        )
    }
    expect_ok check_offline_status
    assert_contains "$OPS" '^wireguard-status-returned$' 'offline ICMP status exited the script'
    assert_contains "$OPS" '^ping ' 'IPv4 ICMP probe was not exercised'
    assert_contains "$OPS" '^ping6 ' 'IPv6 ICMP probe was not exercised'
    assert_absent "$OPS" 'FORBIDDEN|^curl|^systemctl' 'offline ICMP status modified inactive WireGuard'
}

test_configuration_failure_rolls_back() {
    existing_account
    expect_ok Enable_Usque_Proxy
    cp "$Usque_SettingsPath" "$CASE/settings.before"
    cp "$Usque_ServicePath" "$CASE/unit.before"
    MOCK_START_FAIL=1
    expect_failure Configure_Usque_Proxy 127.0.0.2 41000
    cmp -s "$CASE/settings.before" "$Usque_SettingsPath" || fail 'failed configuration changed settings'
    cmp -s "$CASE/unit.before" "$Usque_ServicePath" || fail 'failed configuration changed unit'
    assert_file "$CASE/active"
}

test_configuration_and_restart() {
    existing_account
    expect_ok Enable_Usque_Proxy
    expect_ok Configure_Usque_Proxy 0.0.0.0 41000
    assert_contains "$Usque_SettingsPath" '^bind=0.0.0.0$' 'new bind was not persisted'
    assert_contains "$Usque_SettingsPath" '^port=41000$' 'new port was not persisted'
    assert_contains "$Usque_ServicePath" '-b 0.0.0.0 -p 41000' 'unit retained old bind or port'
    expect_ok Restart_Usque_Proxy
    expect_ok Test_Usque_Proxy
    assert_contains "$OPS" '<socks5h://127.0.0.1:41000>' 'wildcard bind test did not use loopback'
    assert_absent "$OPS" '<register>' 'reconfiguration registered another account'
}

test_install_failure_preserves_binary() {
    install_mock_binary
    cp "$Usque_BinPath" "$CASE/binary.before"
    local failure
    for failure in MOCK_DOWNLOAD_FAIL MOCK_HASH_FAIL MOCK_ARCHIVE_FAIL; do
        printf -v "$failure" '%s' 1
        expect_failure Install_Usque
        cmp -s "$CASE/binary.before" "$Usque_BinPath" || fail "$failure replaced original binary"
        printf -v "$failure" '%s' 0
    done
}

test_install_verified_release() {
    expect_ok Install_Usque
    assert_file "$Usque_BinPath"
    [[ -x $Usque_BinPath ]] || fail 'installed binary is not executable'
    assert_contains "$Usque_BinPath" v1.0.1 'installed binary is not verified release fixture'
    assert_contains "$OPS" '^unzip' 'release archive was not extracted'
    assert_absent "$OPS" 'FORBIDDEN' 'install attempted real dependency installation'
}

test_update_start_failure_restores_binary() {
    existing_account
    expect_ok Enable_Usque_Proxy
    cp "$Usque_BinPath" "$CASE/binary.before"
    MOCK_START_FAIL=1
    expect_failure Install_Usque
    cmp -s "$CASE/binary.before" "$Usque_BinPath" || fail 'failed update changed binary'
    assert_contains "$OPS" '^unzip' 'failed update never reached replacement binary'
    assert_file "$CASE/active"
}

test_uninstall_keeps_account() {
    existing_account
    expect_ok Enable_Usque_Proxy
    expect_ok Uninstall_Usque
    assert_file "$Usque_ConfigPath"
    assert_file "$Usque_SettingsPath"
    [[ ! -e $Usque_BinPath && ! -e $Usque_ServicePath ]] || fail 'uninstall retained binary/unit'
    assert_absent "$OPS" 'FORBIDDEN|warp-cli' 'uninstall touched another client'
}

test_official_protocol_detection() {
    expect_ok Get_WARP_Upstream_Protocol
    assert_eq "${WARP_Upstream_Protocol_en// /}" WireGuard/UDP 'official WireGuard protocol'
    MOCK_WARP_PROTOCOL=MASQUE
    expect_ok Get_WARP_Upstream_Protocol
    assert_eq "$WARP_Upstream_Protocol_en" MASQUE 'official MASQUE protocol'
    MOCK_WARP_FAIL=1
    Get_WARP_Upstream_Protocol > "$CASE/output" 2>&1 || true
    assert_eq "$WARP_Upstream_Protocol_en" 'Settings unavailable' 'failed settings detection reason'
    assert_eq "$WARP_Upstream_Protocol_zh" '设置读取失败' 'failed settings detection Chinese reason'
    MOCK_WARP_FAIL=0 MOCK_WARP_PROTOCOL=unrecognized
    expect_ok Get_WARP_Upstream_Protocol
    assert_eq "$WARP_Upstream_Protocol_en" 'Unknown protocol' 'unknown protocol detection reason'
    MOCK_MISSING_COMMAND=warp-cli
    expect_ok Get_WARP_Upstream_Protocol
    assert_eq "$WARP_Upstream_Protocol_en" 'Not installed' 'missing client detection reason'
    MOCK_MISSING_COMMAND='' WARP_Client_Status=inactive
    expect_ok Get_WARP_Upstream_Protocol
    assert_eq "$WARP_Upstream_Protocol_en" 'Client stopped' 'stopped client detection reason'
    assert_eq "$WARP_Upstream_Protocol_zh" '客户端未运行' 'stopped client Chinese reason'
}

test_main_menu_routes_nine() {
    Check_ALL_Status() { :; }
    clear() { :; }
    Menu_Title=test
    WARP_Client_Status_zh='' WARP_Proxy_Status_zh='' WireGuard_Status_zh=''
    WARP_IPv4_Status_zh='' WARP_IPv6_Status_zh='' WARP_Upstream_Protocol_zh=''
    Usque_Status_zh='service-status-marker' Usque_Proxy_Status_zh='proxy-status-marker'
    Usque_Listen_Address_zh='listen-address-marker'
    Menu_Usque() { record menu-usque; }
    expect_ok Start_Menu <<< 9
    assert_contains "$OPS" '^menu-usque$' 'main option 9 does not open usque menu'
    assert_contains "$CASE/output" service-status-marker 'main menu omits usque service status'
    assert_contains "$CASE/output" proxy-status-marker 'main menu omits usque SOCKS5 status'
    WARP_Client_Status_en='' WARP_Proxy_Status_en='' WireGuard_Status_en=''
    WARP_IPv4_Status_en='' WARP_IPv6_Status_en='' WARP_Upstream_Protocol_en=''
    Usque_Status_en='service-status-marker' Usque_Proxy_Status_en='proxy-status-marker'
    Usque_Listen_Address_en='listen-address-marker'
    expect_ok Print_ALL_Status
    assert_contains "$CASE/output" service-status-marker 'status command omits usque service status'
    assert_contains "$CASE/output" proxy-status-marker 'status command omits usque SOCKS5 status'
}

test_usque_submenu_routes_actions() {
    Check_Usque_Status() {
        Usque_Version=test
        Usque_Status_zh=test
        Usque_SelfStart_zh=test
        Usque_Listen_Address_zh=test
        Usque_Proxy_Status_zh='proxy-status-marker'
    }
    clear() { :; }
    Menu_Title=test
    Install_Usque() { record menu-install; }
    Enable_Usque_Proxy() { record menu-enable; }
    Disable_Usque_Proxy() { record menu-disable; }
    Restart_Usque_Proxy() { record menu-restart; }
    Configure_Usque_Proxy() { record menu-configure; }
    Test_Usque_Proxy() { record menu-test; }
    Print_Usque_Log() { record menu-log; }
    Uninstall_Usque() { record menu-uninstall; }
    local option action
    local actions=(install enable disable restart configure test log uninstall)
    for option in {1..8}; do
        : > "$OPS"
        expect_ok Menu_Usque <<< "$option"
        assert_contains "$CASE/output" proxy-status-marker 'usque submenu omits SOCKS5 status'
        action=${actions[$((option - 1))]}
        assert_eq "$(cat "$OPS")" "menu-$action" "submenu option $option"
    done
}

test_invalid_settings_do_not_block_service_management() {
    existing_account
    expect_ok Enable_Usque_Proxy
    printf 'bind=invalid-host\nport=40000\n' > "$Usque_SettingsPath"
    cp "$Usque_SettingsPath" "$CASE/invalid-settings.before"
    expect_ok Check_Usque_Status
    assert_eq "$Usque_Status" active 'bad settings concealed running service'
    assert_eq "$Usque_Listen_Address_en" 'Invalid proxy.conf' 'bad settings address label'
    assert_eq "$Usque_Proxy_Status" invalid-config 'bad settings proxy status'
    clear() { :; }
    Menu_Title=test
    : > "$OPS"
    expect_ok Menu_Usque <<< 3
    assert_contains "$OPS" '^systemctl <disable> <--now> <usque-warp>' 'bad settings blocked menu stop action'
    [[ ! -e $CASE/active && ! -e $CASE/enabled ]] || fail 'menu stop left service running or enabled'
    : > "$OPS"
    expect_ok Menu_Usque <<< 7
    assert_contains "$OPS" '^journalctl <-u> <usque-warp>' 'bad settings blocked menu log action'
    : > "$OPS"
    expect_failure Enable_Usque_Proxy
    assert_absent "$OPS" 'systemctl <(enable|start|restart)>|<register>|FORBIDDEN' 'bad settings enabled service or changed another client'
    cmp -s "$CASE/invalid-settings.before" "$Usque_SettingsPath" || fail 'service management overwrote bad settings'
    assert_file "$Usque_ConfigPath"
}

run_test() {
    local name=$1
    if (setup_case; cd "$CASE"; "$name"); then printf 'ok - %s\n' "$name"; else FAILED=$((FAILED + 1)); fi
}

FAILED=0
for test in \
    test_default_settings \
    test_settings_not_executed \
    test_invalid_settings_rejected \
    test_existing_account_enable_and_repeat \
    test_first_registration_is_private \
    test_registration_failure_does_not_start_service \
    test_status_and_logs \
    test_proxy_status_tracks_owned_listener \
    test_disable_only_usque_and_keeps_account \
    test_foreign_listener_is_not_killed \
    test_start_failure_does_not_fall_back \
    test_missing_dependencies_fail \
    test_trace_uses_proxy_even_with_no_proxy \
    test_trace_rejects_another_proxy \
    test_inactive_wireguard_with_blocked_icmp \
    test_configuration_failure_rolls_back \
    test_configuration_and_restart \
    test_install_failure_preserves_binary \
    test_install_verified_release \
    test_update_start_failure_restores_binary \
    test_uninstall_keeps_account \
    test_official_protocol_detection \
    test_main_menu_routes_nine \
    test_usque_submenu_routes_actions \
    test_invalid_settings_do_not_block_service_management; do
    run_test "$test"
done
((FAILED == 0)) || { printf '%s test(s) failed\n' "$FAILED" >&2; exit 1; }
printf 'All isolated usque tests passed.\n'
