#!/bin/bash

echo "

░█▀▀░█░█░█▀▀░▀█▀░█▀▀░█▄█░░░░░█▀▀░█░░░█▀▀░█▀█░█▀█░█▀▀░█▀▄
░▀▀█░░█░░▀▀█░░█░░█▀▀░█░█░▄▄▄░█░░░█░░░█▀▀░█▀█░█░█░█▀▀░█▀▄
░▀▀▀░░▀░░▀▀▀░░▀░░▀▀▀░▀░▀░░░░░▀▀▀░▀▀▀░▀▀▀░▀░▀░▀░▀░▀▀▀░▀░▀

"

get_size() {
    if [ -d "$1" ]; then
        du -sh "$1" 2>/dev/null | cut -f1
    else
        echo "0B"
    fi
}

get_size_bytes() {
    if [ -d "$1" ] || [ -f "$1" ]; then
        du -sb "$1" 2>/dev/null | cut -f1
    else
        echo "0"
    fi
}

convert_bytes() {
    local bytes=$1
    if [ "$bytes" -gt 1073741824 ]; then
        echo "$(( bytes / 1073741824 ))GB"
    elif [ "$bytes" -gt 1048576 ]; then
        echo "$(( bytes / 1048576 ))MB"
    elif [ "$bytes" -gt 1024 ]; then
        echo "$(( bytes / 1024 ))KB"
    else
        echo "${bytes}B"
    fi
}

declare -A cleaned_items
total_cleaned_bytes=0

add_cleaned_item() {
    local name="$1"
    local size_bytes="$2"
    cleaned_items["$name"]="$size_bytes"
    total_cleaned_bytes=$((total_cleaned_bytes + size_bytes))
}

show_cleanup_summary() {
    echo
    echo "=== CLEANUP SUMMARY ==="
    if [ ${#cleaned_items[@]} -eq 0 ]; then
        echo "No items were cleaned."
        return
    fi
    
    echo "Items cleaned:"
    for item in "${!cleaned_items[@]}"; do
        size=$(convert_bytes "${cleaned_items[$item]}")
        echo "  • $item: $size"
    done
    echo
    echo "Total space freed: $(convert_bytes $total_cleaned_bytes)"
    echo
    
    unset cleaned_items
    declare -A cleaned_items
    total_cleaned_bytes=0
}

clean_apt_cache() {
    echo "[*] Cleaning APT cache..."
    apt_size=$(get_size_bytes /var/cache/apt)
    sudo apt clean
    sudo apt autoclean
    sudo apt autoremove -y
    add_cleaned_item "APT cache" "$apt_size"
    echo "[✓] APT cache cleaned"
}

clean_snap_cache() {
    if command -v snap >/dev/null 2>&1; then
        echo "[*] Cleaning Snap cache..."
        snap_size=$(get_size_bytes /var/lib/snapd/cache)
        snap_versions=$(snap list --all | awk '/disabled/{print $1, $3}' | while read snapname revision; do
            sudo snap remove "$snapname" --revision="$revision" 2>/dev/null
        done)
        add_cleaned_item "Snap cache" "$snap_size"
        echo "[✓] Snap cache cleaned"
    else
        echo "[!] Snap not installed"
    fi
}

clean_flatpak_cache() {
    if command -v flatpak >/dev/null 2>&1; then
        echo "[*] Cleaning Flatpak cache..."
        flatpak_size=$(get_size_bytes ~/.local/share/flatpak)
        flatpak uninstall --unused -y 2>/dev/null
        sudo flatpak repair 2>/dev/null
        add_cleaned_item "Flatpak cache" "$flatpak_size"
        echo "[✓] Flatpak cache cleaned"
    else
        echo "[!] Flatpak not installed"
    fi
}

clean_system_logs() {
    echo "[*] Cleaning system logs..."
    log_size=$(get_size_bytes /var/log)
    sudo journalctl --vacuum-time=7d
    sudo find /var/log -type f -name "*.log" -mtime +30 -delete 2>/dev/null
    sudo find /var/log -type f -name "*.gz" -delete 2>/dev/null
    new_log_size=$(get_size_bytes /var/log)
    cleaned_size=$((log_size - new_log_size))
    add_cleaned_item "System logs" "$cleaned_size"
    echo "[✓] System logs cleaned"
}

clean_temp_files() {
    echo "[*] Cleaning temporary files..."
    tmp_size=$(get_size_bytes /tmp)
    var_tmp_size=$(get_size_bytes /var/tmp)
    cache_size=$(get_size_bytes ~/.cache)
    trash_size=$(get_size_bytes ~/.local/share/Trash)
    total_temp_size=$((tmp_size + var_tmp_size + cache_size + trash_size))
    
    sudo rm -rf /tmp/* 2>/dev/null
    sudo rm -rf /var/tmp/* 2>/dev/null
    rm -rf ~/.cache/* 2>/dev/null
    rm -rf ~/.local/share/Trash/* 2>/dev/null
    
    add_cleaned_item "Temporary files" "$total_temp_size"
    echo "[✓] Temporary files cleaned"
}

clean_thumbnails() {
    echo "[*] Cleaning thumbnails..."
    thumb_size1=$(get_size_bytes ~/.thumbnails)
    thumb_size2=$(get_size_bytes ~/.cache/thumbnails)
    total_thumb_size=$((thumb_size1 + thumb_size2))
    
    rm -rf ~/.thumbnails/* 2>/dev/null
    rm -rf ~/.cache/thumbnails/* 2>/dev/null
    
    add_cleaned_item "Thumbnails" "$total_thumb_size"
    echo "[✓] Thumbnails cleaned"
}

clean_browser_cache() {
    echo "[*] Cleaning browser cache..."
    
    chrome_size=$(get_size_bytes ~/.cache/google-chrome)
    chromium_size=$(get_size_bytes ~/.cache/chromium)
    firefox_size=$(get_size_bytes ~/.cache/mozilla)
    opera_size=$(get_size_bytes ~/.cache/opera)
    brave_size=$(get_size_bytes ~/.config/BraveSoftware/Brave-Browser/Default/Cache)
    total_browser_size=$((chrome_size + chromium_size + firefox_size + opera_size + brave_size))
    
    rm -rf ~/.cache/google-chrome/* 2>/dev/null
    rm -rf ~/.cache/chromium/* 2>/dev/null
    rm -rf ~/.mozilla/firefox/*/Cache/* 2>/dev/null
    rm -rf ~/.cache/mozilla/* 2>/dev/null
    rm -rf ~/.cache/opera/* 2>/dev/null
    rm -rf ~/.config/BraveSoftware/Brave-Browser/Default/Cache/* 2>/dev/null
    
    add_cleaned_item "Browser cache" "$total_browser_size"
    echo "[✓] Browser cache cleaned"
}

clean_old_kernels() {
    echo "[*] Removing old kernels..."
    current_kernel=$(uname -r)
    old_kernels=$(dpkg --list | grep linux-image | awk '{print $2}' | grep -v "$current_kernel" | grep -E "^linux-image-[0-9]")
    
    if [ -n "$old_kernels" ]; then
        kernel_count=$(echo "$old_kernels" | wc -l)
        kernel_size=$((kernel_count * 300000000))
        echo "$old_kernels" | xargs sudo apt remove -y
        add_cleaned_item "Old kernels ($kernel_count items)" "$kernel_size"
        echo "[✓] Old kernels removed"
    else
        echo "[!] No old kernels found"
    fi
}

show_disk_usage() {
    echo
    echo "=== DISK USAGE ANALYSIS ==="
    echo "Total disk usage:"
    df -h / | tail -1
    echo
    echo "Largest directories in /home:"
    du -sh ~/.* 2>/dev/null | sort -hr | head -10
    echo
    echo "Cache sizes:"
    echo "APT cache: $(get_size /var/cache/apt)"
    echo "User cache: $(get_size ~/.cache)"
    echo "System logs: $(get_size /var/log)"
    echo "Temp files: $(get_size /tmp) + $(get_size /var/tmp)"
    echo "Trash: $(get_size ~/.local/share/Trash)"
}

full_system_clean() {
    echo "[*] Starting full system cleanup..."
    clean_apt_cache
    clean_snap_cache
    clean_flatpak_cache
    clean_system_logs
    clean_temp_files
    clean_thumbnails
    clean_browser_cache
    echo
    echo "[✓] Full system cleanup completed!"
    show_cleanup_summary
}

main_menu() {
    echo "====== SYSTEM CLEANER MENU ======"
    echo "1. Quick clean (APT + Temp + Cache)"
    echo "2. Full system cleanup"
    echo "3. Clean APT cache only"
    echo "4. Clean Snap cache"
    echo "5. Clean Flatpak cache"
    echo "6. Clean system logs"
    echo "7. Clean temporary files"
    echo "8. Clean thumbnails"
    echo "9. Clean browser cache"
    echo "10. Remove old kernels"
    echo "11. Show disk usage"
    echo "12. Exit"
    read -p "Choose option (1-12): " choice
    
    case $choice in
        1)
            clean_apt_cache
            clean_temp_files
            rm -rf ~/.cache/* 2>/dev/null
            echo "[✓] Quick cleanup completed!"
            show_cleanup_summary
            ;;
        2) full_system_clean ;;
        3) 
            clean_apt_cache
            show_cleanup_summary
            ;;
        4) 
            clean_snap_cache
            show_cleanup_summary
            ;;
        5) 
            clean_flatpak_cache
            show_cleanup_summary
            ;;
        6) 
            clean_system_logs
            show_cleanup_summary
            ;;
        7) 
            clean_temp_files
            show_cleanup_summary
            ;;
        8) 
            clean_thumbnails
            show_cleanup_summary
            ;;
        9) 
            clean_browser_cache
            show_cleanup_summary
            ;;
        10) 
            clean_old_kernels
            show_cleanup_summary
            ;;
        11) show_disk_usage ;;
        12) exit 0 ;;
        *) echo "[!] Invalid option" ;;
    esac
}

while true; do
    main_menu
    echo
    read -p "Press Enter to continue or Ctrl+C to exit..."
    echo
done