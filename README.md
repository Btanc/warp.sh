**English** | [中文](https://p3terx.com/archives/cloudflare-warp-configuration-script.html)

# Cloudflare WARP Installer

A Bash script that automatically installs and configures CloudFlare WARP in Linux, connects to WARP networks with WARP official client or WireGuard.

## Features

- Automatically install CloudFlare WARP Official Linux Client
- Quickly enable WARP Proxy Mode, access WARP network with SOCKS5
- Manage a separate usque SOCKS5 proxy with an HTTP/2 (TCP + TLS) upstream
- Automatically install WireGuard related components
- Configuration WARP IPv4 Network interface (WireGuard Mode)
- Configuration WARP IPv6 Network interface (WireGuard Mode)
- Configuration WARP Dual Stack Network interface (WireGuard Mode)
- ...

## Requirements

### WARP Official Linux Client

Official WARP client support is currently limited to x86_64 platforms, see OS Support for details: https://pkg.cloudflareclient.com

### WARP WireGuard Network Mode

Supported distributions:

- Debian >= 10
- Ubuntu >= 16.04
- Fedora
- CentOS
- Oracle Linux
- Arch Linux
- Other similar distributions

Supported platform architecture:

- x86(i386)
- x86_64(amd64)
- ARMv8(aarch64)
- ARMv7(armhf)

### usque SOCKS5 Proxy

Requires Linux with systemd, `curl`, `unzip`, `sha256sum`, and `ss`. The installer selects the latest stable [usque release](https://github.com/Diniboy1123/usque/releases) for the machine's architecture and verifies its SHA256 checksum before installation.

## Usage

```bash
bash <(curl -fsSL git.io/warp.sh) [SUBCOMMAND]
# or
wget git.io/warp.sh
bash warp.sh [SUBCOMMAND]
```

### Subcommands

```
install         Install Cloudflare WARP Official Linux Client
uninstall       uninstall Cloudflare WARP Official Linux Client
restart         Restart Cloudflare WARP Official Linux Client
proxy           Enable WARP Client Proxy Mode (default SOCKS5 port: 40000)
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
menu            Chinese special features menu
```

### Example

- Install and automatically configure the Proxy Mode feature of the WARP client, enable the local loopback port 40000, and use an application that supports SOCKS5 to connect to this port.
    ```
    bash <(curl -fsSL git.io/warp.sh) proxy
    ```

- Install and automatically configure WARP IPv6 Network (with WireGuard)，Giving your Linux server access to IPv6 networks.
    ```
    bash <(curl -fsSL git.io/warp.sh) wg6
    ```

- This Bash script is also a good WireGuard installer.
    ```
    bash <(curl -fsSL git.io/warp.sh) wg
    ```

- Stop the official WARP client and disable automatic startup while preserving installed components, accounts, and configuration. Open the menu, select `3` (manage the official client), then `5` (turn off the official client).
    ```bash
    bash warp.sh menu
    ```

    To restore the official client proxy and enable automatic startup:
    ```bash
    bash warp.sh proxy
    ```

### Manage usque

Open the menu and select `9` (manage usque / WARP proxy):

```bash
sudo bash warp.sh menu
```

The usque submenu provides:

```text
1  Install or update usque
2  Enable SOCKS5 proxy (upstream: HTTP/2 / TCP + TLS)
3  Disable SOCKS5 proxy (upstream: HTTP/2 / TCP + TLS)
4  Restart SOCKS5 proxy (upstream: HTTP/2 / TCP + TLS)
5  Change the IPv4 listen address and port
6  Test the proxy's outbound connection
7  View service logs
8  Uninstall usque, keeping the account configuration
0  Return to the main menu
```

The default listener is `127.0.0.1:40000`. usque runs as the independent `usque-warp.service` systemd service with `socks --http2 --always-reconnect`; its connection to Cloudflare uses HTTP/2 over TCP + TLS. The binary is installed at `/usr/local/bin/usque`, account credentials are stored in `/etc/usque/config.json`, and listener settings are stored in `/etc/usque/proxy.conf`.

On first enable, the script reuses the account configuration at that fixed path. If none exists, it imports an existing `config.json` from the current directory or runs usque's `register` command. Updating, disabling, and uninstalling usque preserve the account configuration. If another process owns the requested port, the script reports the conflict; use submenu option `5` to select a different port. The official WARP proxy also defaults to port `40000`, so choose separate ports to run both.

The main menu and `bash warp.sh status` show both the usque service state and SOCKS5 listener state. A running service is only reported as listening when its own process owns the configured TCP port; outbound connectivity is checked separately with submenu option `6`. usque management is available through the menu; no additional CLI subcommands are added. Official WARP SOCKS5 menu labels display the configured protocol from `warp-cli settings`: `WireGuard / UDP` or `MASQUE`. When the official client is stopped, the label explains that its settings cannot be read. The MASQUE setting does not identify whether its current transport is QUIC or HTTP/2.

Run the isolated regression tests with `bash tests/usque.sh`. They use temporary files and mock network and service operations.

## Credits

- [Cloudflare WARP](https://1.1.1.1/)
- [WireGuard](https://www.wireguard.com/)
- [ViRb3/wgcf](https://github.com/ViRb3/wgcf)
- [Diniboy1123/usque](https://github.com/Diniboy1123/usque)

## License

[MIT](https://github.com/P3TERX/warp.sh/blob/main/LICENSE) © **[P3TERX](https://p3terx.com/)**

## Notice of Non-Affiliation and Disclaimer

We are not affiliated, associated, authorized, endorsed by, or in any way officially connected with Cloudflare, or any of its subsidiaries or its affiliates. The official Cloudflare website can be found at https://www.cloudflare.com/.

The names Cloudflare Warp and Cloudflare as well as related names, marks, emblems and images are registered trademarks of their respective owners.
