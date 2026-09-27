#!/bin/bash
set -x
exec > >(tee -a /var/log/kernel-build.log) 2>&1

echo "=== STARTING NIGHTKERNEL v1.2.1 (PHYSWIZZ BINARY E 5.15.197 BUMP) BUILD WORKER $(date) ==="

ZONE=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone | awk -F/ '{print $NF}')
INSTANCE_NAME=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/name)
PROJECT_ID=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/project/project-id)
GCS_BASE="gs://laya-onnx-stt-465818/nightkernel-v121"

cleanup() {
    echo "=== CLEANING UP INSTANCE $INSTANCE_NAME in $ZONE ==="
    gcloud compute instances delete "$INSTANCE_NAME" --zone="$ZONE" --project="$PROJECT_ID" --quiet || true
}
trap cleanup EXIT

# 1. Install dependencies & QEMU for arm64 binaries (magiskboot)
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y software-properties-common
add-apt-repository -y universe
apt-get update -y
apt-get install -y git curl tar bc bison flex libssl-dev make gcc g++ libelf-dev python3 libncurses-dev zip zstd ccache dwarves patch rsync qemu-user-static binfmt-support || true

# 2. Toolchain setup
mkdir -p /build/toolchains
cd /build/toolchains

# Clang AOSP r450784d (clone from reliable GitHub mirror)
echo "=== CLONING CLANG r450784d ==="
git clone --depth=1 https://github.com/TheBizarreAbhishek/clang-r450784d /build/toolchains/clang-r450784d

# Build tools
echo "=== CLONING BUILD TOOLS ==="
git clone --depth=1 -b main https://android.googlesource.com/kernel/prebuilts/build-tools /build/toolchains/build-tools

# 3. Kernel Source (V-ue commit 69d6e0522 = clean 5.15.197 without KSU)
echo "=== CLONING KERNEL SOURCE V-ue (5.15.197 Binary E) ==="
mkdir -p /build/kernel && cd /build/kernel
git init
git remote add origin https://github.com/physwizz/a146b-a146m.git
git fetch --depth 2 origin main
git checkout 69d6e0522

# Download patches from GCS
mkdir -p /build/patches
gcloud storage cp "${GCS_BASE}/patches/*.patch" /build/patches/

# 4. Apply P4B Autonomous Recovery Patches
echo "=== APPLYING AUTONOMOUS RECOVERY PATCHES ==="
sed -i 's/static char panic_str\[10\] = "panic";/static char panic_str\[10\] = "recovery";/' drivers/samsung/sec_reboot.c

cat << 'PROCEOF' >> kernel/reboot.c

/* ========================================================================== */
/* NightKernel Autonomous Recovery Interface                                  */
/* Allows unprivileged and programmatic reboot to TWRP without USB handshake  */
/* ========================================================================== */
#include <linux/proc_fs.h>
#include <linux/uaccess.h>

static ssize_t nightkernel_reboot_read(struct file *file, char __user *buf, size_t count, loff_t *ppos)
{
	const char *msg = "NightKernel Autonomous Recovery Interface\nUsage: echo 1 > /proc/nightkernel_reboot\n";
	return simple_read_from_buffer(buf, count, ppos, msg, strlen(msg));
}

static ssize_t nightkernel_reboot_write(struct file *file, const char __user *buf, size_t count, loff_t *ppos)
{
	char kbuf[32];
	size_t len = min(count, sizeof(kbuf) - 1);

	if (copy_from_user(kbuf, buf, len))
		return -EFAULT;
	kbuf[len] = '\0';

	if (strstr(kbuf, "1") || strstr(kbuf, "recovery")) {
		pr_emerg("NightKernel: Autonomous reboot to recovery requested!\n");
		kernel_restart("recovery");
	}
	return count;
}

static const struct proc_ops nightkernel_reboot_fops = {
	.proc_read = nightkernel_reboot_read,
	.proc_write = nightkernel_reboot_write,
};

static int __init nightkernel_reboot_init(void)
{
	struct proc_dir_entry *ent = proc_create("nightkernel_reboot", 0666, NULL, &nightkernel_reboot_fops);
	if (!ent)
		pr_err("NightKernel: Failed to create /proc/nightkernel_reboot\n");
	else
		pr_info("NightKernel: Autonomous recovery interface initialized (/proc/nightkernel_reboot)\n");
	return 0;
}
late_initcall(nightkernel_reboot_init);
PROCEOF

# 5. Inject ReSukiSU + Safety Patch
echo "=== INJECTING RESUKISU ==="
curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" | bash -s main
cd KernelSU && patch -p1 --forward < /build/patches/03_resukisu_safety.patch || true && cd ..

# 6. Inject SuSFS 2.1.0 + Stock A14 Reject Fix
echo "=== INJECTING SUSFS 2.1.0 ==="
git clone --depth=1 -b gki-android13-5.15 https://gitlab.com/simonpunk/susfs4ksu.git /tmp/susfs_repo
cd /tmp/susfs_repo && git checkout 9f0415bb2c8fc581e93d384e09aba088bd36733a || true && cd /build/kernel
cp -rf /tmp/susfs_repo/kernel_patches/fs/* fs/
cp -rf /tmp/susfs_repo/kernel_patches/include/linux/* include/linux/
patch -p1 --forward < /tmp/susfs_repo/kernel_patches/50_add_susfs_in_gki-android13-5.15.patch || true
patch -p1 --forward < /build/patches/02_susfs_fix_stock_a14.patch || true
rm -rf /tmp/susfs_repo

# 7. Apply NTSYNC (Wine / Emulator kernel sync)
echo "=== APPLYING NTSYNC PATCHES ==="
patch -p1 --forward < /build/patches/04_ntsync_base.patch || true
patch -p1 --forward < /build/patches/05_ntsync_compat.patch || true

# 8. Apply DroidSpaces Patch
echo "=== APPLYING DROIDSPACE PATCH ==="
patch -p1 --forward < /build/patches/06_droidspace.patch || true

# 9. Setup Baseband Guard (BBG)
echo "=== SETTING UP BASEBAND GUARD ==="
curl -LSs https://github.com/vc-teahouse/Baseband-guard/raw/main/setup.sh | bash || true

# 10. Apply KCAL Color Control
echo "=== APPLYING KCAL PATCH ==="
patch -p1 --forward < /build/patches/07_kcal_dqe.patch || true

# 11. Apply CRCs Disable
echo "=== APPLYING CRCS DISABLE PATCH ==="
patch -p1 --forward < /build/patches/08_crcs_disable.patch || true

# Clean up patch residue
find . -name "*.orig" -delete -o -name "*.rej" -delete

# 12. Setup persistent ccache disk
echo "=== SETTING UP CCACHE DISK ==="
mkdir -p /mnt/ccache
if [ -e /dev/disk/by-id/google-a14x-ccache ]; then
    if ! blkid /dev/disk/by-id/google-a14x-ccache; then
        mkfs.ext4 -m 0 -F /dev/disk/by-id/google-a14x-ccache
    fi
    mount -o noatime /dev/disk/by-id/google-a14x-ccache /mnt/ccache
    export CCACHE_DIR=/mnt/ccache
else
    export CCACHE_DIR=/build/.ccache
fi
mkdir -p "$CCACHE_DIR"
ccache -M 14G
ccache -s

# Setup ccache wrappers
mkdir -p /build/ccache-bin
cat << 'EOF' > /build/ccache-bin/clang
#!/bin/bash
exec ccache /build/toolchains/clang-r450784d/bin/clang "$@"
EOF
cat << 'EOF' > /build/ccache-bin/clang++
#!/bin/bash
exec ccache /build/toolchains/clang-r450784d/bin/clang++ "$@"
EOF
chmod +x /build/ccache-bin/clang /build/ccache-bin/clang++

# Environment
export PATH=/build/ccache-bin:/build/toolchains/clang-r450784d/bin:/build/toolchains/build-tools/path/linux-x86:$PATH
export ARCH=arm64
export SUBARCH=arm64
export LLVM=1
export TARGET_SOC=s5e8535
export DTC_FLAGS="-@"
export PLATFORM_VERSION=15
export ANDROID_MAJOR_VERSION=v

# 13. Download and Apply Defconfig
echo "=== DOWNLOADING DEFCONFIG FROM GCS ==="
gcloud storage cp "${GCS_BASE}/nightkernel_v1.2.1_defconfig" .config

make olddefconfig

# Validate critical flags
echo "=== VALIDATING CONFIGURATION ==="
grep "CONFIG_KSU=y" .config
grep "CONFIG_KSU_SUSFS=y" .config
grep "CONFIG_NTSYNC=y" .config
grep "CONFIG_BBG=y" .config
grep "CONFIG_KCAL_CTRL=y" .config
grep "CONFIG_LOCALVERSION=\"-NightKernel-v1.2.1\"" .config

# 14. Compile Kernel
echo "=== COMPILING NIGHTKERNEL v1.2.1 ==="
make -j$(nproc)

echo "=== CCACHE STATS ==="
ccache -s

# 15. Check output
if [ ! -f arch/arm64/boot/Image ]; then
    echo "ERROR: arch/arm64/boot/Image not found!"
    exit 1
fi

echo "=== BUILD SUCCESSFUL ==="
ls -lh arch/arm64/boot/Image

# 16. Package AnyKernel3
mkdir -p /build/artifacts
cp arch/arm64/boot/Image /build/artifacts/Image
cp .config /build/artifacts/nightkernel-v1.2.1.config

git clone --depth=1 https://github.com/osm0sis/AnyKernel3 /build/anykernel3
cp arch/arm64/boot/Image /build/anykernel3/Image

cat << 'AK3EOF' > /build/anykernel3/anykernel.sh
### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() { '
kernel.string=NightKernel v1.2.1 (5.15.197 Binary E) by Multi-Forge
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
BLOCK=/dev/block/by-name/boot;
IS_SLOT_DEVICE=0;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

. tools/ak3-core.sh;

split_boot;
flash_boot;
AK3EOF

cd /build/anykernel3 && zip -r9 /build/artifacts/NightKernel-v1.2.1-a14x.zip * -x .git README.md *placeholder

# 17. Create repacked raw boot.img and Odin tar from Binary E base
echo "=== CREATING REPACKED BINARY E BOOT.IMG & ODIN TAR ==="
mkdir -p /build/boot_work && cd /build/boot_work
gcloud storage cp "${GCS_BASE}/A146b-V-ue-boot.tar" .
tar -xvf A146b-V-ue-boot.tar

if [ -f boot.img ]; then
    /build/anykernel3/tools/magiskboot unpack boot.img || true
    if [ -f kernel ]; then
        cp /build/artifacts/Image kernel
        /build/anykernel3/tools/magiskboot repack boot.img /build/artifacts/boot.img || true
        if [ -f /build/artifacts/boot.img ]; then
            tar -cvf /build/artifacts/boot-NightKernel-v1.2.1.tar -C /build/artifacts boot.img
        fi
    fi
fi

cd /build/artifacts
sha256sum Image nightkernel-v1.2.1.config NightKernel-v1.2.1-a14x.zip boot.img boot-NightKernel-v1.2.1.tar > sha256sums.txt

# 18. Upload to GCS bucket for direct private retrieval (NO GITHUB PUSH, NO PUBLIC RELEASE)
echo "=== UPLOADING ARTIFACTS TO GCS BUCKET ==="
gcloud storage cp -r /build/artifacts/* "${GCS_BASE}/artifacts/"

echo "=== BUILD COMPLETE AND SAVED TO GCS $(date) ==="
sync
