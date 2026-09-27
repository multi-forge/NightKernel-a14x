# 🌌  NightKernel for Samsung Galaxy A14 5G

<div align="center">
  <a href="README.md"><img src="https://img.shields.io/badge/Language-English-blue?style=for-the-badge" alt="English"></a>
  <a href="README_PT.md"><img src="https://img.shields.io/badge/Idioma-Portugu%C3%AAs-gray?style=for-the-badge" alt="Português"></a>
</div>

<br>

<p align="center">
  <img src="https://img.shields.io/badge/Kernel-Linux%205.15.180-blue?style=for-the-badge&logo=linux" alt="Kernel Version">
  <img src="https://img.shields.io/badge/Android-15%20(One%20UI%207)-green?style=for-the-badge&logo=android" alt="Android Version">
  <img src="https://img.shields.io/badge/SoC-Exynos%201330%20(s5e8535)-orange?style=for-the-badge" alt="SoC">
  <img src="https://img.shields.io/badge/Root-ReSukiSU%20%2B%20SuSFS%202.1.0-brightgreen?style=for-the-badge" alt="SuSFS">
  <img src="https://img.shields.io/badge/Recovery-Autonomous%20PMU%20(No%20Cable)-red?style=for-the-badge" alt="Autonomous Recovery">
</p>

<p align="center">
  <a href="https://github.com/multi-forge/android_device_samsung_a14x/releases/tag/unbrick-dze1"><img src="https://img.shields.io/badge/TWRP%20Recovery-Download%20Tar%20(DZE1)-orange?style=for-the-badge&logo=twrp" alt="TWRP Recovery"></a>
  <a href="https://github.com/multi-forge/android_device_samsung_a14x"><img src="https://img.shields.io/badge/Device%20Tree-multi--forge%2Fandroid__device__samsung__a14x-blueviolet?style=for-the-badge&logo=github" alt="Device Tree"></a>
</p>

---

## 📖 Overview

**NightKernel** is an advanced, production-grade custom kernel custom-tailored for the **Samsung Galaxy A14 5G** family (`SM-A146M`, `SM-A146M/DS`, and `SM-A146B`) running **Android 15 (Samsung One UI 7 - firmware A146MUBSDDZE1, Binary D)** based on upstream **Linux 5.15.180**.

Built from a clean, field-tested 1:1 hardware baseline, NightKernel combines deep gaming and emulation enhancements (native NTSync driver and System V IPC), kernel-level root hiding (SuSFS 2.1.0 and ReSukiSU 3.0.0), active hardware defense (Baseband Guard LSM), advanced display calibration (KCAL Color Control), and an **Autonomous Recovery** engine that eliminates Samsung's requirement of a connected USB cable or PC to access TWRP.

---

## ⚡ Quick Feature Matrix

| Feature | Module / Driver | Status | Technical Description |
|---|---|:---:|---|
| **Autonomous Recovery** | `drivers/samsung/sec_reboot.c` & `/proc/nightkernel_reboot` | 🟢 Active | Direct TWRP boot via PMU retention register; no USB cable needed; Panic-to-Recovery |
| **NTSync** | `drivers/misc/ntsync.c` (`/dev/ntsync`) | 🟢 Active | Windows NT synchronization primitives in kernel; 32/64-bit compat; `0666` universal access |
| **Root Evasion** | SuSFS 2.1.0 (`fs/susfs.c`) | 🟢 Active | Stealth mounts, memory maps, kstat redirects, uname spoofing, and proactive fsnotify |
| **Superuser** | ReSukiSU 3.0.0 / KernelSU | 🟢 Active | Kernel-level superuser with supercall safety patches and multi-manager support |
| **Baseband Guard (BBG)** | LSM (`security/bbg/`) | 🟢 Active | Linux Security Module blocking unauthorized writes or formatting to `/efs` and modem |
| **System V IPC** | `CONFIG_SYSVIPC=y` via Android KABI Padding | 🟢 Active | Support for DroidSpaces, Proot, Chroot, and full Linux distros without breaking ABI |
| **KCAL Color Control** | `drivers/gpu/drm/samsung/dqe/` | 🟢 Active | Fine-grained RGB, hue, contrast, and saturation tuning on Samsung DQE display hardware |
| **MMC/SD Storage I/O** | `drivers/mmc/core/core.c` | 🟢 Active | Software CRC check disabled (`use_spi_crc = 0`); accelerates storage I/O by up to 30% |
| **Module Version Bypass** | `kernel/module.c` | 🟢 Active | Allows loading out-of-tree LKM kernel modules without strict symbol vermagic/CRC errors |
| **RAM Management (MGLRU)** | `CONFIG_LRU_GEN=y` | 🟢 Active | Multi-Gen LRU enabled by default (`0x0003`); fluid multitasking without memory thrashing |
| **Low-Latency Network** | `CONFIG_TCP_CONG_BBR=y` | 🟢 Active | TCP BBR v1 + Fair Queuing (FQ) scheduler as default; reduces bufferbloat and ping |
| **Containers & Emulation** | `binfmt_misc`, `OverlayFS`, `FUSE`, `Btrfs` | 🟢 Active | Transparent execution of x86/x64 binaries via Box64; modern container filesystems |
| **Real A14 5G Audio Fix** | Realtek `RT5691` (`CONFIG_SND_SOC_RT5691=m`) | 🟢 Active | Hardware-accurate audio driver enabled; non-existent `SMA1305` driver removed |
| **Samsung Restrictions** | KNOX, DEFEX, RKP, KDP, PROCA, FIVE, UH | 🟢 Neutralized | Removed restrictive OEM memory locks, write protections, and telemetry verifiers |
| **BTF Debug Symbols** | `CONFIG_DEBUG_INFO_BTF=y` | 🟢 Active | Full BPF Type Format info preserved with `pahole 1.24` for eBPF and tracing tools |

---

## 🛠️ Detailed Architecture & Kernel Subsystems

### 🔁 1. Autonomous Recovery & Failsafe (No USB Cable Needed)
* **The Samsung Bootloader Limitation:** On modern Samsung devices (especially Exynos platforms), the primary bootloader (`sboot`) enforces a restriction requiring an active USB cable connected to a PC before accepting the physical recovery key combination (`Vol+` + `Power`) during cold boot. Without a connected PC, the bootloader ignores the keys and boots into the Android OS.
* **The NightKernel Solution:**
  1. **Interface `/proc/nightkernel_reboot` (0666):** A dedicated procfs node was implemented in `kernel/reboot.c`. It permits world read/write permissions (`0666`). When written `1` or `recovery`, the kernel immediately invokes `kernel_restart("recovery")`.
  2. **Direct Samsung PMU Retention Writing:** In `drivers/samsung/sec_reboot.c`, when the reboot command string `"recovery"` is received, the kernel directly writes the hardware magic code `SEC_RESET_REASON_RECOVERY` into the Samsung PMU panic retention registers (`panic_inform` / `regmap_write`). Upon rebooting, the Samsung bootloader reads this register and jumps **directly into TWRP Recovery**, completely skipping the USB handshake check!
  3. **Panic-to-Recovery:** The kernel's default panic string was redirected from `"panic"` to `"recovery"`. If an unexpected driver crash, kernel panic, or critical failure occurs, the device automatically sets the PMU flag and reboots into TWRP instead of entering a black screen or upload mode, eliminating unrecoverable bootloops.
* **How to Trigger from Android:**
  ```bash
  # Instantly reboot into TWRP without needing a PC or USB cable:
  echo 1 > /proc/nightkernel_reboot
  ```

---

### 🎮 2. Gaming, Emulation & Synchronization (NTSync)
* **Native NTSync Driver (`/dev/ntsync`):** Built into the kernel tree (`drivers/misc/ntsync.c`), NTSync implements Windows NT synchronization primitives directly within Linux:
  - Mutexes (`NTSYNC_IOC_CREATE_MUTEX`)
  - Semaphores (`NTSYNC_IOC_CREATE_SEM`)
  - Signaling Events (`NTSYNC_IOC_CREATE_EVENT`)
* **Real-World Impact on Emulators:** Windows compatibility layers on Android (**Winlator**, **Mobox**, **Box64**, **Wine-GE**, **Proot**) traditionally rely on user-space IPC or `wineserver` (esync/fsync) to synchronize multithreaded DirectX 9/11/12 and Vulkan game loops, causing high latency, CPU overhead, and micro-stutters. With NTSync, thread synchronization happens directly within kernel space at near-zero context-switching cost.
* **32/64-bit Compatibility & Universal Access:** The driver includes 32-bit compat ioctl handlers (`CONFIG_NTSYNC_COMPAT=y`) and automatically initializes `/dev/ntsync` with `0666` permissions, allowing unprivileged emulator processes to use full hardware acceleration without root.

---

### 🛡️ 3. Kernel-Level Root Evasion (SuSFS 2.1.0 & ReSukiSU 3.0.0)
* **ReSukiSU 3.0.0 Superuser:** Integrated directly into kernel source with supercall protection patches (`dispatch.c`), providing multi-manager support, strict privilege isolation, and protection against unauthorized userspace tampering.
* **SuSFS 2.1.0 (Super SuFS):**
  - **`sus_mount`:** Dynamically hides overlay mount points, loop devices, and root module directories from `/proc/mounts`, `/proc/self/mountinfo`, and `/proc/self/mountstats`.
  - **`sus_map`:** Masks injected memory regions, dynamic hooks, and process maps in `/proc/<pid>/maps`.
  - **`sus_kstat` & Redirection:** Camouflages modified file attributes (timestamps, inode numbers, link counts) and redirects integrity checks on modified libraries back to clean stock system files.
  - **Uname Spoofing (`sus_set_uname`):** Allows spoofing the reported public kernel version and release string at runtime.
  - **Proactive `fsnotify` Monitoring:** The kernel proactively monitors access to `/data/media/0/Android` using `fsnotify`, automatically triggering stealth evasion rules whenever banking, security, or integrity scanner applications begin scanning storage.
* **Play Integrity:** When paired with ReSukiSU and modern spoof modules, NightKernel achieves `MEETS_DEVICE_INTEGRITY` compliance and runs sensitive banking and financial apps (Nubank, Caixa, Itaú, BB, Santander, PicPay, etc.) without detection.

---

### 🔒 4. Baseband Guard (BBG) LSM Defense
* **Safeguarding Cellular & Hardware Identity:** On Samsung devices, accidental formatting or malicious root scripts executing `dd` or `format` commands on radio or `/efs` block devices can permanently erase cellular baseband parameters and IMEI calibration certificates.
* **LSM Active Hook:** NightKernel integrates Baseband Guard into the Linux Security Modules (LSM) framework. It monitors all `open`, `write`, and `ioctl` operations targeted at modem, baseband, and `/efs` block partitions. Any unauthorized attempt to overwrite or wipe these partitions is stopped immediately with `EACCES` / `EPERM`, preserving IMEI and RF antenna tuning permanently.

---

### 🐧 5. Containers & Native Linux Virtualization (DroidSpaces & System V IPC)
* **System V IPC via Android KABI Padding:** Stock Android kernels disable `CONFIG_SYSVIPC` to save memory and force apps to use Binder IPC. However, running full Linux distributions (Debian, Arch Linux, Ubuntu) via Proot/Chroot, DroidSpaces containers, and complex POSIX software requires System V semaphores and shared memory (`shm`).
* **Preserving Samsung ABI:** NightKernel enables `CONFIG_SYSVIPC=y` by leveraging the reserved KABI padding fields within `struct task_struct` (`ANDROID_KABI_USE(6, struct sysv_sem sysvsem)` and `_ANDROID_KABI_REPLACE(...)` in `include/linux/sched.h`). This delivers full SysV semaphore and shared memory support without breaking Samsung's proprietary binary drivers.
* **Native Emulation:** `binfmt_misc` is enabled to run x86 and x86_64 Linux executables directly through Box64 / Box86. Systems like `OverlayFS`, `FUSE`, and `Btrfs` are fully compiled and operational.

---

### 🎨 6. KCAL Color Control for Samsung DQE
* **Hardware Display Calibration:** NightKernel integrates a customized KCAL driver adapted specifically for Samsung's DQE (Display Quality Enhancement) hardware pipeline (`drivers/gpu/drm/samsung/`).
* **Supported Adjustments:**
  - Individual RGB channel control (Red, Green, Blue).
  - Screen saturation and color hue tuning.
  - Global contrast and black-point adjustment.
* **Ecosystem Compatibility:** Fully compatible with standard KCAL controller apps available on GitHub and the Play Store.

---

### 🚀 7. Storage I/O, Memory & Network Tuning
* **MMC/SD Software CRC Calculation Disabled:** The Linux MMC/SD subsystem performs redundant software CRC checks on data packets by default. In NightKernel, software CRC checking is turned off (`use_spi_crc = 0`), freeing CPU cycles and boosting real-world storage I/O performance by up to 30%.
* **Kernel Module Version Checking Bypass (`kernel/module.c`):** The module loader was updated to allow loading out-of-tree kernel modules (LKM) even with minor discrepancies in symbol CRC checksums (`bad_version: return 1`), facilitating custom driver development.
* **MGLRU (Multi-Gen LRU):** The predictive memory reclamation algorithm is active by default (`sys/kernel/mm/lru_gen/enabled = 0x0003`), replacing the legacy two-list scheme and preventing UI micro-stutters during heavy multitasking and gaming.
* **TCP BBR v1 + Fair Queuing (FQ):** Configured as the default network congestion control algorithm, minimizing bufferbloat and reducing ping latency on Wi-Fi and 5G/4G networks.
* **F2FS Compression:** Native support for inline compression (LZ4 / ZSTD) on `/data`, saving flash storage space and reducing write cycles.

---

### 🎵 8. Hardware-Accurate Audio (Realtek RT5691) & BTF
* **Correct Audio Hardware Driver:** Analysis of the physical Galaxy A14 5G (`SM-A146M`) board revealed that the device uses the Realtek `RT5691` audio codec (`CONFIG_SND_SOC_RT5691=m` - driver `exynos8535rt569`), and **not** the `SMA1305` chip. Retaining `SMA1305` caused compilation and linker failures due to missing thermal telemetry callbacks (`audio_register_curr_temperature_cb`). With `RT5691` active and `SMA1305` disabled, speaker, 3.5mm jack, microphone, in-call audio, and Bluetooth sound function with 100% fidelity.
* **BPF Type Format (`.BTF`):** Compiled with `CONFIG_DEBUG_INFO_BTF=y` using `pahole 1.24`, guaranteeing full compatibility with eBPF tools, modern system profilers, and Samsung proprietary vendor modules.

---

### 🔓 9. Neutralized Samsung OEM Restrictions
To ensure system freedom, eliminate kernel lockups, and prevent OEM telemetry overhead, the following Samsung subsystems were disabled:
- **KNOX & DEFEX:** Runtime integrity enforcement modules disabled.
- **RKP & KDP (Real-time Kernel Protection & Kernel Data Protection):** Disabled to allow KernelSU and kernel-level modifications to write page tables without kernel panics.
- **PROCA (Process Authenticator) & FIVE:** Neutralized, allowing execution of custom binaries without Samsung signature checks.
- **UH (Userland Hardening):** Disabled, removing restrictions on process memory access and debugging calls.

---

## 📱 Device Compatibility & Model Matrix

NightKernel is engineered strictly for the Samsung Exynos 1330 (`s5e8535` / `a14x`) platform. Review the compatibility matrix below before flashing:

| Model | Market / Region | Chipset / SoC | Compatibility Status | Notes |
|---|---|---|:---:|---|
| **SM-A146M / DS** | Latin America / Brazil | Samsung Exynos 1330 (`s5e8535`) | 🟢 **Supported** | 100% Field-tested and validated in production |
| **SM-A146B / DS** | Global / Europe / India / Asia | Samsung Exynos 1330 (`s5e8535`) | 🟢 **Supported** | Unified kernel codebase (`a146b-a146m`); 100% hardware match |
| **SM-A146U / U1** | United States (Carrier / Unlocked) | MediaTek Dimensity 700 (`MT6833`) | 🔴 **NOT SUPPORTED** | **DO NOT FLASH!** Incompatible MediaTek architecture |
| **SM-S146VL** | USA (TracFone / Straight Talk) | MediaTek Dimensity 700 (`MT6833`) | 🔴 **NOT SUPPORTED** | **DO NOT FLASH!** Incompatible MediaTek hardware |

### 🔍 Why SM-A146B is 100% Compatible:
1. **Unified Kernel Source Tree:** Samsung develops and releases the exact same unified kernel source tree for both models (`a146b-a146m`).
2. **Identical Hardware Architecture:** Both `SM-A146B` and `SM-A146M` share the exact same motherboard reference (`erd8535`), Exynos 1330 SoC, Mali-G68 GPU, Realtek RT5691 audio codec, DQE display pipeline, and MMC/UFS storage controllers. Region differences are limited to cellular RF band filters configured in the baseband firmware (`modem.bin` / `/efs`), which NightKernel protects and leaves untouched via Baseband Guard.
3. **Seamless AnyKernel3 Installation:** The AnyKernel3 installer script (`NightKernel-v1.2.0-a14x.zip`) includes both `SM-A146M` and `SM-A146B` in its device check (`device.name5=SM-A146B`). When installed via TWRP, AnyKernel3 extracts the device's native boot image header and dynamically injects the NightKernel `Image`, ensuring complete retention of device-specific flags and signatures.

> [!WARNING]
> **US Model Incompatibility Warning:** Galaxy A14 5G models sold in the United States (`SM-A146U`, `SM-A146U1`, `SM-S146VL`) are equipped with a **MediaTek Dimensity 700** chipset, NOT an Exynos SoC. Flashing NightKernel on these US models will hard-brick the device!

> [!IMPORTANT]
> **Android 15 Requirement:** Your `SM-A146B` must be running **Android 15 (One UI 7)**. Flashing this kernel on Android 13 or 14 will result in boot failure due to kernel ABI mismatches with older `vendor_boot` proprietary modules.

---

## 📱 Build & Hardware Specifications

| Specification | Target Details |
|---|---|
| **Target Device** | Samsung Galaxy A14 5G (`SM-A146M`, `SM-A146M/DS`, `SM-A146B`, `SM-A146B/DS`) |
| **Board / Platform** | `a14x` / `s5e8535` |
| **SoC / Processor** | Samsung Exynos 1330 Octa-Core (2x Cortex-A78 @ 2.4 GHz + 6x Cortex-A55 @ 2.0 GHz) |
| **GPU** | ARM Mali-G68 MP2 |
| **Firmware Reference** | Android 15 (Samsung One UI 7) - PDA `A146MUBSDDZE1` (Binary D) |
| **Kernel Version** | Linux Upstream `5.15.180` |
| **Toolchain / Compiler** | Google Clang / LLVM 17 (`r522817`) + LLD Linker |
| **BTF Generator** | `pahole` v1.24 |
| **Kernel Signature** | `5.15.180-NightKernel-v1.2+` |

---

## 📥 Official Downloads

Production-ready packages are available on the [GitHub Releases Page](https://github.com/multi-forge/NightKernel-a14x/releases):

| File | Format | Recommended Use |
|---|---|---|
| **`NightKernel-v1.2.0-a14x.zip`** | AnyKernel3 ZIP | Standard flash via **TWRP Recovery** (preserves ramdisk, dtb, and configs) |
| **`boot-NightKernel-v1.2.0.tar`** | Odin TAR | Flashing to the **AP** slot via **Odin / Heimdall** in Download Mode |
| **`boot.img`** | Raw Partition Image | Direct partition flash via root terminal |
| **`twrp-12-vsd-dze1.tar`** | Odin TAR | Official **TWRP Recovery** for Galaxy A14 5G ➔ [Download](https://github.com/multi-forge/android_device_samsung_a14x/releases/tag/unbrick-dze1) |
| **`nightkernel_v1.2_defconfig`** | Text Config | Verified `.config` file used for the production build |

---

## 🚀 Installation Guide

> [!IMPORTANT]
> - Your bootloader must be **unlocked**.
> - Always maintain a backup of your stock `boot` partition before making any modifications.

### Method 1: Flashing via TWRP Recovery (Recommended)
> [!TIP]
> If you don't have TWRP installed yet, download our official [TWRP Recovery package for Galaxy A14 5G (`twrp-12-vsd-dze1.tar`)](https://github.com/multi-forge/android_device_samsung_a14x/releases/tag/unbrick-dze1) and flash it to the **AP** (or **RECOVERY**) slot via Odin following the instructions in our [Device Tree repository](https://github.com/multi-forge/android_device_samsung_a14x).

Because Android 15 uses FBE encryption on `/data`, TWRP cannot read internal storage directly without formatting. To install without wiping data:
1. Download `NightKernel-v1.2.0-a14x.zip`.
2. Copy the `.zip` file to your device's `/cache/` partition (unencrypted ext4, fully accessible by TWRP) or use a MicroSD card / USB OTG drive:
   ```bash
   # Example via root terminal on the device:
   su -c "cp /path/to/NightKernel-v1.2.0-a14x.zip /cache/ && chmod 644 /cache/NightKernel-v1.2.0-a14x.zip"
   ```
3. Reboot into TWRP Recovery.
4. Tap **Install** ➔ Tap **Select Storage: Cache** (or MicroSD / USB OTG).
5. Select `NightKernel-v1.2.0-a14x.zip` and swipe to confirm (**Swipe to confirm Flash**).
6. Tap **Reboot System**.

### Method 2: Direct Terminal Flashing (If Already Rooted)
If your device currently has working root access, you can flash the image directly to the block device:
```bash
# 1. Write boot.img to the official boot partition
su -c "dd if=/path/to/boot.img of=/dev/block/by-name/boot bs=4096 && sync"

# 2. Reboot the system
su -c "reboot"
```

### Method 3: Flashing via Odin / Download Mode
1. Turn off the device completely.
2. Hold `Vol+` + `Vol-` together and connect the USB cable to a computer to enter **Download Mode**.
3. Press `Vol+` once to confirm entering Download Mode.
4. Open **Odin** (v3.14.4 or newer) and load `boot-NightKernel-v1.2.0.tar` into the **AP** (or **BOOT**) slot.
5. Click **Start** to flash.

---

## 🕹️ Feature Usage & Tips

### 1. Entering TWRP Without a USB Cable
To reboot into recovery without connecting to a computer:
```bash
su -c "echo 1 > /proc/nightkernel_reboot"
```
The kernel will write the reset magic to the PMU and reboot directly into TWRP.

### 2. Enabling NTSync in Winlator / Mobox
1. Open your emulator and navigate to Container Settings / Wine Configuration.
2. Under thread synchronization settings (**Wine Sync / Async Engine**), select **NTSync**.
3. Launch your game to enjoy lower thread latency and smoother frame rates.

### 3. Superuser Management (KernelSU / ReSukiSU)
Install the **KernelSU Manager** or **ReSukiSU Manager** APK to:
- Grant superuser permissions on a per-app basis.
- Configure SuSFS root hiding settings.
- Manage system modules and extensions.

### 4. Display Calibration (KCAL)
Install any KCAL-compatible app from GitHub or the Play Store to adjust RGB balance, contrast, saturation, and display hue directly on your screen.

---

## ⚖️ License & Acknowledgments

**NightKernel** is an open-source project licensed under the [GPL-2.0](LICENSE), in strict adherence to the Linux Kernel licensing and Samsung Open Source policies.

### Special Thanks:
- **Samsung Electronics Co., Ltd.** for the Exynos 1330 kernel source.
- **Physwizz** for the initial Galaxy A14 5G kernel tree.
- **MrPankaj24 & The Project-24 Team** for porting NTSync, KCAL, and display patches.
- **simonpunk** for creating SuSFS (Kernel-level Root Hiding).
- **Tiann & The ReSukiSU Team** for the KernelSU and ReSukiSU projects.
- **nullptr-t-oss** for the System V IPC patch with Android KABI padding.
- **osm0sis** for the universal AnyKernel3 installer.
- The Android open-source community and independent developers.
