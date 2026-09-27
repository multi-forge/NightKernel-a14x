# Samsung Galaxy A14 5G (`a14x` / `s5e8535`) Kernel Source Tree

<p align="center">
  <img src="https://img.shields.io/badge/Base-physwizz%20V--sd--perm-blueviolet?style=for-the-badge&logo=linux" alt="Base">
  <img src="https://img.shields.io/badge/Target-SM--A146M%20%7C%20SM--A146B-blue?style=for-the-badge&logo=samsung" alt="Device">
  <img src="https://img.shields.io/badge/SoC-Exynos%201330%20(s5e8535)-orange?style=for-the-badge" alt="SoC">
  <img src="https://img.shields.io/badge/Android-15%20(One%20UI%207)-green?style=for-the-badge&logo=android" alt="Android">
  <img src="https://img.shields.io/badge/Status-Production%20Booted%20🟢-brightgreen?style=for-the-badge" alt="Status">
</p>

---

### ⚠️ DISCLAIMER / LIABILITY NOTICE

> [!WARNING]
> ```text
> * Your warranty is now void.
> *
> * I am not responsible for bricked devices, dead SD cards, thermonuclear war,
> * or you getting fired because the alarm app failed. Please do some research
> * if you have any concerns about features included in this kernel before flashing it!
> *
> * YOU are choosing to make these modifications, and if you point the finger at me
> * for messing up your device, I will laugh at you.
> *
> * Flashing custom kernels, rooting, and bypassing security mechanisms involves
> * inherent risks. You proceed entirely at your own risk.
> ```

---

## 📌 Kernel Source Overview

This directory (`tree/`) contains the complete, verified, and production-booted kernel source code for the **Samsung Galaxy A14 5G** (`SM-A146M` and `SM-A146B`), based on the proven **physwizz** source tree (`V-sd-perm`) for **Android 15 / One UI 7 (PDA: `A146MUBSDDZE1`, Binary D)**.

All production patches are already merged and active in this source tree:
1. **Autonomous Recovery Subsystem:** Kernel-level `/proc/nightkernel_reboot` interface and hardware key handler that bypasses Samsung's requirement for a connected USB cable.
2. **SuSFS v2.1.0:** Kernel-level virtual file system isolation for KernelSU, hiding root from detection mechanisms (Play Integrity Strong, banking apps).
3. **ReSukiSU v3.0.0:** Modern KernelSU implementation with security safeguards.
4. **NTSync (Windows NT Synchronization):** Native driver (`/dev/ntsync`) accelerating multi-threaded Windows emulation (Mobox, Winlator, Termux-Box).
5. **DroidSpaces:** Enhanced Linux container namespace support (LXC, Docker in Termux).
6. **Baseband Guard (BBG):** Security LSM preventing unauthorized baseband access and malicious modem commands.
7. **KCAL DQE Driver:** Custom hardware/software RGB color calibration, saturation, and contrast control.
8. **MMC Software CRC Bypass:** Optimized microSD and eMMC I/O throughput (up to 30% speedup).

---

## 🛠️ Compilation Guide

### Requirements
- **Host OS:** Linux (Ubuntu 22.04 / 24.04 recommended)
- **Toolchain:** Android AOSP Clang 18 (r522817) or newer
- **Cross-Compiler:** AArch64 GCC 12+ / LLVM binutils

### Build Commands
```bash
# 1. Set environment variables
export ARCH=arm64
export SUBARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
export CLANG_TRIPLE=aarch64-linux-gnu-
export PATH=/path/to/clang-r522817/bin:$PATH

# 2. Load NightKernel production defconfig
make CC=clang LLVM=1 nightkernel_v1.2_defconfig

# 3. Compile kernel image
make -j$(nproc) CC=clang LLVM=1 Image
```

The output kernel image will be generated at `arch/arm64/boot/Image`.

---

## 🔗 Related Resources
- **NightKernel Releases:** [multi-forge/NightKernel-a14x/releases](https://github.com/multi-forge/NightKernel-a14x/releases)
- **TWRP Device Tree:** [tree-recovery/](https://github.com/multi-forge/NightKernel-a14x/tree/main/tree-recovery)
- **Official Recovery Repo:** [multi-forge/android_device_samsung_a14x](https://github.com/multi-forge/android_device_samsung_a14x)
- **Upstream Baseline:** [physwizz/a146b-a146m](https://github.com/physwizz/a146b-a146m) (branch `V-sd-perm`)
