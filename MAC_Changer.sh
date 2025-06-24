#!/bin/bash
echo "

░█▄█░█▀█░█▀▀░░░░░█▀▀░█░█░█▀█░█▀█░█▀▀░█▀▀░█▀▄
░█░█░█▀█░█░░░▄▄▄░█░░░█▀█░█▀█░█░█░█░█░█▀▀░█▀▄
░▀░▀░▀░▀░▀▀▀░░░░░▀▀▀░▀░▀░▀░▀░▀░▀░▀▀▀░▀▀▀░▀░▀

"
LAN_IF="eno2"
WIFI_IF="wlo1"

declare -A VENDOR_OUI=(
    ["Apple"]="DC:A9:04"
    ["Samsung"]="00:16:6C"
    ["Intel"]="F0:1F:AF"
    ["Cisco"]="00:1B:54"
    ["Huawei"]="00:9A:CD"
    ["Xiaomi"]="A4:77:33"
    ["ASUS"]="AC:22:0B"
    ["TP-Link"]="D8:47:32"
    ["Dell"]="00:14:22"
    ["Lenovo"]="F4:8C:50"
    ["LG"]="00:1E:75"
    ["Microsoft"]="00:50:F2"
    ["Nokia"]="3C:36:E4"
    ["Sony"]="00:26:B0"
    ["OnePlus"]="04:D6:AA"
    ["Realtek"]="00:E0:4C"
    ["Broadcom"]="00:10:18"
    ["Tenda"]="C8:3A:35"
    ["Netgear"]="20:4E:7F"
    ["D-Link"]="00:1E:58"
)

generate_random_mac() {
    hexchars="0123456789ABCDEF"
    echo "02$(for i in {1..5}; do echo -n ":${hexchars:$((RANDOM%16)):1}${hexchars:$((RANDOM%16)):1}"; done)"
}

generate_anonymous_mac() {
    printf "02"
    for i in {1..5}; do printf ":%02X" $((RANDOM % 256)); done
    echo
}

generate_mac_with_oui() {
    local oui="$1"
    local rand_suffix=$(for i in {1..3}; do printf ":%02X" $((RANDOM % 256)); done)
    echo "$oui$rand_suffix"
}

ask_mac_manual() {
    read -rp "Enter MAC for $1 (leave blank for random): " input
    [[ -z "$input" ]] && generate_random_mac || echo "$input"
}

select_vendor_oui() {
    echo
    echo "Choose a brand to randomize MAC:"
    local i=1
    local keys=()
    for key in "${!VENDOR_OUI[@]}"; do
        echo "$i. $key (${VENDOR_OUI[$key]})"
        keys+=("$key")
        ((i++))
    done
    read -p "Select number: " vendor_index
    selected_vendor="${keys[$((vendor_index-1))]}"
    echo "${VENDOR_OUI[$selected_vendor]}"
}

change_temp_mac() {
    local iface="$1"
    local mac="$2"
    echo "[*] Temporarily changing MAC for $iface → $mac"
    sudo ip link set "$iface" down
    sudo ip link set "$iface" address "$mac"
    sudo ip link set "$iface" up
}

change_perm_mac() {
    local iface="$1"
    local mac="$2"
    local conn_name
    conn_name=$(nmcli -t -f NAME,DEVICE connection show | grep "$iface" | cut -d: -f1)
    if [ -z "$conn_name" ]; then
        echo "[!] Could not find connection for $iface"
        return
    fi
    echo "[*] Permanently changing MAC for $iface ($conn_name) → $mac"
    sudo nmcli connection modify "$conn_name" cloned-mac-address "$mac"
}

# ===== MENU =====

echo "====== MAC CHANGER MENU ======"
echo "1. Temporary MAC change"
echo "2. Permanent MAC change (NetworkManager)"
read -p "Choose mode (1/2): " mode_opt

echo
echo "1. Enter MAC manually"
echo "2. Fully random"
echo "3. Random by brand"
echo "4. Anonymous MAC (local admin)"
read -p "Choose MAC type (1-4): " mac_mode_opt

echo
echo "1. LAN only ($LAN_IF)"
echo "2. Wi-Fi only ($WIFI_IF)"
echo "3. Both"
read -p "Choose interface (1-3): " iface_opt
echo

[[ "$mode_opt" == "1" ]] && MODE="temp" || MODE="perm"

# If random by brand, select OUI after interface selection
if [[ "$mac_mode_opt" == "3" ]]; then
    selected_oui=$(select_vendor_oui)
fi

get_mac() {
    local iface="$1"
    case "$mac_mode_opt" in
        1) ask_mac_manual "$iface" ;;
        2) generate_random_mac ;;
        3) generate_mac_with_oui "$selected_oui" ;;
        4) generate_anonymous_mac ;;
        *) echo "[!] Invalid option"; exit 1 ;;
    esac
}

[[ "$iface_opt" == "1" || "$iface_opt" == "3" ]] && LAN_MAC=$(get_mac "$LAN_IF")
[[ "$iface_opt" == "2" || "$iface_opt" == "3" ]] && WIFI_MAC=$(get_mac "$WIFI_IF")

if [[ "$MODE" == "temp" ]]; then
    [[ "$iface_opt" == "1" || "$iface_opt" == "3" ]] && change_temp_mac "$LAN_IF" "$LAN_MAC"
    [[ "$iface_opt" == "2" || "$iface_opt" == "3" ]] && change_temp_mac "$WIFI_IF" "$WIFI_MAC"
else
    [[ "$iface_opt" == "1" || "$iface_opt" == "3" ]] && change_perm_mac "$LAN_IF" "$LAN_MAC"
    [[ "$iface_opt" == "2" || "$iface_opt" == "3" ]] && change_perm_mac "$WIFI_IF" "$WIFI_MAC"
    sudo systemctl restart NetworkManager
fi

echo
echo "[✓] Done."
