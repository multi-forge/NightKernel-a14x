# Samsung Galaxy A14 5G (`SM-A146M/DS` / `SM-A146B` — `a14x`)

<p align="center">
  <a href="README.md"><img src="https://img.shields.io/badge/Language-English-blue?style=for-the-badge&logo=google-translate" alt="English"></a>
  <a href="README_PT.md"><img src="https://img.shields.io/badge/L%C3%ADngua-Portugu%C3%AAs%20(Brasil)-green?style=for-the-badge&logo=google-translate" alt="Português"></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Device-Samsung%20Galaxy%20A14%205G-blue?style=for-the-badge&logo=samsung" alt="Device">
  <img src="https://img.shields.io/badge/SoC-Exynos%201330%20(s5e8535)-orange?style=for-the-badge" alt="SoC">
  <img src="https://img.shields.io/badge/Android-15%20(One%20UI%207)-green?style=for-the-badge&logo=android" alt="Android">
  <img src="https://img.shields.io/badge/Recovery-TWRP%20v3.7%20Persistent%20🟢-brightgreen?style=for-the-badge" alt="Recovery">
</p>

<p align="center">
  <a href="https://github.com/multi-forge/android_device_samsung_a14x/releases/tag/unbrick-dze1"><img src="https://img.shields.io/badge/Download-TWRP%20Recovery%20(DZE1)-red?style=for-the-badge&logo=twrp" alt="Download TWRP"></a>
  <a href="https://github.com/multi-forge/NightKernel-a14x"><img src="https://img.shields.io/badge/Kernel-NightKernel%20a14x-purple?style=for-the-badge" alt="NightKernel"></a>
</p>

Official repository for the Device Tree, recovery persistence modules, kernel configurations, and unbricking procedures for the **Samsung Galaxy A14 5G** (`SM-A146M` and `SM-A146B`, codename `a14x`), powered by the **Exynos 1330 (`s5e8535`)** platform, running **Android 15 (One UI 7 - PDA `A146MUBSDDZE1`, Binary D)**.

---

## 📱 Device Technical Specifications

| Parameter | Value / Specification |
|---|---|
| **Model** | Samsung Galaxy A14 5G (`SM-A146M/DS` / `SM-A146B`) |
| **Codename** | `a14x` / `s5e8535` |
| **SoC / Chipset** | Samsung Exynos 1330 (2× Cortex-A78 @ 2.4 GHz + 6× Cortex-A55 @ 2.0 GHz) |
| **GPU** | ARM Mali-G68 MP2 |
| **Audio Codec** | `SMA1305` |
| **PDA / AP** | `A146MUBSDDZE1` |
| **CSC** | `A146MOWODDZE1` (OWO / ZTO / LATAM) |
| **Android Version** | Android 15 / One UI 7 (Binary D - Bootloader v4/v2) |
| **Kernel Baseline** | Linux `5.15.180` (Branch `V-sd-perm`, commit `ca3d9d162`) |
| **Recovery Partition** | `100,663,296` bytes (96 MB) — Boot Header v2 |
| **Boot Partition** | `67,108,864` bytes (64 MB) — Boot Header v4 (ramdisk 0) |
| **Init Boot Partition** | `16,777,216` bytes (16 MB) — Contains system ramdisk |
| **Official Custom Kernel** | [multi-forge/NightKernel-a14x](https://github.com/multi-forge/NightKernel-a14x) |

---

## 🛠️ TWRP Recovery Architecture on Android 15

### 1. Partitioning and Image Format
- Recovery is hosted on the `/dev/block/by-name/recovery` partition (96 MB) using the **Boot Header v2** format (embedded kernel + TWRP ramdisk + compiled Samsung `s5e8535` DTB).
- Integrated **Fastbootd** mode support for flashing dynamic partitions (`system`, `vendor`, `product`, `system_ext`).

### 2. Persistence Mechanism (Anti-Recovery Restore)
Stock Samsung firmwares attempt to automatically restore the stock recovery on every boot via `/system/bin/install-recovery.sh` and `/system/recovery-from-boot.p`.
- **How we prevent overwrite:** 
  - The [modules/keep-twrp](modules/keep-twrp) module is injected into the early boot environment (Magisk/KernelSU).
  - It intercepts restore scripts and blocks unauthorized write calls to the recovery partition, ensuring TWRP remains permanently installed across reboots.

### 3. Local `/cache` Failsafe Suite (Bypassing FBE Encryption)
On Android 15, the `/data` partition uses File-Based Encryption (FBE) backed by TrustZone hardware keystore keys. As a result, TWRP **does not decrypt** internal storage (`/sdcard`).
- **Architectural Solution:** 
  - The `/cache` partition (`/dev/block/by-name/cache`, ext4) **is unencrypted** and mounted natively by TWRP with full read/write permissions.
  - A permanent unbrick suite is maintained inside `/cache`:
    - `/cache/Restore-Stock-Boot.zip`: AnyKernel3 package for instant 1-click stock restoration.
    - `/cache/Kernel-Base-a14x-Vsd.zip`: AnyKernel3 base kernel package.
    - `/cache/boot-backup.img`: Raw 64 MB dump of the functional boot partition.
    - `/cache/restore_boot.sh`: Direct executable shell script for TWRP Terminal.

### 4. Bootloader USB Handshake (`sboot`) & Autonomous Solution
On Samsung's stock bootloader for the Exynos 1330:
- Cold-booting into recovery using hardware keys (`Vol+` + `Power`) **requires a connected USB cable** plugged into a PC or charger (`VBUS` power detection / USB handshake).
- Pressing keys without an active USB cable causes the bootloader to ignore recovery requests and continue booting normal Android.
- ⚡ **Integrated Solution with NightKernel:**
  - With [NightKernel v1.2+](https://github.com/multi-forge/NightKernel-a14x) installed, this limitation is completely bypassed. You can trigger recovery programmatically at any time without a USB cable:
    ```bash
    echo 1 > /proc/nightkernel_reboot
    ```
    or simply hold `Power + Vol+` while rebooting the system.

---

## 🚀 How to Install TWRP Recovery

### Method 1: Via Odin / Heimdall (Download Mode)
1. Boot the phone into **Download Mode** (with phone powered off, hold `Vol+` + `Vol-` and connect the USB cable to a PC).
2. Open Odin and place [`twrp-12-vsd-dze1.tar`](https://github.com/multi-forge/android_device_samsung_a14x/releases/tag/unbrick-dze1) into the **AP** slot (or use Heimdall to flash the `RECOVERY` partition).
3. In Odin, **uncheck** the **Auto Reboot** option.
4. Click Start. Once completed, force a reboot by holding `Vol-` + `Power`. As soon as the screen turns black, immediately switch to holding `Vol+` + `Power` (keeping the USB cable connected) to boot directly into TWRP.

### Method 2: Directly via Root Terminal
```bash
su
dd if=/path/to/recovery.img of=/dev/block/by-name/recovery bs=4096
sync
```

---

## 🆘 Unbricking Procedure (Odin / Brokkr)

If partition corruption or a critical boot failure occurs during experiments:
1. Put the device into Download Mode (`Vol -` + `Vol +` with USB cable).
2. Download official artifacts from [Release unbrick-dze1](https://github.com/multi-forge/android_device_samsung_a14x/releases/tag/unbrick-dze1):
   - `unbrick-dze1-recovery.tar`: Restores `/dev/block/by-name/recovery`.
   - `unbrick-dze1-boot.tar`: Restores `/dev/block/by-name/boot` and `/dev/block/by-name/init_boot`.
3. Flash via Odin (PC) or Brokkr (OTG from another Android device).

---

## 🔐 Verification Checksums (Stock DZE1 Baseline)

```text
05fdc90b152966526553dca7bdbf21a0e35464d4905221adf49ee9677b732e32  recovery-stock.img
7659b2fd80a7d8537fba98073179f338bf205fb1694abe81b2134690754a2545  boot-current.img
2c0b60b7c93a184029d590ff508d920a5c205787ba248f423af348ca1553f423  init_boot-current.img
19c06b501ef7e0cfdd33d513078da98eaaecda7d4ab56bc83dcbb4fe81031015  dtbo-stock.img
9824851c3fda31a911ccc4fc6e134306e6f0ac502218375d7b3bd2a2289cec15  vbmeta-stock.img
cecc9b258175e228fc80c2237b8ba9baa66b93be4540cc5c8728d60f8718163f  config.gz
4bdf87b9274fb1e31c4aab5bc2fa871498a69b5499c6cb91b6011a722835af3f  unbrick-dze1-recovery.tar
0c388562d71dc648134fe43d4a501dd339cc7998106b49125c19f9daacd71cab  unbrick-dze1-boot.tar
```

---

## 🔗 Related Projects
- **Official Custom Kernel:** [multi-forge/NightKernel-a14x](https://github.com/multi-forge/NightKernel-a14x)
- **Kernel Source Baseline:** [physwizz/a146b-a146m](https://github.com/physwizz/a146b-a146m) (branch `V-sd-perm`)
