#!/bin/bash

# DNS Servers list
declare -A DNS_SERVERS
DNS_SERVERS["Google"]="8.8.8.8 8.8.4.4"
DNS_SERVERS["Cloudflare"]="1.1.1.1 1.0.0.1"
DNS_SERVERS["AdGuard"]="94.140.14.14 94.140.15.15"
DNS_SERVERS["OpenDNS"]="208.67.222.222 208.67.220.220"
DNS_SERVERS["VNPT"]="203.113.131.1 203.113.131.2"
DNS_SERVERS["FPT"]="210.245.31.130 210.245.31.131"

reset_dns_wifi() {
    iface=$(nmcli -t -f NAME connection show --active | head -n 1)
    nmcli con mod "$iface" ipv4.ignore-auto-dns no
    nmcli con mod "$iface" ipv4.dns ""
    nmcli con up "$iface"
    echo "[+] Wi-Fi DNS reset to default."
}

set_dns_wifi() {
    iface=$(nmcli -t -f NAME connection show --active | head -n 1)
    echo "Choose a DNS provider:"
    select name in "${!DNS_SERVERS[@]}"; do
        if [[ -n $name ]]; then
            nmcli con mod "$iface" ipv4.ignore-auto-dns yes
            nmcli con mod "$iface" ipv4.dns "${DNS_SERVERS[$name]}"
            nmcli con up "$iface"
            echo "[+] ${name} DNS set for Wi-Fi ($iface)."
            break
        else
            echo "Invalid selection."
        fi
    done
}

reset_dns_system() {
    sudo sed -i '/^DNS=/d;/^FallbackDNS=/d' /etc/systemd/resolved.conf
    sudo systemctl restart systemd-resolved
    echo "[+] System DNS reset to default."
}

set_dns_system() {
    echo "Choose a DNS provider:"
    select name in "${!DNS_SERVERS[@]}"; do
        if [[ -n $name ]]; then
            sudo sed -i '/^DNS=/d;/^FallbackDNS=/d' /etc/systemd/resolved.conf
            echo "DNS=${DNS_SERVERS[$name]}" | sudo tee -a /etc/systemd/resolved.conf > /dev/null
            echo "FallbackDNS=8.8.8.8" | sudo tee -a /etc/systemd/resolved.conf > /dev/null
            sudo systemctl restart systemd-resolved
            echo "[+] ${name} DNS applied system-wide."
            break
        else
            echo "Invalid selection."
        fi
    done
}

test_dns_latency() {
    echo "Testing DNS latency (lower is better):"
    for name in "${!DNS_SERVERS[@]}"; do
        dns_ip=$(echo "${DNS_SERVERS[$name]}" | awk '{print $1}')
        avg=$(ping -c 3 -q "$dns_ip" | awk -F'/' '/avg/ {print $5}')
        echo "$name ($dns_ip): ${avg:-timeout} ms"
    done
}

setup_doh_cloudflare() {
    echo "[*] Installing cloudflared (Cloudflare DoH client)..."
    sudo apt install -y cloudflared || {
        echo "cloudflared install failed"; return
    }

    echo "[*] Configuring system to use cloudflared..."
    sudo tee /etc/systemd/system/cloudflared-dns.service > /dev/null <<EOF
[Unit]
Description=Cloudflare DNS over HTTPS Proxy
After=network.target

[Service]
ExecStart=/usr/bin/cloudflared proxy-dns
Restart=on-failure
User=nobody

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reexec
    sudo systemctl enable --now cloudflared-dns

    echo "[*] Setting system DNS to 127.0.0.1"
    sudo sed -i '/^DNS=/d;/^FallbackDNS=/d' /etc/systemd/resolved.conf
    echo "DNS=127.0.0.1" | sudo tee -a /etc/systemd/resolved.conf > /dev/null
    sudo systemctl restart systemd-resolved

    echo "[+] DoH via Cloudflare is now active at 127.0.0.1"
}

main_menu() {
    echo "=== DNS Configurator ==="
    select opt in \
        "Set DNS for current Wi-Fi" \
        "Reset DNS for Wi-Fi" \
        "Set system-wide DNS" \
        "Reset system-wide DNS" \
        "Test DNS latency" \
        "Enable DoH via Cloudflare" \
        "Exit"; do

        case $REPLY in
            1) set_dns_wifi ;;
            2) reset_dns_wifi ;;
            3) set_dns_system ;;
            4) reset_dns_system ;;
            5) test_dns_latency ;;
            6) setup_doh_cloudflare ;;
            7) exit 0 ;;
            *) echo "Invalid option." ;;
        esac
        break
    done
}

main_menu
