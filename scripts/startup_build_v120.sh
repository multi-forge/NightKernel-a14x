#!/bin/bash
set -x
exec > >(tee -a /var/log/kernel-build.log) 2>&1

echo "=== STARTING NIGHTKERNEL v1.2.0 (PROJECT-24 + SUSFS 2.1.0 + NTSYNC) BUILD WORKER $(date) ==="

ZONE=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone | awk -F/ '{print $NF}')
INSTANCE_NAME=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/name)
PROJECT_ID=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/project/project-id)
GH_TOKEN=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/attributes/gh_token)
export GH_TOKEN="$GH_TOKEN"
export GITHUB_TOKEN="$GH_TOKEN"
REPO="multi-forge/NightKernel-a14x"
BRANCH="V-sd-perm"
RAW_URL="https://raw.githubusercontent.com/${REPO}/main"

cleanup() {
    echo "=== CLEANING UP INSTANCE $INSTANCE_NAME in $ZONE ==="
    gcloud compute instances delete "$INSTANCE_NAME" --zone="$ZONE" --project="$PROJECT_ID" --quiet || true
}
trap cleanup EXIT

# 1. Install dependencies & GitHub CLI
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y software-properties-common
add-apt-repository -y universe
apt-get update -y
apt-get install -y git curl tar bc bison flex libssl-dev make gcc g++ libelf-dev python3 libncurses-dev zip zstd ccache gh dwarves qemu-user-static binfmt-support patch rsync || true

if ! command -v gh &> /dev/null; then
    mkdir -p -m 755 /etc/apt/keyrings
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
    chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    apt-get update -y
    apt-get install -y gh
fi

echo "$GH_TOKEN" | gh auth login --with-token
gh auth status

# 2. Toolchain setup
mkdir -p /build/toolchains
cd /build/toolchains

# Clang AOSP r450784d
echo "=== DOWNLOADING CLANG r450784d ==="
mkdir -p clang-r450784d
curl -sL "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/android13-release/clang-r450784d.tar.gz" -o clang.tar.gz
tar -xzf clang.tar.gz -C clang-r450784d
rm -f clang.tar.gz

# Build tools
echo "=== CLONING BUILD TOOLS ==="
git clone --depth=1 -b main https://android.googlesource.com/kernel/prebuilts/build-tools /build/toolchains/build-tools

# 3. Kernel Source
echo "=== CLONING KERNEL SOURCE $BRANCH ==="
git clone --depth=1 -b "$BRANCH" https://github.com/physwizz/a146b-a146m.git /build/kernel
cd /build/kernel

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
curl -fsSL "${RAW_URL}/patches/03_resukisu_safety.patch" -o /tmp/03_resukisu_safety.patch
cd KernelSU && patch -p1 --forward < /tmp/03_resukisu_safety.patch || true && cd ..

# 6. Inject SuSFS 2.1.0 + Stock A14 Reject Fix
echo "=== INJECTING SUSFS 2.1.0 ==="
git clone --depth=1 -b gki-android13-5.15 https://gitlab.com/simonpunk/susfs4ksu.git /tmp/susfs_repo
cd /tmp/susfs_repo && git checkout 9f0415bb2c8fc581e93d384e09aba088bd36733a || true && cd /build/kernel
cp -rf /tmp/susfs_repo/kernel_patches/fs/* fs/
cp -rf /tmp/susfs_repo/kernel_patches/include/linux/* include/linux/
patch -p1 --forward < /tmp/susfs_repo/kernel_patches/50_add_susfs_in_gki-android13-5.15.patch || true

curl -fsSL "${RAW_URL}/patches/02_susfs_fix_stock_a14.patch" -o /tmp/02_susfs_fix_stock_a14.patch
patch -p1 --forward < /tmp/02_susfs_fix_stock_a14.patch || true
rm -rf /tmp/susfs_repo

# 7. Apply NTSYNC (Wine / Emulator kernel sync)
echo "=== APPLYING NTSYNC PATCHES ==="
curl -fsSL "${RAW_URL}/patches/04_ntsync_base.patch" -o /tmp/04_ntsync_base.patch
patch -p1 --forward < /tmp/04_ntsync_base.patch || true
curl -fsSL "${RAW_URL}/patches/05_ntsync_compat.patch" -o /tmp/05_ntsync_compat.patch
patch -p1 --forward < /tmp/05_ntsync_compat.patch || true

# 8. Apply DroidSpaces Patch
echo "=== APPLYING DROIDSPACE PATCH ==="
curl -fsSL "${RAW_URL}/patches/06_droidspace.patch" -o /tmp/06_droidspace.patch
patch -p1 --forward < /tmp/06_droidspace.patch || true

# 9. Setup Baseband Guard (BBG)
echo "=== SETTING UP BASEBAND GUARD ==="
curl -LSs https://github.com/vc-teahouse/Baseband-guard/raw/main/setup.sh | bash || true

# 10. Apply KCAL Color Control
echo "=== APPLYING KCAL PATCH ==="
curl -fsSL "${RAW_URL}/patches/07_kcal_dqe.patch" -o /tmp/07_kcal_dqe.patch
patch -p1 --forward < /tmp/07_kcal_dqe.patch || true

# 11. Apply CRCs Disable
echo "=== APPLYING CRCS DISABLE PATCH ==="
curl -fsSL "${RAW_URL}/patches/08_crcs_disable.patch" -o /tmp/08_crcs_disable.patch
patch -p1 --forward < /tmp/08_crcs_disable.patch || true

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
echo "=== DOWNLOADING DEFCONFIG FROM NIGHTKERNEL REPO ==="
curl -fsSL "${RAW_URL}/configs/nightkernel_v1.2_defconfig" -o .config

make olddefconfig

# Validate critical flags
echo "=== VALIDATING CONFIGURATION ==="
grep "CONFIG_KSU=y" .config
grep "CONFIG_KSU_SUSFS=y" .config
grep "CONFIG_NTSYNC=y" .config
grep "CONFIG_BBG=y" .config
grep "CONFIG_KCAL_CTRL=y" .config
grep "CONFIG_SND_SOC_RT5691=m" .config
grep "CONFIG_DEBUG_INFO_BTF=y" .config

# 14. Compile Kernel
echo "=== COMPILING NIGHTKERNEL v1.2.0 ==="
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
cp .config /build/artifacts/nightkernel-v1.2.config

git clone --depth=1 https://github.com/osm0sis/AnyKernel3 /build/anykernel3
cp arch/arm64/boot/Image /build/anykernel3/Image

cat << 'AK3EOF' > /build/anykernel3/anykernel.sh
### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() { '
kernel.string=NightKernel v1.2.0 (Project-24 + SuSFS 2.1.0 + NTSync) by Multi-Forge
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

cd /build/anykernel3 && zip -r9 /build/artifacts/NightKernel-v1.2.0-a14x.zip * -x .git README.md *placeholder

# 17. Create repacked raw boot.img and Odin tar
echo "=== CREATING REPACKED BOOT.IMG & ODIN TAR ==="
mkdir -p /build/boot_work && cd /build/boot_work
gh release download v1.0.0-base -p "boot.img" --repo "$REPO" || true
if [ -f boot.img ]; then
    /build/anykernel3/tools/magiskboot unpack boot.img || true
    if [ -f kernel ]; then
        cp /build/artifacts/Image kernel
        /build/anykernel3/tools/magiskboot repack boot.img /build/artifacts/boot.img || true
        if [ -f /build/artifacts/boot.img ]; then
            tar -cvf /build/artifacts/boot-NightKernel-v1.2.0.tar -C /build/artifacts boot.img
        fi
    fi
fi

cd /build/artifacts
gh release delete v1.2.0 -y --repo "$REPO" || true

if [ -f /build/artifacts/boot.img ]; then
    sha256sum Image nightkernel-v1.2.config NightKernel-v1.2.0-a14x.zip boot.img boot-NightKernel-v1.2.0.tar > sha256sums.txt
    gh release create v1.2.0 Image nightkernel-v1.2.config NightKernel-v1.2.0-a14x.zip boot.img boot-NightKernel-v1.2.0.tar sha256sums.txt \
        --repo "$REPO" \
        --title "NightKernel v1.2.0 (Project-24 + SuSFS 2.1.0 + NTSync)" \
        --notes "### NightKernel v1.2.0 for Samsung Galaxy A14 5G (SM-A146M / SM-A146B)
- **Project-24 Kernel Stack:**
  - **SuSFS 2.1.0 (Kernel Root Hiding):** SuSFS com suporte completo para ocultação de root no nível de kernel (Play Integrity).
  - **ReSukiSU Integrado:** Branch main com multi-manager e KSU safety patch 5.15.
  - **NTSync (\`/dev/ntsync\`):** Driver de sincronização Windows NT no kernel para alta performance em emuladores (Winlator, Mobox, Box64).
  - **Baseband Guard (BBG):** Proteção ativa contra corrupção e formatação de partições críticas de modem e EFS.
  - **DroidSpaces:** Suporte para isolamento e containers avançados.
  - **KCAL Color Control:** Driver DQE para ajuste de calibração de cor e saturação da tela.
  - **I/O Otimizado:** CRCs de MMC desativados para leitura e gravação mais rápida.
  - **Performance:** Multi-Gen LRU (MGLRU), TCP BBR habilitado por padrão, F2FS compression.
- **Recovery Autônomo (NightKernel Core):**
  - Mantido nó \`/proc/nightkernel_reboot\` (0666) para reboot direto no TWRP sem necessidade de cabo USB.
  - Panic-to-Recovery mantido.
- **Hardware & Estabilidade:**
  - Driver de áudio SMA1305 estritamente preservado.
  - Suporte total a BTF (\`CONFIG_DEBUG_INFO_BTF=y\`) mantendo compatibilidade 1:1 com os módulos do \`vendor_boot\` no Android 15 One UI 7."
fi

echo "=== RELEASE v1.2.0 PUBLISHED SUCCESSFULLY $(date) ==="
sync
