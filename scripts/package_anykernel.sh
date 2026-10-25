#!/usr/bin/env bash
# ==============================================================================
# AnyKernel3 Packaging Script for NightKernel (Galaxy A14 5G - Header v4)
# ==============================================================================
set -euo pipefail

IMAGE_PATH="${1:-Image}"
OUTPUT_ZIP="${2:-NightKernel-Zero+-v3.2-stable-a14x.zip}"

if [ ! -f "${IMAGE_PATH}" ]; then
    echo "Erro: Imagem ${IMAGE_PATH} não encontrada!"
    exit 1
fi

AK3_DIR="$(mktemp -d)"
git clone --depth 1 https://github.com/osm0sis/AnyKernel3 "${AK3_DIR}"

cat << 'EOF' > "${AK3_DIR}/anykernel.sh"
### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() { '
kernel.string=NightKernel Zero+ v3.2 (Linux 5.15.221 / Clang 22 / Dynamic Fsync / All-In-One) by Multi-Forge
do.devicecheck=1
do.modules=1
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=a14x
device.name2=a14
device.name3=s5e8535
device.name4=SM-A146M
device.name5=SM-A146B
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties

### AnyKernel install
# boot shell variables
BLOCK=/dev/block/by-name/boot;
IS_SLOT_DEVICE=0;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

# boot install (Header v4: split and repack kernel only, no ramdisk)
split_boot;
flash_boot;

# Install post-boot autonomous optimizer & debloater into /data/adb/service.d/
ui_print " ";
ui_print "--- Installing NightKernel Optimizer & Debloater ---";
mount /data 2>/dev/null || true;
if [ -d /data ]; then
  mkdir -p /data/adb/service.d;
  cp -f $home/00-nightkernel-optimizer.sh /data/adb/service.d/00-nightkernel-optimizer.sh;
  chmod 755 /data/adb/service.d/00-nightkernel-optimizer.sh;
  ui_print "    [+] Debloater service installed to /data/adb/service.d/";
fi;
## end boot install
EOF

cp "${IMAGE_PATH}" "${AK3_DIR}/Image"
cp "$(dirname "$0")/00-nightkernel-optimizer.sh" "${AK3_DIR}/00-nightkernel-optimizer.sh"
cd "${AK3_DIR}"
zip -r9 "${OUTPUT_ZIP}" * -x .git README.md *placeholder
mv "${OUTPUT_ZIP}" "${OLDPWD}/"
cd "${OLDPWD}"
rm -rf "${AK3_DIR}"

echo "[+] AnyKernel3 zip gerado com sucesso: ${OUTPUT_ZIP}"
