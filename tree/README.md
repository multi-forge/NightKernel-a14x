# Samsung Galaxy A14 5G (`a14x` / `s5e8535`) Kernel Source Tree

<p align="center">
  <img src="https://raw.githubusercontent.com/multi-forge/NightKernel-a14x/main/assets/banner.jpg" alt="NightKernel Banner" width="100%">
</p>

> [!WARNING]
> ```text
> * Your warranty is now void.
> * I am not responsible for bricked devices, dead SD cards, thermonuclear war,
> * or you getting fired because the alarm app failed. Please do some research
> * before flashing. You choose to make these modifications, and you proceed
> * at your own risk.
> ```

---

## Overview

Complete production-booted kernel source tree for the **Samsung Galaxy A14 5G** (`SM-A146M` and `SM-A146B`), based on the `physwizz/a146b-a146m` (`V-sd-perm`) source tree for **Android 15 / One UI 7 (PDA: `A146MUBSDDZE1`, Binary D)**.

### Merged Patches & Features
1. **Autonomous Recovery:** Kernel-level `/proc/nightkernel_reboot` interface and hardware key handler bypassing Samsung's PC USB cable handshake requirement.
2. **SuSFS v2.1.0:** Kernel VFS-level isolation for KernelSU (`sus_mount`, `sus_map`, `sus_kstat_redirect`).
3. **ReSukiSU v3.0.0:** Modern KernelSU implementation with supercall protection.
4. **NTSync:** Native driver (`/dev/ntsync`) with 32-bit compat support for fast Windows NT synchronization in Winlator / Mobox.
5. **DroidSpaces:** Container namespace support and `CONFIG_SYSVIPC=y` for LXC and Docker in Termux.
6. **Baseband Guard (BBG):** Security LSM blocking unauthorized writes to `/efs` and radio partitions.
7. **KCAL DQE Driver:** Hardware RGB color calibration, contrast, and saturation control.
8. **MMC CRC Bypass:** Software CRC checks disabled on MMC/SD for faster I/O.

---

## Compilation

### Requirements
- Host OS: Linux (Ubuntu 22.04 or 24.04 recommended)
- Toolchain: Android AOSP Clang 18 (r522817) or newer
- Cross-Compiler: AArch64 GCC / LLVM binutils

### Build Commands
```bash
export ARCH=arm64
export SUBARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
export CLANG_TRIPLE=aarch64-linux-gnu-
export PATH=/path/to/clang-r522817/bin:$PATH

make CC=clang LLVM=1 nightkernel_v1.2_defconfig
make -j$(nproc) CC=clang LLVM=1 Image
```

Output kernel binary: `arch/arm64/boot/Image`.

---

## Resources
- **Releases:** [NightKernel Releases](https://github.com/multi-forge/NightKernel-a14x/releases)
- **TWRP Device Tree:** [tree-recovery/](https://github.com/multi-forge/NightKernel-a14x/tree/main/tree-recovery)
- **Recovery Repo:** [android_device_samsung_a14x](https://github.com/multi-forge/android_device_samsung_a14x)
- **Upstream Source:** [physwizz/a146b-a146m](https://github.com/physwizz/a146b-a146m) (`V-sd-perm`)
