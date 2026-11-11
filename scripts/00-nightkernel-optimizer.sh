#!/system/bin/sh
# ==============================================================================
# NightKernel Zero+ Autonomous Optimizer & Debloater Service
# Runs automatically after boot via KernelSU / Magisk service.d
# ==============================================================================

LOG="/data/local/tmp/nightkernel_optimizer.log"
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG" 2>/dev/null
}

write_val() {
    if [ -e "$1" ]; then
        chmod 0644 "$1" 2>/dev/null
        echo "$2" > "$1" 2>/dev/null
    fi
}

log "=================================================="
log "=== NightKernel Zero+ Optimizer Service Starting ==="
log "=================================================="

# 0. Ensure early kernel node permissions and MGLRU state
if [ -e /dev/ntsync ]; then
    chmod 0666 /dev/ntsync 2>/dev/null || true
    chcon u:object_r:gpu_device:s0 /dev/ntsync 2>/dev/null || true
fi
if [ -e /sys/kernel/mm/lru_gen/enabled ]; then
    echo y > /sys/kernel/mm/lru_gen/enabled 2>/dev/null || true
fi

# 1. Wait for Android boot completion and PackageManager availability
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 2
done

# Re-apply early nodes after init coldboot finishes
if [ -e /dev/ntsync ]; then
    chmod 0666 /dev/ntsync 2>/dev/null || true
    chcon u:object_r:gpu_device:s0 /dev/ntsync 2>/dev/null || true
fi
if [ -e /sys/kernel/mm/lru_gen/enabled ]; then
    echo y > /sys/kernel/mm/lru_gen/enabled 2>/dev/null || true
fi

while ! pm path android >/dev/null 2>&1; do
    sleep 2
done
log "[+] Android Package Manager is fully responsive."

# 2. Next-Gen Performance & Low-Latency Tunables (BORE, uclamp, VM, F2FS, Net)
apply_nextgen_performance_tunables() {
    log "[*] Applying Next-Gen Performance & Low-Latency tunables..."

    # --------------------------------------------------------------------------
    # 1. Escalonador CFS / EMS / BORE & Latencia de Preempcao (Alvo: 90Hz)
    # --------------------------------------------------------------------------
    write_val /proc/sys/kernel/sched_min_granularity_ns 2000000
    write_val /proc/sys/kernel/sched_wakeup_granularity_ns 3000000
    write_val /proc/sys/kernel/sched_migration_cost_ns 500000
    write_val /proc/sys/kernel/sched_latency_ns 10000000
    write_val /proc/sys/kernel/sched_nr_migrate 32
    write_val /proc/sys/kernel/sched_schedstats 0
    write_val /proc/sys/kernel/sched_bore 1
    write_val /proc/sys/kernel/sched_burst_penalty_offset 22
    write_val /proc/sys/kernel/sched_burst_penalty_scale 1280
    write_val /proc/sys/kernel/sched_burst_smoothness_long 1
    write_val /proc/sys/kernel/sched_burst_smoothness_short 0

    # --------------------------------------------------------------------------
    # 2. Utilization Clamping (uclamp) para Fluidez de UI e Controle de Background
    # --------------------------------------------------------------------------
    write_val /dev/cpuset/top-app/uclamp.min 15
    write_val /dev/cpuset/top-app/uclamp.max max
    write_val /dev/cpuset/top-app/uclamp.boosted 1
    write_val /dev/cpuset/top-app/uclamp.latency_sensitive 1

    write_val /dev/cpuset/foreground/uclamp.min 5
    write_val /dev/cpuset/foreground/uclamp.max 80

    write_val /dev/cpuset/background/uclamp.min 0
    write_val /dev/cpuset/background/uclamp.max 50

    write_val /dev/cpuset/system-background/uclamp.min 0
    write_val /dev/cpuset/system-background/uclamp.max 25

    # --------------------------------------------------------------------------
    # 3. Gerenciamento de Memoria Virtual (VM), MGLRU e ZRAM LZ4
    # --------------------------------------------------------------------------
    write_val /sys/kernel/mm/lru_gen/enabled 0x0003
    write_val /sys/kernel/mm/lru_gen/min_ttl_ms 1000

    write_val /proc/sys/vm/page-cluster 0
    write_val /proc/sys/vm/watermark_boost_factor 0
    write_val /proc/sys/vm/watermark_scale_factor 125
    write_val /proc/sys/vm/compaction_proactiveness 0
    write_val /proc/sys/vm/vfs_cache_pressure 60
    write_val /proc/sys/vm/dirty_ratio 20
    write_val /proc/sys/vm/dirty_background_ratio 5
    write_val /proc/sys/vm/stat_interval 10
    write_val /proc/sys/vm/oom_dump_tasks 0

    # --------------------------------------------------------------------------
    # 4. Sistema de Arquivos F2FS e Camada de Bloco UFS 2.2 (blk-mq)
    # --------------------------------------------------------------------------
    mount -o remount,atgc,gc_merge /data 2>/dev/null

    for queue in /sys/block/*/queue; do
        write_val "$queue/iostats" 0
        write_val "$queue/add_random" 0
        write_val "$queue/rq_affinity" 2
        write_val "$queue/nomerges" 0
    done

    for zdev in /sys/block/zram*/queue; do
        write_val "$zdev/read_ahead_kb" 0
    done
    for sdev in /sys/block/sd*/queue; do
        write_val "$sdev/read_ahead_kb" 128
        write_val "$sdev/nr_requests" 64
    done

    # --------------------------------------------------------------------------
    # 5. Rede de Baixa Latencia (TCP BBR, FastOpen, ECN) e eBPF JIT
    # --------------------------------------------------------------------------
    write_val /proc/sys/net/core/bpf_jit_harden 0
    write_val /proc/sys/net/core/default_qdisc fq
    write_val /proc/sys/net/ipv4/tcp_congestion_control bbr
    write_val /proc/sys/net/ipv4/tcp_fastopen 3
    write_val /proc/sys/net/ipv4/tcp_ecn 1
    write_val /proc/sys/net/ipv4/tcp_slow_start_after_idle 0
    write_val /proc/sys/net/ipv4/tcp_low_latency 1

    # --------------------------------------------------------------------------
    # 6. Dynamic Fsync: Safe Default (0 = Inactive, toggle exported)
    # --------------------------------------------------------------------------
    if [ -e /sys/kernel/dyn_fsync/Dyn_fsync_active ]; then
        chmod 0666 /sys/kernel/dyn_fsync/Dyn_fsync_active 2>/dev/null || true
        write_val /sys/kernel/dyn_fsync/Dyn_fsync_active 0
    fi

    # --------------------------------------------------------------------------
    # 7. Persistencia de Nos Criticos (/dev/ntsync) & Teto GPU (949 MHz)
    # --------------------------------------------------------------------------
    if [ -e /dev/ntsync ]; then
        chmod 0666 /dev/ntsync 2>/dev/null || true
        chcon u:object_r:gpu_device:s0 /dev/ntsync 2>/dev/null || true
    fi

    write_val /sys/kernel/gpu/gpu_max_clock 949000
    write_val /sys/kernel/gpu/gpu_min_clock 208000
    write_val /sys/devices/platform/10300000.mali/max_clock 949000
    write_val /sys/devices/platform/10300000.mali/min_clock 208000

    # --------------------------------------------------------------------------
    # 8. Barramento MIF (Memoria) - Escalonamento Dinamico Validado
    # --------------------------------------------------------------------------
    write_val /sys/class/devfreq/17000010.devfreq_mif/governor simple_ondemand 2>/dev/null || true
    write_val /sys/class/devfreq/17000010.devfreq_mif/min_freq 421000
    write_val /sys/class/devfreq/17000010.devfreq_mif/max_freq 2093000
    write_val /sys/class/devfreq/17000010.devfreq_mif/exynos_data/debug_scaling_devfreq_min 421000

    # --------------------------------------------------------------------------
    # 9. HKTweaks Symlinks & Node Permissions
    # --------------------------------------------------------------------------
    # Battery Store Mode symlink & permissions
    if [ ! -d /sys/devices/battery/power_supply/battery ]; then
        mkdir -p /sys/devices/battery/power_supply 2>/dev/null || true
        ln -sf /sys/class/power_supply/battery /sys/devices/battery/power_supply/battery 2>/dev/null || true
    fi
    chmod 0666 /sys/devices/battery/power_supply/battery/store_mode 2>/dev/null || true
    chmod 0666 /sys/class/power_supply/battery/store_mode 2>/dev/null || true
    chmod 0666 /sys/module/sec_battery/parameters/store_mode_max 2>/dev/null || true
    chmod 0666 /sys/module/sec_battery/parameters/store_mode_min 2>/dev/null || true

    # Devfreq Bus aliases for HKTweaks
    if [ -d /sys/class/devfreq/17000040.devfreq_disp ] && [ ! -e /sys/class/devfreq/17000030.devfreq_disp ]; then
        ln -sf /sys/class/devfreq/17000040.devfreq_disp /sys/class/devfreq/17000030.devfreq_disp 2>/dev/null || true
    fi
    if [ -d /sys/class/devfreq/17000060.devfreq_cam ] && [ ! -e /sys/class/devfreq/17000040.devfreq_cam ]; then
        ln -sf /sys/class/devfreq/17000060.devfreq_cam /sys/class/devfreq/17000040.devfreq_cam 2>/dev/null || true
    fi

    # Devfreq volt_table permissions
    chmod 0666 /sys/class/devfreq/*/volt_table 2>/dev/null || true

    # Mali GPU aliases for HKTweaks
    if [ -d /sys/devices/platform/10300000.mali ]; then
        [ ! -e /sys/devices/platform/17500000.mali ] && ln -sf /sys/devices/platform/10300000.mali /sys/devices/platform/17500000.mali 2>/dev/null || true
        [ ! -e /sys/devices/14ac0000.mali ] && ln -sf /sys/devices/platform/10300000.mali /sys/devices/14ac0000.mali 2>/dev/null || true
        chmod 0666 /sys/devices/platform/10300000.mali/* 2>/dev/null || true
    fi

    # CPU Voltages (mp-cpufreq) permissions
    if [ -d /sys/devices/system/cpu/cpufreq/mp-cpufreq ]; then
        chmod 0666 /sys/devices/system/cpu/cpufreq/mp-cpufreq/* 2>/dev/null || true
    fi
    if [ -e /sys/power/little_thermal_temp ]; then
        chmod 0666 /sys/power/little_thermal_temp 2>/dev/null || true
    fi

    # Boeffla Wakelock Blocker permissions
    if [ -d /sys/devices/virtual/misc/boeffla_wakelock_blocker ]; then
        chmod 0666 /sys/devices/virtual/misc/boeffla_wakelock_blocker/* 2>/dev/null || true
    fi

    # MoroSound / Sound Control permissions
    if [ -d /sys/devices/virtual/misc/moro_sound ]; then
        chmod 0666 /sys/devices/virtual/misc/moro_sound/* 2>/dev/null || true
    fi
    if [ -d /sys/kernel/sound_control ]; then
        chmod 0666 /sys/kernel/sound_control/* 2>/dev/null || true
    fi

    # --------------------------------------------------------------------------
    # 10. Spectrum Profiles Initialization & Watcher
    # --------------------------------------------------------------------------
    resetprop -n spectrum.support 1 2>/dev/null || true
    if [ -z "$(getprop persist.spectrum.profile)" ]; then
        resetprop -n persist.spectrum.profile 0 2>/dev/null || true
    fi

    log "[+] Next-Gen Performance tunables applied successfully."
}

apply_nextgen_performance_tunables

# 3. Approved Debloat List (Safeguards: FMM and GameTools kept intact)
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

# 4. Spectrum Profiles Dynamic Listener Daemon
(
    LAST_PROFILE="-1"
    while true; do
        CUR_PROFILE="$(getprop persist.spectrum.profile)"
        if [ "$CUR_PROFILE" != "$LAST_PROFILE" ]; then
            LAST_PROFILE="$CUR_PROFILE"
            case "$CUR_PROFILE" in
                0) # Balance
                    write_val /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor schedutil
                    write_val /sys/devices/system/cpu/cpu6/cpufreq/scaling_governor schedutil
                    write_val /sys/kernel/gpu/gpu_max_clock 949000
                    write_val /sys/devices/platform/10300000.mali/max_clock 949000
                    write_val /sys/class/devfreq/17000010.devfreq_mif/min_freq 421000
                    write_val /sys/class/devfreq/17000010.devfreq_mif/max_freq 2093000
                    cmd wifi force-low-latency-mode disabled 2>/dev/null || true
                    ;;
                1) # Performance
                    write_val /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor schedutil
                    write_val /sys/devices/system/cpu/cpu6/cpufreq/scaling_governor performance
                    write_val /sys/kernel/gpu/gpu_max_clock 949000
                    write_val /sys/devices/platform/10300000.mali/max_clock 949000
                    write_val /sys/class/devfreq/17000010.devfreq_mif/min_freq 1014000
                    write_val /sys/class/devfreq/17000010.devfreq_mif/max_freq 2093000
                    cmd wifi force-low-latency-mode enabled 2>/dev/null || true
                    ;;
                2) # Battery
                    write_val /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor powersave
                    write_val /sys/devices/system/cpu/cpu6/cpufreq/scaling_governor powersave
                    write_val /sys/kernel/gpu/gpu_max_clock 611000
                    write_val /sys/devices/platform/10300000.mali/max_clock 611000
                    write_val /sys/class/devfreq/17000010.devfreq_mif/min_freq 421000
                    write_val /sys/class/devfreq/17000010.devfreq_mif/max_freq 1541000
                    cmd wifi force-low-latency-mode disabled 2>/dev/null || true
                    ;;
                3) # Gaming
                    write_val /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor performance
                    write_val /sys/devices/system/cpu/cpu6/cpufreq/scaling_governor performance
                    write_val /sys/kernel/gpu/gpu_max_clock 949000
                    write_val /sys/devices/platform/10300000.mali/max_clock 949000
                    write_val /sys/class/devfreq/17000010.devfreq_mif/min_freq 1352000
                    write_val /sys/class/devfreq/17000010.devfreq_mif/max_freq 2093000
                    write_val /sys/class/devfreq/17000000.devfreq_dsu/min_freq 1440000 2>/dev/null || true
                    cmd wifi force-low-latency-mode enabled 2>/dev/null || true
                    ;;
            esac
        fi
        sleep 3
    done
) &

# 5. Autonomous SSHD Watchdog Daemon
log "[*] Spawning autonomous SSHD watchdog daemon..."
(
    while true; do
        if ! pidof sshd >/dev/null 2>&1; then
            if [ -x "/data/data/com.termux/files/usr/bin/sshd" ]; then
                su 10288 -c "PATH=/data/data/com.termux/files/usr/bin:$PATH HOME=/data/data/com.termux/files/home PREFIX=/data/data/com.termux/files/usr /data/data/com.termux/files/usr/bin/sshd -p 8022" >/dev/null 2>&1
            fi
        fi
        sleep 5
    done
) &

log "=== NightKernel Zero+ Optimizer Execution Complete ==="
