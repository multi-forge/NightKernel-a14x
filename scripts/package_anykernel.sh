#!/usr/bin/env bash
# ==============================================================================
# AnyKernel3 Packaging Script for NightKernel (Galaxy A14 5G - Header v4)
# ==============================================================================
set -euo pipefail

IMAGE_PATH="${1:-Image}"
OUTPUT_ZIP="${2:-NightKernel-Base-a14x.zip}"

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
kernel.string=NightKernel 5.15.180 (A146MUBSDDZE1) by Multi-Forge
do.devicecheck=1
do.modules=0
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
## end boot install
EOF

cp "${IMAGE_PATH}" "${AK3_DIR}/Image"
cd "${AK3_DIR}"
zip -r9 "${OUTPUT_ZIP}" * -x .git README.md *placeholder
mv "${OUTPUT_ZIP}" "${OLDPWD}/"
cd "${OLDPWD}"
rm -rf "${AK3_DIR}"

echo "[+] AnyKernel3 zip gerado com sucesso: ${OUTPUT_ZIP}"
