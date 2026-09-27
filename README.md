# NightKernel for Samsung Galaxy A14 5G

[English](README.md) | [Português](README_PT.md)

<p align="center">
  <img src="assets/banner.jpg" alt="NightKernel Banner" width="100%">
</p>

Custom Linux kernel for the **Samsung Galaxy A14 5G** (`SM-A146M` / `SM-A146B`, codename `a14x` / `s5e8535`), running **Android 15 (Samsung One UI 7 - PDA `A146MUBSDDZE1`, Binary D)**. Built from the proven `physwizz/a146b-a146m` (`V-sd-perm`) baseline with upstream **Linux 5.15.180**.

> [!WARNING]
> **Compatibility:** Supported on `SM-A146M` and `SM-A146B` (Samsung Exynos 1330).  
> **DO NOT FLASH on US variants (`SM-A146U`, `SM-A146U1`, `SM-S146VL`)** — those models use a MediaTek Dimensity 700 SoC and will brick.

> [!CAUTION]
> ```text
> * Your warranty is now void.
> * I am not responsible for bricked devices, dead SD cards, thermonuclear war,
> * or you getting fired because the alarm app failed. Please do some research
> * before flashing. You choose to make these modifications, and you proceed
> * at your own risk.
> ```

---

## Features

### Autonomous Recovery (`/proc/nightkernel_reboot`)
Samsung's stock bootloader (`sboot`) on Exynos 1330 enforces a restriction requiring an active USB cable connected to a PC or charger before accepting hardware keys (`Power + Vol Up`) for recovery. Without a USB connection, cold reboots jump straight into Android.
- **Kernel-level fix:** In `drivers/samsung/sec_reboot.c`, issuing `recovery` writes the hardware magic code `SEC_RESET_REASON_RECOVERY` directly into the Samsung PMU retention registers (`panic_inform` / `regmap_write`).
- **Procfs node:** World-writable (`0666`) interface at `/proc/nightkernel_reboot`. Run:
  ```bash
  echo 1 > /proc/nightkernel_reboot
  ```
  to reboot immediately into TWRP without needing a computer or cable.
- **Hardware key shortcut:** Holding `Power + Vol Up` while rebooting the system also routes directly to recovery.
- **Panic-to-Recovery:** Kernel panic handler defaults to `"recovery"` instead of `"panic"`, safely booting into TWRP rather than freezing in upload mode or bootlooping.

### Root & Integrity Bypass (ReSukiSU 3.0.0 + SuSFS 2.1.0)
- **ReSukiSU 3.0.0:** Integrated directly into kernel source with supercall protection patches in `dispatch.c`.
- **SuSFS 2.1.0:** Kernel-level VFS isolation hiding root mounts (`sus_mount`), memory maps (`sus_map`), and inode attributes (`sus_kstat_redirect`). Passes Google Play Integrity (`MEETS_DEVICE_INTEGRITY`) and banking app security checks.
- **Uname spoofing:** Configurable kernel release string at runtime (`sus_set_uname`).

### Windows NT Synchronization (NTSync)
- **Driver `/dev/ntsync`:** Implements Windows NT synchronization primitives (mutexes, semaphores, events) directly inside the Linux kernel (`drivers/misc/ntsync.c`).
- **Performance:** Bypasses `wineserver` user-space IPC overhead in Windows compatibility layers (**Winlator**, **Mobox**, **Termux-Box**, **Wine-GE**), reducing thread synchronization latency in multithreaded DirectX 9/11/12 and Vulkan workloads.
- **Compatibility:** Includes 32-bit compat ioctl handlers (`CONFIG_NTSYNC_COMPAT=y`) and `0666` permissions for unprivileged access.

### Display Tuning (KCAL Color Control)
- Custom KCAL driver integrated into Samsung's DQE display pipeline (`drivers/gpu/drm/samsung/dqe/`).
- Allows adjusting RGB color balance, contrast, saturation, and hue via standard KCAL apps.

### Storage & I/O
- Software CRC checks disabled on MMC/SD (`use_spi_crc = 0` in `drivers/mmc/core/core.c`), cutting CPU overhead and boosting storage/microSD read and write throughput.
- Kernel module version checking bypass in `kernel/module.c` for loading out-of-tree modules without vermagic mismatch errors.

### Containers & Linux Virtualization
- `CONFIG_SYSVIPC=y` enabled through Android KABI padding without breaking OEM kernel ABI.
- DroidSpaces support (`binfmt_misc`, `OverlayFS`, `FUSE`, `Btrfs`) for running chroots, LXC, and Docker in Termux.

### Hardware Defense (Baseband Guard)
- Baseband Guard (BBG) LSM module integrated in `security/bbg/`.
- Blocks unauthorized writes, formatting, or tampering with `/efs` and radio partitions to safeguard IMEI and RF calibration data.

### System & Memory
- **MGLRU (Multi-Gen LRU):** Enabled by default (`CONFIG_LRU_GEN=y`, `0x0003`) for efficient page reclamation.
- **TCP BBR v1 + FQ:** Congestion control set to BBR with Fair Queuing qdisc to minimize network latency and bufferbloat.
- **Realtek RT5691 Audio:** Built with the correct hardware audio codec driver (`CONFIG_SND_SOC_RT5691=m`).
- **Samsung restrictions removed:** KNOX, DEFEX, RKP, KDP, PROCA, FIVE, and UH neutralized.
- **BTF debug info:** Built with `CONFIG_DEBUG_INFO_BTF=y` and `pahole 1.24` for eBPF tool compatibility.

---

## Installation

### 1. TWRP Recovery (Recommended)
1. Download `NightKernel-v1.2.0-a14x.zip` from [Releases](https://github.com/multi-forge/NightKernel-a14x/releases/tag/v1.2.0).
2. Boot into TWRP.
3. *Note:* Because Android 15 `/data` is encrypted with FBE, place the zip on a **MicroSD card**, **USB OTG drive**, or in `/cache/` (unencrypted ext4 partition).
4. Flash the zip and reboot system.

### 2. Odin / Download Mode
1. Download `boot-NightKernel-v1.2.0.tar` from [Releases](https://github.com/multi-forge/NightKernel-a14x/releases/tag/v1.2.0).
2. Boot into Download Mode (`Vol+ + Vol-` with USB cable connected to PC).
3. Place `boot-NightKernel-v1.2.0.tar` in the **AP** slot in Odin.
4. Flash and reboot.

### 3. Root Terminal
```bash
dd if=boot.img of=/dev/block/by-name/boot bs=4096 && sync && reboot
```

---

## Building from Source

### Prerequisites
- Linux build environment (Ubuntu 22.04 or 24.04 LTS recommended)
- AOSP Clang 18 (r522817) or newer
- AArch64 GCC / LLVM binutils

### Build Commands
```bash
# Set toolchain paths
export ARCH=arm64
export SUBARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
export CLANG_TRIPLE=aarch64-linux-gnu-
export PATH=/path/to/clang-r522817/bin:$PATH

# Load defconfig
make CC=clang LLVM=1 nightkernel_v1.2_defconfig

# Compile kernel Image
make -j$(nproc) CC=clang LLVM=1 Image
```
Output binary will be located at `arch/arm64/boot/Image`.

---

## Source Tree Structure
- [`tree/`](tree/): Full kernel source tree with all patches applied.
- [`tree-recovery/`](tree-recovery/): TWRP device tree for Galaxy A14 5G.
- [`configs/`](configs/): Production kernel defconfig (`nightkernel_v1.2_defconfig`).
- [`patches/`](patches/): Modular patch files for each individual feature.

## Related Links
- **Releases:** [NightKernel Releases](https://github.com/multi-forge/NightKernel-a14x/releases)
- **TWRP Recovery:** [android_device_samsung_a14x](https://github.com/multi-forge/android_device_samsung_a14x)
- **Base Tree:** [physwizz/a146b-a146m](https://github.com/physwizz/a146b-a146m) (`V-sd-perm`)
