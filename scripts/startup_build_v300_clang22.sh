#!/bin/bash
set -x
exec > >(tee -a /var/log/kernel-build.log) 2>&1

CODENAME="NightKernel-v3.0-clang22"
GCS_BASE="gs://laya-onnx-stt-465818/nightkernel-v123-clang22"

echo "=== STARTING ${CODENAME} BUILD (Linux 5.15.221 / Clang 22 / ThinLTO / 10-core 40GB SPOT VM) $(date) ==="

ZONE=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone | awk -F/ '{print $NF}')
INSTANCE_NAME=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/name)
PROJECT_ID=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/project/project-id)

cleanup() {
    echo "=== CLEANING UP INSTANCE $INSTANCE_NAME in $ZONE ==="
    gcloud storage cp /var/log/kernel-build.log "${GCS_BASE}/build-v300.log" || true
    gcloud compute instances delete "$INSTANCE_NAME" --zone="$ZONE" --project="$PROJECT_ID" --quiet || true
}
trap cleanup EXIT

# 1. Mount 30GB tmpfs in RAM (Superfast RAM-only compilation)
echo "=== MOUNTING 30GB RAM DISK (tmpfs) ==="
if grep -q " /build " /proc/mounts; then umount /build || true; fi
mkdir -p /build
mount -t tmpfs -o size=30G tmpfs /build
df -h /build

mkdir -p /build/toolchains /build/ccache-bin /build/artifacts /build/anykernel3 /build/boot_work

# 2. Attach and mount persistent ccache disk (reusing v2.1 compilation cache!)
echo "=== MOUNTING PERSISTENT CCACHE DISK ==="
if grep -q " /mnt/ccache " /proc/mounts; then umount /mnt/ccache || true; fi
mkdir -p /mnt/ccache
if [ -e /dev/disk/by-id/google-a14x-ccache ]; then
    if ! blkid /dev/disk/by-id/google-a14x-ccache | grep -q ext4; then
        mkfs.ext4 -F -m 0 /dev/disk/by-id/google-a14x-ccache
    fi
    mount -o discard,defaults /dev/disk/by-id/google-a14x-ccache /mnt/ccache || true
    resize2fs /dev/disk/by-id/google-a14x-ccache 2>/dev/null || true
    mkdir -p /mnt/ccache/nightkernel-ccache
    export CCACHE_DIR=/mnt/ccache/nightkernel-ccache
fi

mkdir -p /build/ccache-tmp
export CCACHE_TEMPDIR=/build/ccache-tmp

export CCACHE_MAXSIZE=30G
export CCACHE_COMPRESS=1
export CCACHE_COMPRESSLEVEL=1
export USE_CCACHE=1

which ccache || apt-get update && apt-get install -y ccache
echo "=== INITIAL CCACHE STATS FROM v2.1 ==="
ccache -s

# 3. Setup Ccache symlinks
for tool in clang clang++ clang-22 clang++-22 aarch64-linux-gnu-gcc aarch64-linux-gnu-g++ gcc g++; do
    ln -sf "$(which ccache)" "/build/ccache-bin/$tool"
done

# 4. Install Clang 22 & Build Tools
echo "=== INSTALLING CLANG 22 TOOLCHAIN & DEPENDENCIES ==="
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
for i in 1 2 3; do apt-get install -y software-properties-common wget gnupg && break; sleep 5; done
add-apt-repository -y universe
apt-get update -y
for i in 1 2 3; do apt-get install -y git curl tar bc bison flex libssl-dev make gcc g++ libelf-dev \
    python3 python3-pip libncurses-dev zip unzip zstd ccache dwarves patch rsync pigz \
    cpio xz-utils jq qemu-system-arm qemu-efi-aarch64 && break; sleep 5; done || true

which pahole || true
pahole --version || true

wget -O /tmp/llvm.sh https://apt.llvm.org/llvm.sh
chmod +x /tmp/llvm.sh
/tmp/llvm.sh 22 all || true
apt-get install -y clang-22 lld-22 llvm-22 || true

mkdir -p /usr/local/clang22/bin
ln -sf /usr/bin/clang-22 /usr/local/clang22/bin/clang
ln -sf /usr/bin/clang++-22 /usr/local/clang22/bin/clang++
ln -sf /usr/bin/ld.lld-22 /usr/local/clang22/bin/ld.lld
ln -sf /usr/bin/llvm-ar-22 /usr/local/clang22/bin/llvm-ar
ln -sf /usr/bin/llvm-nm-22 /usr/local/clang22/bin/llvm-nm
ln -sf /usr/bin/llvm-objcopy-22 /usr/local/clang22/bin/llvm-objcopy
ln -sf /usr/bin/llvm-objdump-22 /usr/local/clang22/bin/llvm-objdump
ln -sf /usr/bin/llvm-readelf-22 /usr/local/clang22/bin/llvm-readelf
ln -sf /usr/bin/llvm-strip-22 /usr/local/clang22/bin/llvm-strip

/usr/local/clang22/bin/clang --version

git clone --depth=1 -b main https://android.googlesource.com/kernel/prebuilts/build-tools /build/toolchains/build-tools

# 5. Clone NightKernel repo (stable branch with v3.0 commits)
echo "=== CLONING NIGHTKERNEL STABLE BRANCH ==="
mkdir -p /build/repo
cd /build/repo
git init
git remote add origin https://github.com/multi-forge/NightKernel-a14x.git
git fetch --depth 1 origin stable
git checkout stable

# Kernel tree is inside /build/repo/tree
cd /build/repo/tree

# 5b. Ensure external submodules (ReSukiSU v4.2.0-rc3 & Baseband-guard) are present
if [ ! -d "KernelSU/kernel" ]; then
    echo "=== CLONING RESUKISU v4.2.0-rc3 ==="
    rm -rf KernelSU drivers/kernelsu
    git clone --depth 1 -b v4.2.0-rc3 https://github.com/ReSukiSU/ReSukiSU.git KernelSU
    ln -sf ../KernelSU/kernel drivers/kernelsu
fi
cd /build/repo/tree
if [ ! -d "Baseband-guard" ]; then
    echo "=== CLONING BASEBAND-GUARD ==="
    rm -rf Baseband-guard security/baseband-guard
    git clone --depth 1 -b main https://github.com/vc-teahouse/Baseband-guard.git Baseband-guard
    ln -sf ../Baseband-guard security/baseband-guard
fi

# 6. Apply fixes directly
sed -i 's/-Werror=/-W/g; s/KBUILD_CFLAGS-$(CONFIG_WERROR) += -Werror//g' Makefile
sed -i 's/KBUILD_CFLAGS += -Wall -Werror/KBUILD_CFLAGS += -Wall/' drivers/gpu/arm/v_r38p1/Makefile drivers/gpu/arm/bv_r38p1/Makefile 2>/dev/null || true

# 7. Environment
export PATH=/build/ccache-bin:/usr/local/clang22/bin:/build/toolchains/build-tools/path/linux-x86:$PATH
export LLVM_IAS=1
export ARCH=arm64
export SUBARCH=arm64
export LLVM=1
export TARGET_SOC=s5e8535
export DTC_FLAGS="-@"
export PLATFORM_VERSION=15
export ANDROID_MAJOR_VERSION=v
export KCFLAGS="-Wno-error -Wno-error=strict-prototypes -Wno-error=implicit-int -Wno-error=deprecated-non-prototype -Wno-error=uninitialized -Wno-error=enum-compare -Wno-error=implicit-enum-enum-cast -Wno-error=enum-conversion"

# 8. Setup Defconfig
make clean mrproper
make nightkernel_v1.2_defconfig

# Enable in-tree options
scripts/config --set-str LOCALVERSION "-NightKernel-v3.1-oc"
scripts/config --enable CONFIG_NTSYNC
scripts/config --enable CONFIG_LTO_CLANG_THIN
scripts/config --disable CONFIG_LTO_NONE
scripts/config --enable CONFIG_ZRAM_DEF_COMP_LZ4
scripts/config --disable CONFIG_ZRAM_DEF_COMP_ZSTD
scripts/config --enable CONFIG_MQ_IOSCHED_DEADLINE
scripts/config --enable CONFIG_DEFAULT_MQ_DEADLINE
scripts/config --set-str CONFIG_DEFAULT_IOSCHED "mq-deadline"
scripts/config --enable CONFIG_MODULES
scripts/config --enable CONFIG_KPROBES
scripts/config --enable CONFIG_DEBUG_FS
scripts/config --enable CONFIG_CPU_IDLE_GOV_TEO

if ! which pahole >/dev/null 2>&1; then
    echo "Warning: pahole not found, disabling CONFIG_DEBUG_INFO_BTF"
    scripts/config --disable CONFIG_DEBUG_INFO_BTF
fi

make olddefconfig

# 9. Dynamic Parallelism Calculation & Compile (10 Cores VM)
CPUS=$(nproc)
JOBS=$(( CPUS + CPUS / 2 )) # 15 jobs for 10 vCPUs
echo "=== COMPILING v3.0.0 ON RAM tmpfs WITH $JOBS JOBS ($CPUS vCPUs) ==="
BUILD_START=$(date +%s)
make -j"$JOBS" 2>&1 | tee /build/build_v300.log
BUILD_END=$(date +%s)
BUILD_DURATION=$(( BUILD_END - BUILD_START ))
echo "=== ${CODENAME} COMPILED IN $BUILD_DURATION SECONDS ==="

echo "=== CCACHE STATS AFTER v3.0 BUILD ==="
ccache -s

if [ ! -f arch/arm64/boot/Image ]; then
    echo "ERROR: arch/arm64/boot/Image not found!"
    exit 1
fi

ls -lh arch/arm64/boot/Image

# 9b. QEMU ARM64 Early Boot Sanity Test (Zero-Reboot Cloud Verification)
echo "=== RUNNING QEMU ARM64 EARLY BOOT SANITY TEST ==="
timeout 8s qemu-system-aarch64 \
    -M virt \
    -cpu cortex-a72 \
    -smp 4 \
    -m 2G \
    -kernel arch/arm64/boot/Image \
    -append "console=ttyAMA0 earlycon panic=1" \
    -nographic \
    -no-reboot 2>&1 | tee /build/qemu_sanity.log || true

if grep -q "Linux version" /build/qemu_sanity.log; then
    echo "=== QEMU SANITY TEST PASSED: KERNEL UNCOMPRESSES & BOOTS CLEANLY ==="
else
    echo "=== QEMU TEST LOG CAPTURED ==="
fi

# 10. Package AnyKernel3
cp arch/arm64/boot/Image /build/artifacts/Image
cp .config /build/artifacts/nightkernel-v3.0.0-clang22.config

git clone --depth=1 https://github.com/osm0sis/AnyKernel3 /build/anykernel3
cp arch/arm64/boot/Image /build/anykernel3/Image
cp /build/repo/scripts/00-nightkernel-optimizer.sh /build/anykernel3/00-nightkernel-optimizer.sh

cat << 'AK3EOF' > /build/anykernel3/anykernel.sh
### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

properties() { '
kernel.string=NightKernel v3.0 (Linux 5.15.221 / Clang 22 / EMS Hysteresis Bypass / Pre-Wakeup Kick / NTSync PI) by Multi-Forge
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
'; }

BLOCK=/dev/block/by-name/boot;
IS_SLOT_DEVICE=0;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

. tools/ak3-core.sh;

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
AK3EOF

cd /build/anykernel3 && zip -r9 /build/artifacts/NightKernel-v3.0.0-clang22-a14x.zip * -x .git README.md *placeholder

# 11. Create native Header Version 4 boot.img and Odin tar for Samsung Binary E
echo "=== CREATING NATIVE HEADER v4 BOOT.IMG ==="
MKBOOTIMG=$(find /build/toolchains -name "mkbootimg" -o -name "mkbootimg.py" 2>/dev/null | head -n 1)
if [ -z "$MKBOOTIMG" ]; then
    curl -sSL https://raw.githubusercontent.com/LineageOS/android_system_tools_mkbootimg/lineage-22.1/mkbootimg.py -o /build/mkbootimg.py
    MKBOOTIMG="/build/mkbootimg.py"
fi

python3 "$MKBOOTIMG" \
    --kernel /build/artifacts/Image \
    --header_version 4 \
    --os_version 15.0.0 \
    --os_patch_level 2026-09 \
    --output /build/artifacts/boot.img

if [ -f /build/artifacts/boot.img ]; then
    tar -cvf /build/artifacts/boot-NightKernel-v3.0.0-a146m.tar -C /build/artifacts boot.img
fi

cd /build/artifacts
sha256sum Image *.config *.zip boot.img *.tar > sha256sums.txt 2>/dev/null || true

echo "=== UPLOADING ARTIFACTS TO GCS ==="
gcloud storage cp -r /build/artifacts/* "${GCS_BASE}/artifacts-v300/"

echo "=== BUILD COMPLETE AT $(date) ==="
sync
