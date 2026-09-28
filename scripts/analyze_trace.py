#!/usr/bin/env python3
import os
import csv
import sys
from datetime import datetime

CSV_FILE = "/sdcard/Download/nightkernel_trace.csv"
EVENT_FILE = "/sdcard/Download/nightkernel_events.log"

def main():
    if not os.path.exists(CSV_FILE):
        print(f"No trace data found at {CSV_FILE}.")
        return

    rows = []
    with open(CSV_FILE, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for r in reader:
            rows.append(r)

    if not rows:
        print("Trace file is empty.")
        return

    print("=" * 60)
    print("📊 NIGHTKERNEL TELEMETRY & BEHAVIOR ANALYSIS REPORT")
    print("=" * 60)

    total_samples = len(rows)
    start_time = rows[0]["timestamp"]
    end_time = rows[-1]["timestamp"]

    try:
        t0 = datetime.strptime(start_time, "%Y-%m-%d %H:%M:%S")
        t1 = datetime.strptime(end_time, "%Y-%m-%d %H:%M:%S")
        duration_sec = (t1 - t0).total_seconds()
        duration_str = f"{int(duration_sec // 60)}m {int(duration_sec % 60)}s"
    except Exception:
        duration_str = f"{total_samples * 5}s (est.)"

    print(f"• Início da Sessão:      {start_time}")
    print(f"• Fim da Sessão:         {end_time}")
    print(f"• Duração Monitorada:    {duration_str} ({total_samples} amostras)")
    print("-" * 60)

    def stats(col_name, transform=float):
        vals = []
        for r in rows:
            try:
                v = transform(r[col_name])
                vals.append(v)
            except Exception:
                pass
        if not vals:
            return 0, 0, 0
        return min(vals), sum(vals)/len(vals), max(vals)

    # 1. Thermal Analysis
    min_big, avg_big, max_big = stats("temp_big_c")
    min_little, avg_little, max_little = stats("temp_little_c")
    min_gpu, avg_gpu, max_gpu = stats("temp_gpu_c")
    min_batt, avg_batt, max_batt = stats("temp_batt_c")

    print("\n🌡️ COMPORTAMENTO TÉRMICO:")
    print(f"  • CPU Big (Cortex-A78):  Mín: {min_big:.1f}°C | Méd: {avg_big:.1f}°C | Máx: {max_big:.1f}°C")
    print(f"  • CPU Little (Cortex-A55): Mín: {min_little:.1f}°C | Méd: {avg_little:.1f}°C | Máx: {max_little:.1f}°C")
    print(f"  • GPU (Mali-G68):        Mín: {min_gpu:.1f}°C | Méd: {avg_gpu:.1f}°C | Máx: {max_gpu:.1f}°C")
    print(f"  • Bateria:               Mín: {min_batt:.1f}°C | Méd: {avg_batt:.1f}°C | Máx: {max_batt:.1f}°C")

    # 2. CPU Frequencies & Throttling
    min_b_freq, avg_b_freq, max_b_freq = stats("cpu_big_mhz")
    min_l_freq, avg_l_freq, max_l_freq = stats("cpu_little_mhz")
    _, avg_gpu_load, max_gpu_load = stats("gpu_util")

    print("\n⚡ FREQUÊNCIAS & CARGA:")
    print(f"  • Cluster Big (A78):     Méd: {avg_b_freq:.0f} MHz | Máx: {max_b_freq:.0f} MHz")
    print(f"  • Cluster Little (A55):  Méd: {avg_l_freq:.0f} MHz | Máx: {max_l_freq:.0f} MHz")
    print(f"  • Utilização GPU Mali:   Méd: {avg_gpu_load:.1f}% | Pico: {max_gpu_load:.0f}%")

    # Thermal throttle detection: if Big was under 1500MHz while temp > 75C
    throttled_count = 0
    for r in rows:
        try:
            if float(r["temp_big_c"]) >= 75 and float(r["cpu_big_mhz"]) < 1800:
                throttled_count += 1
        except: pass

    if throttled_count > 0:
        pct = (throttled_count / total_samples) * 100
        print(f"  ⚠️ Throttling Térmico detectado em {throttled_count} amostras ({pct:.1f}% do tempo).")
    else:
        print("  ✅ Nenhum Thermal Throttling severo detectado (frequências sustentadas estáveis).")

    # 3. Memory & ZRAM
    min_ram, avg_ram, max_ram = stats("ram_avail_mb")
    min_zram, avg_zram, max_zram = stats("zram_used_mb")

    print("\n🧠 MEMÓRIA & SWAP ZRAM:")
    print(f"  • RAM Disponível:        Mín: {min_ram:.0f} MB | Méd: {avg_ram:.0f} MB")
    print(f"  • ZRAM em Uso:           Méd: {avg_zram:.0f} MB | Pico: {max_zram:.0f} MB")

    # 4. Pressure Stall Information (PSI)
    _, avg_psi_cpu, max_psi_cpu = stats("psi_cpu_10")
    _, avg_psi_mem, max_psi_mem = stats("psi_mem_10")
    _, avg_psi_io, max_psi_io = stats("psi_io_10")

    print("\n⏱️ ESTABILIDADE & STALLS (PSI):")
    print(f"  • CPU Pressure (avg10):  Méd: {avg_psi_cpu:.2f}% | Pico: {max_psi_cpu:.2f}%")
    print(f"  • Memory Pressure:       Méd: {avg_psi_mem:.2f}% | Pico: {max_psi_mem:.2f}%")
    print(f"  • I/O Storage Pressure:  Méd: {avg_psi_io:.2f}% | Pico: {max_psi_io:.2f}%")

    if max_psi_mem > 15.0:
        print("  ⚠️ Alerta de pressão de memória alta (possível contenção de cache/ZRAM).")
    else:
        print("  ✅ Pressão de memória e I/O dentro dos parâmetros ideais (sem micro-travamentos).")

    # 5. Battery Drain
    min_ma, avg_ma, max_ma = stats("batt_ma")
    p0 = float(rows[0]["batt_pct"]) if rows[0].get("batt_pct") else 0
    p1 = float(rows[-1]["batt_pct"]) if rows[-1].get("batt_pct") else 0
    drop = p0 - p1

    print("\n🔋 BATERIA:")
    print(f"  • Nível Inicial / Final: {p0:.0f}% -> {p1:.0f}% (Variação: {drop:+.0f}%)")
    print(f"  • Corrente de Descarga:  Méd: {abs(avg_ma):.0f} mA | Pico: {abs(max_ma):.0f} mA")

    # 6. Kernel Events / Dmesg alerts
    print("\n🛡️ INTEGRIDADE DO KERNEL:")
    if os.path.exists(EVENT_FILE) and os.path.getsize(EVENT_FILE) > 0:
        with open(EVENT_FILE, "r", encoding="utf-8", errors="replace") as ef:
            events = ef.read().strip()
        lines = [l for l in events.splitlines() if "tracer started" not in l]
        if lines:
            print(f"  ⚠️ {len(lines)} eventos/alertas registrados no kernel:")
            for l in lines[:5]:
                print(f"    - {l}")
            if len(lines) > 5:
                print(f"    - ... e mais {len(lines) - 5} alertas (veja {EVENT_FILE}).")
        else:
            print("  ✅ Nenhum erro, warning ou instabilidade registrado no dmesg durante o teste!")
    else:
        print("  ✅ Nenhum erro, warning ou instabilidade registrado no dmesg durante o teste!")

    print("=" * 60)

if __name__ == "__main__":
    main()
