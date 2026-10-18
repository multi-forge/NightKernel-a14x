#!/system/bin/sh
# NightKernel Comprehensive Benchmark Suite (NightBench)
# Powered by Benchkit, FIO, Cyclictest, Hackbench, Schbench, Stress-ng, Perfetto
# For Samsung Galaxy A14 5G (Exynos 1330 / a14x / Linux 5.15)

VERSION="1.0.0"
OUTPUT_DIR="/data/local/tmp/nightbench_reports"
mkdir -p "$OUTPUT_DIR"

export PATH="/data/adb/ksu/bin:/system/bin:/system/xbin:$PATH"

log_header() {
    echo "=========================================================="
    echo "=== $1"
    echo "=========================================================="
}

run_sched_bench() {
    log_header "1. SCHEDULER WAKEUP & IPC PIPELINE BENCHMARKS"
    
    echo "[+] Running hackbench (Process IPC & Contention)..."
    echo "--- Hackbench Results ---"
    hackbench -l 500 -g 2 2>&1
    echo ""
    
    echo "[+] Running schbench (Scheduler Wakeup Latency Percentiles)..."
    echo "--- Schbench Results (5s run) ---"
    schbench -m 2 -t 4 -r 5 2>&1
    echo ""
}

run_rt_bench() {
    log_header "2. REAL-TIME LATENCY & TIMER JITTER (cyclictest)"
    
    echo "[+] Running cyclictest (5000 loops, priority 99, 1000us interval)..."
    cyclictest -l 5000 -p 99 -i 1000 -m -q 2>&1
    echo ""
}

run_io_bench() {
    log_header "3. UFS 2.2 STORAGE I/O BENCHMARKS (fio)"
    local testfile="/data/local/tmp/nightbench_fio.dat"
    rm -f "$testfile"
    
    echo "[+] Test A: Sequential Read 64MB / 1MB Block (Game Asset Loading Simulation)..."
    fio --name=asset_seq_read --filename="$testfile" --rw=read --bs=1m --size=64m \
        --iodepth=4 --direct=1 --ioengine=sync --runtime=5 --time_based=0 2>&1 | grep -E "READ:|clat \("
    echo ""
    
    echo "[+] Test B: Random 4KB Writes 16MB (Dirty Pages Flush & Background Write)..."
    fio --name=dirty_rnd_write --filename="$testfile" --rw=randwrite --bs=4k --size=16m \
        --iodepth=4 --direct=0 --ioengine=sync --runtime=5 --time_based=0 2>&1 | grep -E "WRITE:|clat \("
    echo ""
    rm -f "$testfile"
}

run_mem_bench() {
    log_header "4. MEMORY BANDWIDTH & LOADED LATENCY BENCHMARKS"
    
    echo "[+] Memory Bandwidth (memcpy 64MB x 5 passes)..."
    memcpy 64 5 2>&1
    echo ""
    
    echo "[+] Loaded Memory Latency (Memory throughput under 4x CPU background load)..."
    stress-ng --cpu 4 --timeout 3s --quiet &
    local stress_pid=$!
    sleep 0.5
    memcpy 64 3 2>&1
    wait $stress_pid 2>/dev/null
    echo ""
}

run_sleep_bench() {
    log_header "5. CLUSTER POWER COLLAPSE & DEEP SLEEP VALIDATION"
    
    echo "[*] Sampling CPU 6 (Cortex-A78 Big) Cpuidle States..."
    for s in /sys/devices/system/cpu/cpu6/cpuidle/state*; do
        local name=$(cat "$s/name" 2>/dev/null)
        local time=$(cat "$s/time" 2>/dev/null)
        local usage=$(cat "$s/usage" 2>/dev/null)
        echo "    State: $name | Residency: ${time} us | Invocations: $usage"
    done
    echo ""
    echo "[i] To validate screen-off deep sleep transition:"
    echo "    1. Lock the device screen (screen-off)."
    echo "    2. Wait 10 seconds."
    echo "    3. Unlock and re-run 'nightbench sleep' to confirm hercules-cpu-sl (power collapse) time increased."
    echo ""
}

run_trace_bench() {
    log_header "6. SYSTEM-WIDE PERFETTO SCHEDULER & POWER TRACE"
    local duration="${1:-10s}"
    local outfile="/data/local/tmp/nightbench_trace.pftrace"
    
    echo "[+] Recording $duration trace of scheduler switches, CPU frequency & cpuidle states..."
    echo "[i] File output: $outfile"
    /system/bin/perfetto -t "$duration" -o "$outfile" sched/sched_switch sched/sched_wakeup power/cpu_frequency power/cpu_idle 2>&1
    echo ""
    echo "[✓] Trace complete! Open $outfile in https://ui.perfetto.dev to inspect execution timelines."
    echo ""
}

show_help() {
    echo "NightBench — Benchmark Suite for NightKernel (v$VERSION)"
    echo "Usage: nightbench <command> [args]"
    echo ""
    echo "Commands:"
    echo "  sched        - Scheduler wakeup latency (schbench) and IPC contention (hackbench)"
    echo "  rt           - Real-time latency and timer jitter (cyclictest)"
    echo "  io           - UFS 2.2 sequential read (asset load) & random write (fio)"
    echo "  mem          - Memory bandwidth (memcpy) & loaded latency (stress-ng)"
    echo "  sleep        - Big cluster cpuidle states & power collapse residency verification"
    echo "  trace [time] - Record system-wide Perfetto trace (default: 10s) for scheduler & power states"
    echo "  all          - Execute the complete benchmark suite and display full metrics"
    echo ""
}

case "$1" in
    sched)
        run_sched_bench
        ;;
    rt)
        run_rt_bench
        ;;
    io)
        run_io_bench
        ;;
    mem)
        run_mem_bench
        ;;
    sleep)
        run_sleep_bench
        ;;
    trace)
        run_trace_bench "$2"
        ;;
    all|"")
        echo "=========================================================="
        echo "=== NIGHTBENCH v$VERSION — EXYNOS 1330 FULL KERNEL BENCHMARK"
        echo "=== Timestamp: $(date)"
        echo "=== Kernel: $(uname -r)"
        echo "=========================================================="
        run_sched_bench
        run_rt_bench
        run_io_bench
        run_mem_bench
        run_sleep_bench
        echo "=== NIGHTBENCH COMPLETE ==="
        ;;
    *)
        show_help
        ;;
esac
