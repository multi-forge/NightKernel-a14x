#!/system/bin/sh
# ============================================================
# NightKernel v1.3 — Runtime Optimization Script
# SM-A146M (Exynos 1330) · Linux 5.15 · One UI 7
# Apply via: su -c sh /sdcard/nightkernel_v13_tweaks.sh
# ============================================================

# === 1. DAEMONS PARASITAS (Knox/TEE loop com bootloader desbloqueado) ===
stop vaultkeeper 2>/dev/null
stop vaultkeeper_hal 2>/dev/null
stop proca 2>/dev/null
stop cass 2>/dev/null

# === 2. SENSORHUB (reduzir spam de logs + power governor) ===
echo 0 > /sys/devices/platform/119f0000.contexthub/loglevel 2>/dev/null
echo 2 > /sys/devices/platform/119f0000.contexthub/dfs_gov 2>/dev/null

# === 3. MEMÓRIA & SWAP ===
echo 100 > /proc/sys/vm/swappiness
echo 2 > /proc/sys/vm/page-cluster
echo 32768 > /proc/sys/vm/min_free_kbytes
echo 50 > /proc/sys/vm/watermark_scale_factor
echo 75 > /proc/sys/vm/vfs_cache_pressure
echo 10 > /proc/sys/vm/dirty_ratio
echo 5 > /proc/sys/vm/dirty_background_ratio
echo 100 > /proc/sys/vm/dirty_expire_centisecs
echo 300 > /proc/sys/vm/dirty_writeback_centisecs
echo 3 > /proc/sys/vm/drop_caches 2>/dev/null

# === 4. SCHEDULER ===
echo 0 > /proc/sys/kernel/sched_schedstats 2>/dev/null
echo 2 > /proc/sys/kernel/sched_pelt_multiplier 2>/dev/null
echo HRTICK > /sys/kernel/debug/sched/features 2>/dev/null

# === 5. PRINTK & DEBUG ===
echo "4 4 1 7" > /proc/sys/kernel/printk
echo 0 > /sys/kernel/gpu/debug_level 2>/dev/null

# === 6. INPUT BOOSTER (touch response) ===
echo "170 1632000 1014000 0" > /sys/class/input_booster/touch/head 2>/dev/null
echo "1000 1632000 1014000 0" > /sys/class/input_booster/multitouch/head 2>/dev/null

# === 7. GPU (scale up faster, disable blur) ===
echo 70 > /sys/class/misc/mali0/device/highspeed_load 2>/dev/null

# === 8. I/O (mq-deadline + readahead) ===
for dev in sda sdb sdc; do
  [ -d /sys/block/$dev/queue ] && {
    echo mq-deadline > /sys/block/$dev/queue/scheduler
    echo 256 > /sys/block/$dev/queue/read_ahead_kb
    echo 2 > /sys/block/$dev/queue/rq_affinity
  }
done

# === 9. IRQ BALANCING (desafogar CPU0) ===
echo 2-3 > /proc/irq/163/smp_affinity_list 2>/dev/null  # Mali GPU
echo 2-3 > /proc/irq/165/smp_affinity_list 2>/dev/null  # Mali GPU
echo 1-2 > /proc/irq/107/smp_affinity_list 2>/dev/null  # Display DSI
echo 1-2 > /proc/irq/109/smp_affinity_list 2>/dev/null  # Display DECON
echo 1-2 > /proc/irq/116/smp_affinity_list 2>/dev/null  # Touch I2C

# === 10. CPUSET (isolar background nos LITTLE) ===
echo 0-3 > /dev/cpuset/restricted/cpus 2>/dev/null
echo 0-3 > /dev/cpuset/system-background/cpus 2>/dev/null
echo 0-5 > /dev/cpuset/midground/cpus 2>/dev/null

# === 11. REDE ===
echo bbr > /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null
echo 3 > /proc/sys/net/ipv4/tcp_fastopen

# === 12. INTERFACE (blur off + animations 0.5x) ===
settings put global disable_window_blurs 1 2>/dev/null
settings put global window_animation_scale 0.5
settings put global transition_animation_scale 0.5
settings put global animator_duration_scale 0.5

# === 13. PROTEGER PROCESSOS CRÍTICOS ===
launcher_pid=$(pidof com.sec.android.app.launcher)
[ -n "$launcher_pid" ] && echo -800 > /proc/$launcher_pid/oom_score_adj

# Pre-heat SystemUI + Launcher no pagecache
cat /system/system_ext/priv-app/SystemUI/SystemUI.apk > /dev/null 2>&1 &
cat /system/system_ext/priv-app/SystemUI/oat/arm64/SystemUI.odex > /dev/null 2>&1 &
cat /system/priv-app/TouchWizHome_2017/TouchWizHome_2017.apk > /dev/null 2>&1 &

echo "[NightKernel] v1.3 runtime optimizations applied ✓"
