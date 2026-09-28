#!/data/data/com.termux/files/usr/bin/bash
# Control and analysis interface for NightKernel Telemetry Tracer

SCRIPT_DIR="/data/data/com.termux/files/home/a14x-workspace/NightKernel/scripts"
TRACER="$SCRIPT_DIR/nightkernel_tracer.sh"
PID_FILE="$SCRIPT_DIR/tracer.pid"
CSV_OUT="/sdcard/Download/nightkernel_trace.csv"
EVENT_LOG="/sdcard/Download/nightkernel_events.log"

case "$1" in
    start)
        if [ -f "$PID_FILE" ]; then
            PID=$(cat "$PID_FILE")
            if su -c "kill -0 $PID 2>/dev/null"; then
                echo "Tracer is already running (PID: $PID)."
                exit 0
            fi
        fi
        echo "Starting NightKernel Telemetry Tracer in background (immune to LMK)..."
        su -c "nohup sh $TRACER >/dev/null 2>&1 &"
        sleep 1
        PID=$(su -c "pgrep -f nightkernel_tracer.sh | head -n 1")
        echo "NightKernel Tracer active (PID: $PID)."
        echo "Logging metrics to: $CSV_OUT"
        echo "Kernel alerts to:   $EVENT_LOG"
        ;;

    status)
        PID=$(su -c "pgrep -f nightkernel_tracer.sh | head -n 1")
        if [ -n "$PID" ]; then
            OOM_ADJ=$(su -c "cat /proc/$PID/oom_score_adj 2>/dev/null" || echo "unknown")
            SAMPLES=$(wc -l < "$CSV_OUT" 2>/dev/null || echo 0)
            echo "Status: RUNNING (PID: $PID, OOM Score Adj: $OOM_ADJ - Immune to LMK)"
            echo "Total samples recorded: $(( SAMPLES > 0 ? SAMPLES - 1 : 0 ))"
            if [ -f "$CSV_OUT" ] && [ "$SAMPLES" -gt 1 ]; then
                echo "Latest Reading:"
                tail -n 1 "$CSV_OUT"
            fi
        else
            echo "Status: STOPPED."
            if [ -f "$CSV_OUT" ]; then
                SAMPLES=$(wc -l < "$CSV_OUT")
                echo "Existing dataset contains $(( SAMPLES - 1 )) samples."
            fi
        fi
        ;;

    stop)
        PID=$(su -c "pgrep -f nightkernel_tracer.sh")
        if [ -n "$PID" ]; then
            echo "Stopping NightKernel Tracer (PID: $PID)..."
            su -c "kill $PID 2>/dev/null || true"
            rm -f "$PID_FILE"
            echo "Tracer stopped."
        else
            echo "Tracer is not running."
        fi
        ;;

    analyze)
        python3 "$SCRIPT_DIR/analyze_trace.py"
        ;;

    *)
        echo "Usage: $0 {start|status|stop|analyze}"
        exit 1
        ;;
esac
