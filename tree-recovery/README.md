# TWRP Device Tree for Samsung Galaxy A14 5G (`a14x`)

[English](README.md) | [Português](README_PT.md)

<p align="center">
  <img src="https://raw.githubusercontent.com/multi-forge/NightKernel-a14x/main/assets/banner.jpg" alt="NightKernel & TWRP" width="100%">
</p>

Official TWRP recovery device tree, persistence modules, and unbricking resources for the **Samsung Galaxy A14 5G** (`SM-A146M` / `SM-A146B`), **Exynos 1330 (`s5e8535`)**, running **Android 15 (One UI 7 - PDA `A146MUBSDDZE1`, Binary D)**.

---

## Device Specifications

| Item | Specification |
|---|---|
| **Device** | Samsung Galaxy A14 5G (`SM-A146M/DS` / `SM-A146B`) |
| **SoC** | Samsung Exynos 1330 (2× Cortex-A78 @ 2.4 GHz + 6× Cortex-A55 @ 2.0 GHz) |
| **GPU** | ARM Mali-G68 MP2 |
| **Audio Codec** | Realtek `RT5691` |
| **PDA / AP** | `A146MUBSDDZE1` |
| **CSC** | `A146MOWODDZE1` (OWO / ZTO / LATAM) |
| **Android Version** | Android 15 / One UI 7 (Binary D) |
| **Kernel Baseline** | Linux `5.15.180` (physwizz `V-sd-perm`) |
| **Recovery Partition** | `100,663,296` bytes (96 MB) — Boot Header v2 |
| **Boot Partition** | `67,108,864` bytes (64 MB) — Boot Header v4 (ramdisk 0) |
| **Init Boot Partition** | `16,777,216` bytes (16 MB) — Contains system ramdisk |
| **Custom Kernel** | [multi-forge/NightKernel-a14x](https://github.com/multi-forge/NightKernel-a14x) |

---

## Technical Notes

### 1. Partitioning and Boot Header
- Recovery partition is `/dev/block/by-name/recovery` (96 MB) using the **Boot Header v2** format (kernel + TWRP ramdisk + compiled `s5e8535` DTB).
- Includes **Fastbootd** mode support for flashing dynamic partitions (`system`, `vendor`, `product`, `system_ext`).

### 2. Anti-Recovery Restore (`keep-twrp`)
Stock Samsung firmwares run `/system/bin/install-recovery.sh` on boot to restore stock recovery from `/system/recovery-from-boot.p`.
- The [`modules/keep-twrp`](modules/keep-twrp) module runs in early init (Magisk/KernelSU) to block writes to the recovery partition, preventing TWRP from being overwritten by the system.

### 3. FBE Encryption & `/cache` Failsafe
Android 15 uses File-Based Encryption (FBE) backed by TrustZone Keystore. TWRP cannot decrypt internal storage (`/sdcard`).
- The `/cache` partition (`/dev/block/by-name/cache`, ext4) is unencrypted and mounted by TWRP with full read/write permissions.
- You can store recovery zips and backup images directly in `/cache/` or use an external MicroSD card / USB OTG.

### 4. Bootloader USB Handshake Bypass
Stock Samsung bootloader ignores recovery hardware keys (`Power + Vol Up`) during cold boot unless a USB cable is connected to a PC.
- When running [NightKernel](https://github.com/multi-forge/NightKernel-a14x), this restriction is bypassed. You can reboot to TWRP without a PC via:
  ```bash
  echo 1 > /proc/nightkernel_reboot
  ```
  or by holding `Power + Vol Up` while rebooting.

---

## Installation

### Method 1: Odin / Heimdall (Download Mode)
1. Boot device into Download Mode (`Vol+ + Vol-` with USB cable connected to PC).
2. Download [`twrp-12-vsd-dze1.tar`](https://github.com/multi-forge/android_device_samsung_a14x/releases/tag/unbrick-dze1).
3. Place `twrp-12-vsd-dze1.tar` in the **AP** slot in Odin.
4. Uncheck **Auto Reboot** in Odin settings.
5. Flash. Once finished, force reboot with `Vol- + Power` and immediately hold `Vol+ + Power` (with USB cable connected) to boot directly into TWRP on first boot.

### Method 2: Terminal (Root)
```bash
dd if=recovery.img of=/dev/block/by-name/recovery bs=4096 && sync
```

---

## Unbricking
Official stock dumps for recovery and boot restoration are available in the [unbrick-dze1 Release](https://github.com/multi-forge/android_device_samsung_a14x/releases/tag/unbrick-dze1):
- `unbrick-dze1-recovery.tar`: Restores stock recovery.
- `unbrick-dze1-boot.tar`: Restores stock `boot` and `init_boot`.

---

## Links
- **TWRP Downloads:** [Releases](https://github.com/multi-forge/android_device_samsung_a14x/releases)
- **NightKernel Source:** [NightKernel-a14x](https://github.com/multi-forge/NightKernel-a14x)
