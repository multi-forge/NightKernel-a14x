#!/bin/sh
# NightKernel Unkillable Telemetry & Performance Tracer
# Designed for low-overhead (<0.05% CPU) monitoring during heavy 3D gaming & daily driving.

CSV_OUT="/sdcard/Download/nightkernel_trace.csv"
EVENT_LOG="/sdcard/Download/nightkernel_events.log"
PID_FILE="/data/data/com.termux/files/home/a14x-workspace/NightKernel/scripts/tracer.pid"

# 1. Immune to Android Low Memory Killer (LMK)
echo -1000 > /proc/$$/oom_score_adj 2>/dev/null

# 2. Lowest CPU priority so it never steals cycles from game render threads
renice -n 19 $$ 2>/dev/null

# Save PID
echo $$ > "$PID_FILE"

# Initialize CSV header if not exists
if [ ! -f "$CSV_OUT" ]; then
    echo "timestamp,uptime_s,cpu_little_mhz,cpu_big_mhz,gpu_util,temp_big_c,temp_little_c,temp_gpu_c,temp_batt_c,ram_avail_mb,zram_used_mb,psi_cpu_10,psi_mem_10,psi_io_10,batt_ma,batt_pct" > "$CSV_OUT"
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] NightKernel tracer started (PID: $$)" >> "$EVENT_LOG"

LAST_DMESG_LINES=0
if command -v dmesg >/dev/null 2>&1; then
    LAST_DMESG_LINES=$(dmesg | wc -l)
fi

while true; do
    TS=$(date '+%Y-%m-%d %H:%M:%S')
    UPTIME=$(cut -d. -f1 /proc/uptime 2>/dev/null || echo 0)

    # CPU Frequencies
    LITTLE_FREQ=$(cat /sys/devices/system/cpu/cpufreq/policy0/scaling_cur_freq 2>/dev/null || echo 0)
    BIG_FREQ=$(cat /sys/devices/system/cpu/cpufreq/policy6/scaling_cur_freq 2>/dev/null || echo 0)
    LITTLE_MHZ=$(( LITTLE_FREQ / 1000 ))
    BIG_MHZ=$(( BIG_FREQ / 1000 ))

    # GPU Utilization
    GPU_UTIL=$(cat /sys/devices/platform/10300000.mali/utilization 2>/dev/null || echo 0)

    # Thermal Zones
    TEMP_BIG_RAW=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 0)
    TEMP_LITTLE_RAW=$(cat /sys/class/thermal/thermal_zone1/temp 2>/dev/null || echo 0)
    TEMP_GPU_RAW=$(cat /sys/class/thermal/thermal_zone2/temp 2>/dev/null || echo 0)
    TEMP_BATT_RAW=$(cat /sys/class/thermal/thermal_zone6/temp 2>/dev/null || echo 0)

    TEMP_BIG=$(( TEMP_BIG_RAW / 1000 ))
    TEMP_LITTLE=$(( TEMP_LITTLE_RAW / 1000 ))
    TEMP_GPU=$(( TEMP_GPU_RAW / 1000 ))
    TEMP_BATT=$(( TEMP_BATT_RAW / 1000 ))

    # Memory
    MEM_AVAIL_KB=$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}')
    MEM_AVAIL_MB=$(( ${MEM_AVAIL_KB:-0} / 1024 ))
    
    ZRAM_USED_KB=$(grep zram0 /proc/swaps 2>/dev/null | awk '{print $4}')
    ZRAM_USED_MB=$(( ${ZRAM_USED_KB:-0} / 1024 ))

    # Pressure Stall Information (avg10)
    PSI_CPU=$(grep "some" /proc/pressure/cpu 2>/dev/null | sed -n 's/.*avg10=\([0-9.]*\).*/\1/p')
    PSI_MEM=$(grep "some" /proc/pressure/memory 2>/dev/null | sed -n 's/.*avg10=\([0-9.]*\).*/\1/p')
    PSI_IO=$(grep "some" /proc/pressure/io 2>/dev/null | sed -n 's/.*avg10=\([0-9.]*\).*/\1/p')

    # Battery
    BATT_MA=$(cat /sys/class/power_supply/battery/current_now 2>/dev/null || echo 0)
    BATT_PCT=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null || echo 0)

    # Write CSV line
    echo "$TS,$UPTIME,$LITTLE_MHZ,$BIG_MHZ,$GPU_UTIL,$TEMP_BIG,$TEMP_LITTLE,$TEMP_GPU,$TEMP_BATT,$MEM_AVAIL_MB,$ZRAM_USED_MB,${PSI_CPU:-0},${PSI_MEM:-0},${PSI_IO:-0},$BATT_MA,$BATT_PCT" >> "$CSV_OUT"

    # Periodic kernel anomaly check (every ~30s or on dmesg growth)
    CURRENT_DMESG_LINES=$(dmesg | wc -l 2>/dev/null || echo 0)
    if [ "$CURRENT_DMESG_LINES" -gt "$LAST_DMESG_LINES" ]; then
        DIFF=$(( CURRENT_DMESG_LINES - LAST_DMESG_LINES ))
        NEW_ERRORS=$(dmesg | tail -n "$DIFF" | grep -iE 'panic|oops|bug:|warn|call trace|oom-killer|freeze|stuck|timeout')
        if [ -n "$NEW_ERRORS" ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Kernel Alert:" >> "$EVENT_LOG"
            echo "$NEW_ERRORS" >> "$EVENT_LOG"
        fi
        LAST_DMESG_LINES=$CURRENT_DMESG_LINES
    fi

    # 5 second interval is gentle on CPU and captures gaming bursts accurately
    sleep 5
done
