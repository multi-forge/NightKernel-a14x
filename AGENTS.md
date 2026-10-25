# Repository Guidelines

## Project Overview
**NightKernel** is a high-performance custom Linux 5.15 LTS kernel engineered for the **Samsung Galaxy A14 5G** (`SM-A146M` / `SM-A146B`, codename `a14x` / SoC Exynos 1330 `s5e8535`) running **Android 15 (Samsung One UI 7)** with Dual-Binary D & E bootloader compatibility (`A146MUBSDDZE1`).

> **CRITICAL HARDWARE WARNING**: Never flash or build for US variants (`SM-A146U`, `SM-A146U1`, `SM-S146VL`). Those variants use a MediaTek Dimensity 700 SoC and will suffer an unrecoverable hard-brick.

Core objectives:
- **Root Stealth & VFS Isolation**: ReSukiSU 3.0.0 supercall isolation with SuSFS 2.1.0 VFS hiding.
- **Autonomous Recovery Failsafe**: Automatic redirect of kernel panics to TWRP recovery via Samsung PMU registers.
- **Windows Emulation Acceleration**: Native in-kernel Windows NT synchronization primitives via `/dev/ntsync`.
- **Hardware & Radio Security**: Baseband Guard (BBG) LSM module preventing write/wipe damage to `/efs` and radio partitions.
- **Display Tuning**: Hardware DQE KCAL gamma/RGB matrix transformation engine.
- **I/O & Memory Optimization**: MMC CRC software bypass, Multi-Gen LRU (MGLRU), LZ4 ZRAM swap decompression, and aggressive VFS dentry cache retention.

---

## Architecture & Data Flow

```
+-----------------------------------------------------------------------------+
|                                User Space                                   |
|   +--------------------+  +--------------------+  +---------------------+   |
|   | Banking/Root Apps  |  | Wine/Winlator Emul |  | KCAL Display Apps   |   |
|   +--------------------+  +--------------------+  +---------------------+   |
+-------------|-----------------------|------------------------|--------------+
              | Supercalls            | ioctls (/dev/ntsync)   | Sysfs (kcal)
+-------------v-----------------------v------------------------v--------------+
|                             Kernel Subsystems                               |
|   +--------------------+  +--------------------+  +---------------------+   |
|   | ReSukiSU / SuSFS   |  | NTSync Driver      |  | Samsung DQE KCAL    |   |
|   | dispatch.c         |  | ntsync.c           |  | exynos_drm_dqe.c    |   |
|   | (VFS Isolation)    |  | (Mutex/Sem/Events) |  | (S8.14 Matrix Calc) |   |
|   +--------------------+  +--------------------+  +---------------------+   |
|                                                                             |
|   +--------------------+  +--------------------+  +---------------------+   |
|   | Baseband Guard LSM |  | Panic-to-Recovery  |  | Storage & Memory    |   |
|   | security/bbg/      |  | sec_reboot.c       |  | MMC CRC=0, LZ4 ZRAM |   |
|   | (Protects /efs)    |  | (PMU Retention)    |  | MGLRU, vfs_cache=60 |   |
|   +--------------------+  +--------------------+  +---------------------+   |
+-----------------------------------------------------------------------------+
|                                  Hardware                                   |
|         Exynos 1330 (2x Cortex-A78 + 6x Cortex-A55) | Mali-G68 GPU          |
+-----------------------------------------------------------------------------+
```

### High-Level Subsystems & Data Flows
1. **Root Stealth & VFS Isolation**:
   - Userspace calls route through `kernel/supercall/dispatch.c` (`ksu_handle_susfs_cmd`).
   - Hooks in `fs/namespace.c` (`sus_mount`) conceal active root mount points from namespace iteration.
   - Inode redirection (`sus_kstat_redirect`) and memory-map masking (`sus_map`) in `fs/proc/base.c` hide KernelSU binaries and su mounts from root scanners.
   - Runtime kernel release spoofing via `sus_set_uname`.
2. **Panic-to-Recovery Failsafe**:
   - `drivers/samsung/sec_reboot.c`: The kernel panic handler overrides `panic_str` to `"recovery"`, writing `SEC_RESET_REASON_RECOVERY` into Samsung PMU retention registers. Panics reboot straight into TWRP recovery instead of freezing in upload mode.
   - Programmatic trigger: `kernel/reboot.c` exposes `/proc/nightkernel_reboot` (`0666`), enabling instant recovery reboots without a USB PC connection.
3. **Windows NT Synchronization (NTSync)**:
   - `drivers/misc/ntsync.c` provides `/dev/ntsync` with 32-bit ioctl compat (`CONFIG_NTSYNC_COMPAT=y`).
   - Windows compatibility layers (Winlator, Mobox, Box64, Wine-GE) bypass slow `wineserver` IPC by delegating mutex, semaphore, and event wait/signal operations directly to kernel futex-like primitives.
4. **Hardware Display Tuning (KCAL DQE)**:
   - Integrated into Samsung's Display Quality Engine in `drivers/gpu/drm/samsung/dpu/exynos_drm_dqe.c`.
   - Evaluates user parameters (`kcal_enable`, `kcal_hue`, `kcal_sat`, `kcal_val`, `kcal_cont`) through an S8.14 fixed-point transformation matrix (`dqe_kcal_apply_matrix`), multiplying color gains directly into hardware gamma tables before screen refresh.
5. **Baseband Guard (BBG)**:
   - Dedicated Linux Security Module (LSM) in `security/bbg/`.
   - Intercepts block device writes and filesystem operations targeting `/efs`, modem, and radio nvram partitions, protecting device IMEI and calibration data from corruption.
6. **Storage & Memory Pipeline**:
   - MMC software CRC is disabled (`use_spi_crc = 0` in `drivers/mmc/core/core.c`), cutting CPU overhead.
   - `fs/dcache.c` tunes `sysctl_vfs_cache_pressure = 60` to retain directory inodes under memory strain.
   - Multi-Gen LRU (`CONFIG_LRU_GEN=y`) prioritizes hot cache pages; default ZRAM uses LZ4 (~4 GB/s decompression) to minimize memory PSI stalls.

---

## Key Directories

| Directory | Purpose |
| :--- | :--- |
| `tree/` | Complete Linux 5.15 LTS kernel source tree with Samsung Exynos 1330 drivers and NightKernel patches. |
| `tree/drivers/misc/` | NTSync driver implementation (`ntsync.c`). |
| `tree/drivers/samsung/` | Samsung SoC platform drivers, PMU reboot logic (`sec_reboot.c`), and debug modules. |
| `tree/drivers/gpu/drm/samsung/dpu/` | Exynos Display Processing Unit and DQE driver with embedded KCAL color calibration. |
| `tree/drivers/input/input_boost/` | Samsung Input Booster with de-spammed touch latency logging (`pr_debug`). |
| `tree/kernel/supercall/` | ReSukiSU supercall router and SuSFS command dispatch (`dispatch.c`). |
| `tree/security/bbg/` | Baseband Guard LSM protecting radio, modem, and `/efs` partitions. |
| `tree-recovery/` | TWRP recovery device tree for Galaxy A14 5G (`twrp_a14x.mk`). |
| `configs/` | Production kernel defconfigs (`nightkernel_v1.2.4_clang22_defconfig`, `nightkernel-v1.2.3-clang22.config`). |
| `patches/` | Modular individual patch files for cherry-picking specific subsystems. |
| `scripts/` | GCP Spot VM build launchers, ephemeral startup scripts, AnyKernel packaging, and benchmark suites. |

---

## Development Commands

### 1. Local Environment Setup & Compilation
```bash
# Export target architecture and toolchain
export ARCH=arm64
export SUBARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
export CLANG_TRIPLE=aarch64-linux-gnu-
export PATH=/usr/local/clang22/bin:$PATH

# Move into source tree
cd tree

# Load production defconfig
make CC=clang LLVM=1 LLVM_IAS=1 nightkernel_v1.2.4_clang22_defconfig

# Compile kernel Image and in-tree modules
make -j$(nproc) CC=clang LLVM=1 LLVM_IAS=1 KCFLAGS="-Wno-error" Image modules
```

### 2. Ephemeral Cloud Build (Google Cloud Platform)
Compiles on ephemeral GCP Spot VMs with a 24GB `tmpfs` RAM disk and persistent SSD ccache:
```bash
# Launch Cloud Build instance (v3.0.0 / Clang 22)
./scripts/launch_v300_clang22_gcp.sh

# Monitor live VM build log
gcloud compute instances tail-serial-port-output nightkernel-v300-<TIMESTAMP> \
    --zone=us-central1-a --project=stt-465818
```

### 3. Packaging Artifacts (TWRP Zip & Odin AP Tar)
```bash
# Generate AnyKernel3 zip for TWRP flashing
./scripts/package_anykernel.sh

# Generate Header Version 4 boot.img and Odin .tar
python3 scripts/mkbootimg.py \
    --kernel tree/arch/arm64/boot/Image \
    --header_version 4 \
    --os_version 15.0.0 \
    --os_patch_level 2026-09 \
    --output boot.img

tar -cvf boot-NightKernel-v3.0.0-a146m.tar boot.img
```

### 4. Device Benchmarking & Telemetry
```bash
# Run full benchmark harness on target device (via root shell)
su -c "/data/local/tmp/nightbench.sh all"

# Run targeted benchmark suites: sched | rt | io | mem | sleep | trace
su -c "/data/local/tmp/nightbench.sh sched"
su -c "/data/local/tmp/nightbench.sh io"

# Manage background telemetry tracer (LMK-immune logger)
su -c "/data/local/tmp/trace_control.sh start"
su -c "/data/local/tmp/trace_control.sh status"
su -c "/data/local/tmp/trace_control.sh stop"

# Generate telemetry summary report
python3 scripts/analyze_trace.py /sdcard/Download/nightkernel_trace.csv
```

---

## Code Conventions & Common Patterns

### C Coding Standards & Style
- **Linux Kernel Standard**: Adhere to GNU C11/C17 kernel conventions, 8-space tabs, `snake_case` functions and identifiers. Run `tree/scripts/checkpatch.pl --no-tree` on modifications.
- **Error Handling**: Functions returning pointers MUST use `ERR_PTR(-E*)`, `IS_ERR()`, and `PTR_ERR()`. Integer return functions MUST return `0` on success and negative error codes (`-EINVAL`, `-ENOMEM`, `-EFAULT`) on failure. Always use `goto err_cleanup` ladders to unwind resource allocation in reverse order.
- **Locking & Concurrency**:
  - Sleepable contexts: `mutex_lock(&lock)` / `mutex_unlock(&lock)`.
  - Atomic or IRQ contexts: `spin_lock_irqsave(&lock, flags)` / `spin_unlock_irqrestore(&lock, flags)`.
  - Read-heavy data paths: `rcu_read_lock()` / `rcu_read_unlock()` with `synchronize_rcu()`.
- **Samsung KABI Preservation**:
  - Never alter existing struct layouts or member offsets exposed to OEM proprietary vendor modules.
  - Exploit Android KABI reserved fields (`ANDROID_KABI_USE(...)`) when enabling new core features (such as `CONFIG_SYSVIPC=y`).
- **Hot-Path Logging**:
  - Strict prohibition against using `pr_info` or `pr_err` in high-frequency hot paths (touch handlers, frame compositing, IRQ handlers).
  - Use `pr_debug` or ftrace tracepoints (`trace_printk`) to avoid serial lock stalls.
- **Conditional Compilation**:
  - Explicitly wrap modular features in Kconfig checks (e.g. `#if defined(CONFIG_KSU_SUSFS)`).

---

## Important Files

| File Path | Description |
| :--- | :--- |
| `tree/Makefile` | Kernel root Makefile configuring ThinLTO, toolchain flags, and compiler warnings. |
| `configs/nightkernel_v1.2.4_clang22_defconfig` | Primary defconfig for Clang 22 LLVM builds with ThinLTO, BTF, and Teo governor. |
| `tree/kernel/supercall/dispatch.c` | ReSukiSU root supercall router with SuSFS integration. |
| `tree/drivers/samsung/sec_reboot.c` | Panic handler overriding `panic_str = "recovery"` to write PMU recovery flags. |
| `tree/kernel/reboot.c` | `/proc/nightkernel_reboot` interface for programmatic recovery reboots. |
| `tree/drivers/misc/ntsync.c` | In-kernel Windows NT synchronization primitive driver (`/dev/ntsync`). |
| `tree/drivers/gpu/drm/samsung/dpu/exynos_drm_dqe.c` | KCAL S8.14 matrix transformation integration in Samsung DQE. |
| `tree/security/bbg/` | Baseband Guard LSM source protecting `/efs` partitions. |
| `tree/drivers/mmc/core/core.c` | MMC software CRC check bypass (`use_spi_crc = 0`). |
| `tree/kernel/module.c` | Vermagic module version check bypass. |
| `tree/fs/sync.c` | Dynamic Fsync engine with `/sys/kernel/dyn_fsync/Dyn_fsync_active` sysfs toggle. |
| `scripts/00-nightkernel-optimizer.sh` | Post-boot debloater service disabling 26 Samsung/Meta daemons and keeping SSHD alive. |
| `scripts/package_anykernel.sh` | AnyKernel3 installer zip packaging script. |
| `scripts/nightbench.sh` | On-device validation suite (`hackbench`, `schbench`, `cyclictest`, `fio`). |
| `scripts/nightkernel_tracer.sh` | Daemon logging thermal, frequency, PSI stalls, and dmesg anomalies. |
| `scripts/analyze_trace.py` | Telemetry parser computing thermal throttling and memory pressure reports. |
| `INIT.md` | Master project directive and operational source of truth. |

---

## Runtime & Tooling Preferences

- **Build Environments**:
  - **Cloud Build**: GCP Spot VM `n2-standard-8` (8 vCPUs, 32 GB RAM) or `n2-custom-10-40960` running Ubuntu 24.04 LTS.
  - **RAM Disk Compilation**: Mandatory 24GB `tmpfs` at `/build` (`mount -t tmpfs -o size=24G tmpfs /build`). Avoid building directly on local flash storage to prevent I/O bottlenecks and drive wear.
  - **Local Host**: Android Termux (used exclusively for orchestration, launcher dispatch, analysis scripts, and git operations).
- **Compilers & Toolchains**:
  - **Clang 22 LLVM**: `clang-22`, `lld-22`, `llvm-22` with integrated assembler (`LLVM=1 LLVM_IAS=1`).
  - **AOSP Clang**: `clang-r450784d` (Clang 14.0.6) for stock baseline reproduction.
  - **Frame Warn Limit**: `CONFIG_FRAME_WARN=3072` required when compiling with modern Clang to accommodate inlined stack frames.
- **Cache Infrastructure**:
  - Dedicated GCP persistent SSD disk `a14x-ccache` mounted at `/mnt/ccache` with `CCACHE_COMPRESS=1` and `CCACHE_NOHASHDIR=1`.
- **BTF & Debugging Utilities**:
  - `pahole` (v1.24+) and `dwarves` required for BPF Type Format generation (`CONFIG_DEBUG_INFO_BTF=y`).
  - Python 3 with `argparse`, `csv`, and `math` for `mkbootimg.py` and `analyze_trace.py`.

---

## Testing & QA

### Validation Suites & Commands
1. **Scheduler Latency & IPC**:
   - `hackbench -l 500 -g 2`: Tests process scheduling and IPC contention.
   - `schbench -m 2 -t 4 -r 5`: Evaluates scheduler wakeup latency percentiles.
2. **Real-Time Jitter**:
   - `cyclictest -l 5000 -p 99 -i 1000 -m -q`: Measures timer jitter and latency under thread priority 99.
3. **UFS 2.2 Storage Throughput**:
   - `fio --rw=read --bs=1m --iodepth=4 --direct=1`: Validates sequential read speed.
   - `fio --rw=randwrite --bs=4k --iodepth=4 --direct=0`: Validates dirty page flushing.
4. **Dynamic Fsync & I/O Latency Trade-Off**:
   - Active by default (`1`) yielding ~100k IOPS on 4KB SQLite writes.
   - Toggle off (`echo 0 > /sys/kernel/dyn_fsync/Dyn_fsync_active`) for professional low-latency audio where p99.9 jitter (<300µs) takes precedence over I/O throughput.
5. **Thermal & PSI Telemetry Rules**:
   - **Throttling Warning**: Big core frequency dropping below 1800 MHz while temperature is $\ge 75^\circ\text{C}$ indicates thermal throttling.
   - **Memory Stall Warning**: Memory Pressure Stall Information (`avg10`) exceeding 15.0% indicates excessive ZRAM thrashing or memory pressure.
   - **Kernel Integrity**: Any `dmesg` matches for `panic`, `oops`, `bug`, `call trace`, or `oom-killer` flagged as release blockers.
5. **Pre-Release Headless Sanity Check**:
   - Build scripts execute a QEMU headless boot test (`qemu-system-aarch64 -nographic -no-reboot`) to verify kernel decompression and banner output (`"Linux version"`) before packaging artifacts.
