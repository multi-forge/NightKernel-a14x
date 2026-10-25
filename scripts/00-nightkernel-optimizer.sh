#!/system/bin/sh
# ==============================================================================
# NightKernel v3.1 Autonomous Optimizer & Debloater Service
# Runs automatically after boot via KernelSU / Magisk service.d
# ==============================================================================

LOG="/data/local/tmp/nightkernel_optimizer.log"
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG" 2>/dev/null
}

log "=================================================="
log "=== NightKernel v3.1 Optimizer Service Starting ==="
log "=================================================="

# 1. Wait for Android boot completion and PackageManager availability
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 2
done

while ! pm path android >/dev/null 2>&1; do
    sleep 2
done
log "[+] Android Package Manager is fully responsive."

# 2. Approved Debloat List (Safeguards: FMM and GameTools kept intact)
DEBLOAT_PACKAGES="
com.sec.android.sdhms
com.samsung.android.oneconnect
com.sec.android.diagmonagent
com.facebook.services
com.facebook.system
com.facebook.appmanager
com.wssyncmldm
com.samsung.android.rubin.app
com.samsung.android.smartswitchassistant
com.sec.android.easyMover.Agent
com.samsung.android.game.gamehome
com.sec.enterprise.knox.cloudmdm.smdms
com.samsung.android.mdm
com.samsung.android.app.watchmanagerstub
com.samsung.android.aircommandmanager
com.samsung.android.uds
android.autoinstalls.config.samsung
com.sec.android.app.wlantest
com.sec.phone
com.sec.bcservice
com.sec.app.RilErrorNotifier
com.wsomacp
com.android.providers.partnerbookmarks
com.sec.android.app.chromecustomizations
com.google.android.feedback
com.google.android.printservice.recommendation
"

log "[*] Disabling approved bloatware, tracking, and OTA agents..."
DISABLED_COUNT=0
for pkg in $DEBLOAT_PACKAGES; do
    if pm list packages "$pkg" 2>/dev/null | grep -q "$pkg"; then
        pm disable-user --user 0 "$pkg" >/dev/null 2>&1
        pkill -f "$pkg" >/dev/null 2>&1
        log "    [-] Disabled & killed: $pkg"
        DISABLED_COUNT=$((DISABLED_COUNT + 1))
    fi
done

log "[+] Total packages disabled: $DISABLED_COUNT"
log "[i] Safety Preserved: com.samsung.android.fmm (Find My Mobile)"
log "[i] Safety Preserved: com.samsung.android.game.gametools"

# 3. Autonomous SSHD Watchdog Daemon
log "[*] Spawning autonomous SSHD watchdog daemon..."
(
    while true; do
        if ! pgrep -f "sshd" >/dev/null 2>&1; then
            if [ -x "/data/data/com.termux/files/usr/bin/sshd" ]; then
                su 10288 -c "PATH=/data/data/com.termux/files/usr/bin:$PATH HOME=/data/data/com.termux/files/home PREFIX=/data/data/com.termux/files/usr /data/data/com.termux/files/usr/bin/sshd -p 8022" >/dev/null 2>&1
            fi
        fi
        sleep 5
    done
) &

log "=== NightKernel v3.1 Optimizer Execution Complete ==="
