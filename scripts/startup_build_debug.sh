#!/bin/bash
set -x
exec > >(tee -a /var/log/kernel-build.log) 2>&1

CODENAME="NightKernel-debug"
GCS_BASE="gs://laya-onnx-stt-465818/nightkernel-v123-clang22"

echo "=== STARTING ${CODENAME} BUILD (Clang 22 / NO-LTO / FAST-DEBUG) $(date) ==="

ZONE=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone | awk -F/ '{print $NF}')
INSTANCE_NAME=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/name)
PROJECT_ID=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/project/project-id)

cleanup() {
    echo "=== CLEANING UP INSTANCE $INSTANCE_NAME in $ZONE ==="
    gcloud storage cp /var/log/kernel-build.log "${GCS_BASE}/build-debug.log" || true
    gcloud compute instances delete "$INSTANCE_NAME" --zone="$ZONE" --project="$PROJECT_ID" --quiet || true
}
trap cleanup EXIT

# 1. Mount 24GB tmpfs in RAM
echo "=== MOUNTING 24GB RAM DISK (tmpfs) ==="
if grep -q " /build " /proc/mounts; then umount /build || true; fi
mkdir -p /build
mount -t tmpfs -o size=24G tmpfs /build

mkdir -p /build/toolchains /build/kernel /build/patches /build/ccache-bin /build/artifacts /build/anykernel3 /build/boot_work

# 2. Attach and mount persistent ccache disk
echo "=== MOUNTING PERSISTENT CCACHE DISK ==="
if grep -q " /mnt/ccache " /proc/mounts; then umount /mnt/ccache || true; fi
mkdir -p /mnt/ccache
if [ -e /dev/disk/by-id/google-a14x-ccache ]; then
    mount -o discard,defaults /dev/disk/by-id/google-a14x-ccache /mnt/ccache || true
    mkdir -p /mnt/ccache/nightkernel-ccache
    export CCACHE_DIR=/mnt/ccache/nightkernel-ccache
fi

export CCACHE_MAXSIZE=14G
export CCACHE_COMPRESS=1
export CCACHE_COMPRESSLEVEL=1
export USE_CCACHE=1
which ccache && ccache -M 14G && ccache -z

# 3. Base Packages & Clang 22 Setup
export DEBIAN_FRONTEND=noninteractive
apt-get update -y -o Acquire::Retries=5 -o Acquire::http::Timeout=30 -o Acquire::http::Pipeline-Depth=0
for i in 1 2 3; do apt-get install -y -o Acquire::Retries=5 -o Acquire::http::Timeout=30 -o Acquire::http::Pipeline-Depth=0 software-properties-common wget gnupg && break; sleep 5; done
add-apt-repository -y universe
apt-get update -y
for i in 1 2 3; do apt-get install -y -o Acquire::Retries=5 -o Acquire::http::Timeout=30 -o Acquire::http::Pipeline-Depth=0 git curl tar bc bison flex libssl-dev make gcc g++ libelf-dev python3 libncurses-dev zip zstd ccache dwarves patch rsync qemu-user-static binfmt-support pigz && break; sleep 10; done || true

echo "deb http://apt.llvm.org/noble/ llvm-toolchain-noble-22 main" > /etc/apt/sources.list.d/llvm22.list
wget -qO /etc/apt/trusted.gpg.d/apt.llvm.org.asc https://apt.llvm.org/llvm-snapshot.gpg.key
apt-get update -y -o Acquire::Retries=5 -o Acquire::http::Timeout=30 || true
for i in 1 2 3; do apt-get install -y -o Acquire::Retries=5 -o Acquire::http::Timeout=30 -o Acquire::http::Pipeline-Depth=0 clang-22 lld-22 llvm-22 llvm-22-tools && break; sleep 10; done || true
command -v clang-22 || { echo "FATAL: clang-22 ausente"; exit 1; }

mkdir -p /usr/local/clang22/bin
for t in clang clang++ ld.lld llvm-ar llvm-nm llvm-objcopy llvm-objdump llvm-readelf llvm-strip; do
    if [ -f "/usr/bin/${t}-22" ]; then
        ln -sf "/usr/bin/${t}-22" "/usr/local/clang22/bin/${t}"
    fi
done

# Wrapper ccache
mkdir -p /build/ccache-bin
ln -sf "$(which ccache)" /build/ccache-bin/clang
ln -sf "$(which ccache)" /build/ccache-bin/clang++
ln -sf "$(which ccache)" /build/ccache-bin/aarch64-linux-gnu-gcc
ln -sf "$(which ccache)" /build/ccache-bin/aarch64-linux-gnu-g++

# 4. Clone AOSP Prebuilt Build Tools
git clone --depth=1 -b main https://android.googlesource.com/kernel/prebuilts/build-tools /build/toolchains/build-tools

# 5. Clone Kernel Source
cd /build/kernel
git init
git remote add origin https://github.com/multi-forge/NightKernel-a14x.git
git fetch --depth 1 origin debug
git checkout debug

# 6. Apply patches & compatibility
cd /build/kernel
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
export KCFLAGS="-Wno-error"

# 8. Defconfig
cp configs/nightkernel_debug_defconfig .config
make olddefconfig

# 9. Fast Compile
CPUS=$(nproc)
JOBS=$(( CPUS + 4 ))
echo "=== COMPILING DEBUG KERNEL ON RAM tmpfs WITH $JOBS JOBS (NO LTO) ==="
BUILD_START=$(date +%s)
make -j"$JOBS" 2>&1 | tee /build/build_debug.log
BUILD_END=$(date +%s)
echo "=== COMPILED IN $(( BUILD_END - BUILD_START )) SECONDS ==="

if [ ! -f arch/arm64/boot/Image ]; then
    echo "ERROR: arch/arm64/boot/Image not found!"
    exit 1
fi

# 10. Package AnyKernel3
cp arch/arm64/boot/Image /build/artifacts/Image
cp .config /build/artifacts/nightkernel-debug.config

git clone --depth=1 https://github.com/osm0sis/AnyKernel3 /build/anykernel3
cp arch/arm64/boot/Image /build/anykernel3/Image

cat << 'AK3EOF' > /build/anykernel3/anykernel.sh
### AnyKernel3 Ramdisk Mod Script
properties() { '
kernel.string=NightKernel-debug (Fast Build / Verbose Logging / PStore / 5.15.197) by Multi-Forge
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
'; }
BLOCK=/dev/block/by-name/boot;
IS_SLOT_DEVICE=0;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;
. tools/ak3-core.sh;
split_boot;
flash_boot;
AK3EOF

cd /build/anykernel3 && zip -r9 /build/artifacts/NightKernel-debug-a14x.zip * -x .git README.md *placeholder

# 11. Boot.img & Odin Tar
mkdir -p /build/boot_work && cd /build/boot_work
gcloud storage cp "${GCS_BASE}/A146b-V-ue-boot.tar" .
tar -xvf A146b-V-ue-boot.tar
if [ -f boot.img ]; then
    /build/anykernel3/tools/magiskboot unpack boot.img || true
    if [ -f kernel ]; then
        cp /build/artifacts/Image kernel
        /build/anykernel3/tools/magiskboot repack boot.img /build/artifacts/boot.img || true
        if [ -f /build/artifacts/boot.img ]; then
            tar -cvf /build/artifacts/boot-NightKernel-debug.tar -C /build/artifacts boot.img
        fi
    fi
fi

cd /build/artifacts
sha256sum Image nightkernel-debug.config NightKernel-debug-a14x.zip boot.img boot-NightKernel-debug.tar > sha256sums.txt

echo "=== UPLOADING DEBUG ARTIFACTS TO GCS ==="
gcloud storage cp -r /build/artifacts/* "${GCS_BASE}/artifacts-debug/"

echo "=== DEBUG BUILD COMPLETE AT $(date) ==="
sync
