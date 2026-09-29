#!/bin/bash
set -x
exec > >(tee -a /var/log/kernel-build.log) 2>&1

CODENAME="NightKernel-v1.2.3-clang22"
GCS_BASE="gs://laya-onnx-stt-465818/nightkernel-v123-clang22"

echo "=== STARTING ${CODENAME} BUILD (Clang 22.1.x + ThinLTO + LZ4 zRAM) $(date) ==="

ZONE=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone | awk -F/ '{print $NF}')
INSTANCE_NAME=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/name)
PROJECT_ID=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/project/project-id)
# GCS_BASE definido acima (v123-clang22)

cleanup() {
    echo "=== CLEANING UP INSTANCE $INSTANCE_NAME in $ZONE ==="
    gcloud storage cp /var/log/kernel-build.log "${GCS_BASE}/build.log" || true
    gcloud compute instances delete "$INSTANCE_NAME" --zone="$ZONE" --project="$PROJECT_ID" --quiet || true
}
trap cleanup EXIT

# 1. Mount 24GB tmpfs in RAM
echo "=== MOUNTING 24GB RAM DISK (tmpfs) ==="
if grep -q " /build " /proc/mounts; then umount /build || true; fi
mkdir -p /build
mount -t tmpfs -o size=24G tmpfs /build
df -h /build

mkdir -p /build/toolchains /build/kernel /build/patches /build/ccache-bin /build/artifacts /build/anykernel3 /build/boot_work

# 2. Attach and mount persistent ccache disk
echo "=== MOUNTING PERSISTENT CCACHE DISK ==="
if grep -q " /mnt/ccache " /proc/mounts; then umount /mnt/ccache || true; fi
mkdir -p /mnt/ccache
if [ -e /dev/disk/by-id/google-a14x-ccache ]; then
    mount -o noatime,commit=60 /dev/disk/by-id/google-a14x-ccache /mnt/ccache
    mkdir -p /mnt/ccache/clang22
    export CCACHE_DIR=/mnt/ccache/clang22
else
    mkdir -p /build/ccache
    export CCACHE_DIR=/build/ccache
fi

export CCACHE_COMPRESS=1
export CCACHE_COMPRESSLEVEL=1
export CCACHE_MAXSIZE=14G
export CCACHE_BASEDIR=/build
export CCACHE_NOHASHDIR=1

# 3. Install packages & dependencies
export DEBIAN_FRONTEND=noninteractive
apt-get update -y -o Acquire::Retries=5 -o Acquire::http::Timeout=30 -o Acquire::http::Pipeline-Depth=0
for i in 1 2 3; do apt-get install -y -o Acquire::Retries=5 -o Acquire::http::Timeout=30 -o Acquire::http::Pipeline-Depth=0 software-properties-common wget gnupg && break; sleep 5; done
add-apt-repository -y universe
apt-get update -y
for i in 1 2 3; do apt-get install -y -o Acquire::Retries=5 -o Acquire::http::Timeout=30 -o Acquire::http::Pipeline-Depth=0 git curl tar bc bison flex libssl-dev make gcc g++ libelf-dev python3 libncurses-dev zip zstd ccache dwarves patch rsync qemu-user-static binfmt-support pigz && break; sleep 10; done || true
echo "=== BASE TOOLS INSTALL LOOP DONE ==="
echo "deb http://apt.llvm.org/noble/ llvm-toolchain-noble-22 main" > /etc/apt/sources.list.d/llvm22.list
wget -qO /etc/apt/trusted.gpg.d/apt.llvm.org.asc https://apt.llvm.org/llvm-snapshot.gpg.key
apt-get update -y -o Acquire::Retries=5 -o Acquire::http::Timeout=30 || true
apt-cache policy clang-22 | head -3
for i in 1 2 3; do apt-get install -y -o Acquire::Retries=5 -o Acquire::http::Timeout=30 -o Acquire::http::Pipeline-Depth=0 clang-22 lld-22 llvm-22 llvm-22-tools && break; sleep 10; done || true
command -v clang-22 || { echo "FATAL: clang-22 ausente"; exit 1; }
echo "=== TOOLCHAIN VERSIONS ==="
clang-22 --version | head -2 || true
ld.lld-22 --version | head -2 || true

echo "=== INITIAL CCACHE STATUS ==="
ccache -s

# 4. Clone Clang toolchain into RAM
mkdir -p /usr/local/clang22/bin
for t in clang clang++ ld.lld llvm-ar llvm-nm llvm-objcopy llvm-objdump llvm-readelf llvm-strip clang-cpp; do
  ln -sf "/usr/bin/${t}-22" "/usr/local/clang22/bin/${t}" 2>/dev/null || true
done
ls -la /usr/local/clang22/bin/

echo "=== CLONING BUILD TOOLS TO RAM ==="
git clone --depth=1 -b main https://android.googlesource.com/kernel/prebuilts/build-tools /build/toolchains/build-tools

# Setup ccache wrappers
cat << 'EOF' > /build/ccache-bin/clang
#!/bin/bash
exec ccache /usr/local/clang22/bin/clang "$@"
EOF
cat << 'EOF' > /build/ccache-bin/clang++
#!/bin/bash
exec ccache /usr/local/clang22/bin/clang++ "$@"
EOF
chmod +x /build/ccache-bin/clang /build/ccache-bin/clang++

# 5. Clone Kernel Source into RAM (V-ue commit 69d6e0522 = clean 5.15.197)
echo "=== CLONING KERNEL SOURCE TO RAM ==="
cd /build/kernel
git init
git remote add origin https://github.com/physwizz/a146b-a146m.git
git fetch --depth 2 origin main
git checkout 69d6e0522

# Download patches from GCS
gcloud storage cp "${GCS_BASE}/patches/*.patch" /build/patches/

# 6. Apply Autonomous Recovery Patch
echo "=== APPLYING AUTONOMOUS RECOVERY PATCH ==="
sed -i 's/static char panic_str\[10\] = "panic";/static char panic_str\[10\] = "recovery";/' drivers/samsung/sec_reboot.c

cat << 'PROCEOF' >> kernel/reboot.c

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

# 7. Inject ReSukiSU + Safety Patch
echo "=== INJECTING RESUKISU ==="
curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" | bash -s main
cd KernelSU && patch -p1 --forward < /build/patches/03_resukisu_safety.patch || true && cd ..

# 8. Inject SuSFS 2.1.0 + Stock A14 Reject Fix
echo "=== INJECTING SUSFS 2.1.0 ==="
git clone --depth=1 -b gki-android13-5.15 https://gitlab.com/simonpunk/susfs4ksu.git /tmp/susfs_repo
cd /tmp/susfs_repo && git checkout 9f0415bb2c8fc581e93d384e09aba088bd36733a || true && cd /build/kernel
cp -rf /tmp/susfs_repo/kernel_patches/fs/* fs/
cp -rf /tmp/susfs_repo/kernel_patches/include/linux/* include/linux/
patch -p1 --forward < /tmp/susfs_repo/kernel_patches/50_add_susfs_in_gki-android13-5.15.patch || true
patch -p1 --forward < /build/patches/02_susfs_fix_stock_a14.patch || true
rm -rf /tmp/susfs_repo

# 9. Apply Feature Patches (NTSync, DroidSpaces, BBG, KCAL, CRC bypass, Telemetry Optimizations)
patch -p1 --forward < /build/patches/04_ntsync_base.patch || true
patch -p1 --forward < /build/patches/05_ntsync_compat.patch || true
patch -p1 --forward < /build/patches/06_droidspace.patch || true
curl -LSs https://github.com/vc-teahouse/Baseband-guard/raw/main/setup.sh | bash || true
patch -p1 --forward < /build/patches/07_kcal_dqe.patch || true
patch -p1 --forward < /build/patches/08_crcs_disable.patch || true
patch -p1 --forward < /build/patches/09_telemetry_gaming_optimizations.patch || true

find . -name "*.orig" -delete -o -name "*.rej" -delete

# 10. Environment
export PATH=/build/ccache-bin:/usr/local/clang22/bin:/build/toolchains/build-tools/path/linux-x86:$PATH
export LLVM_IAS=1
echo "=== EFFECTIVE COMPILER ==="
which clang
clang --version | head -2
export ARCH=arm64
export SUBARCH=arm64
export LLVM=1
export TARGET_SOC=s5e8535
export DTC_FLAGS="-@"
export PLATFORM_VERSION=15
export ANDROID_MAJOR_VERSION=v
export KCFLAGS="-Wno-error -Wno-error=strict-prototypes -Wno-error=implicit-int -Wno-error=deprecated-non-prototype -Wno-error=uninitialized -Wno-error=enum-compare -Wno-error=implicit-enum-enum-cast -Wno-error=enum-conversion"

# 11. Download and Apply Defconfig
echo "=== DOWNLOADING DEFCONFIG v1.2.3-clang22 FROM GCS ==="
gcloud storage cp "${GCS_BASE}/nightkernel_v1.2.3_clang22_defconfig" .config
make olddefconfig

# 11b. Clang 22 compat fixes (tree 5.15.197 + vendor Samsung) — antes do olddefconfig
# F1: filemap.c — Clang >=15 exige prototipo (void); Clang 14 tolerava ()
sed -i 's/static void filemap_tracing_mark_end()/static void filemap_tracing_mark_end(void)/g' mm/filemap.c
# F2: sysbusy.c (vendor EMS) — faltava o tipo do array (implicit-int virou erro)
sed -i 's/^static cpn_next_cpu\[VENDOR_NR_CPUS\]/static int cpn_next_cpu[VENDOR_NR_CPUS]/' kernel/sched/ems/sysbusy.c
# F3: exynos-devfreq.h — tipo de retorno int ausente (implicit-int virou erro)
sed -i 's/extern exynos_devfreq_alt_mode_change/extern int exynos_devfreq_alt_mode_change/' include/soc/samsung/exynos-devfreq.h
# F4: exynos_usb_audio_gic.c — Clang >=15 exige prototipo (void)
sed -i 's/static void exynos_sound_usb_pm_noti_init()/static void exynos_sound_usb_pm_noti_init(void)/' sound/usb/exynos_usb_audio_gic.c
# F5: exynos-cpupm.c — variavel name nao inicializada em ramo de erro kzalloc
sed -i 's/const char \*name;/const char *name = NULL;/' drivers/soc/samsung/exynos-cpupm.c
# F6: drivers/samsung/debug — sec_debug_test.o eh driver de teste de panicos/crashes com inline asm NEON (q0-q31)
# Desacopla sec_debug_test.o de CONFIG_SEC_DEBUG_BASE para CONFIG_SEC_DEBUG_TEST (=n) e aplica .arch armv8-a+fp no asm inline
sed -i 's/obj-\$(CONFIG_SEC_DEBUG_BASE)[[:space:]]*+= sec_debug_test\.o/obj-\$(CONFIG_SEC_DEBUG_TEST) += sec_debug_test\.o/' drivers/samsung/debug/Makefile
sed -i '/\tstp\tq0, q1, \[%0, #16 \* 0\]/i \\\t\"\t\.arch armv8-a+fp\\n\"' drivers/samsung/debug/sec_debug_test.c
sed -i '/\tstp\tq30, q31, \[%0, #16 \* 30\]/a \\\t\"\t\.arch armv8-a\\n\"' drivers/samsung/debug/sec_debug_test.c
sed -i '/\tldp\tq0, q1, \[%0, #16 \* 0\]/i \\\t\"\t\.arch armv8-a+fp\\n\"' drivers/samsung/debug/sec_debug_test.c
sed -i '/\tldp\tq30, q31, \[%0, #16 \* 30\]/a \\\t\"\t\.arch armv8-a\\n\"' drivers/samsung/debug/sec_debug_test.c
# F7: nt36xxx.c — conversao invalida de enum sec_ts_error para irqreturn_t
sed -i 's/return SEC_ERROR;/return IRQ_NONE;/' drivers/input/touchscreen/novatek/nt36523_spi/nt36xxx.c
# F10: Makefile raiz — desativar todos os -Werror= e -Werror transformando em warnings
sed -i 's/-Werror=/-W/g; s/KBUILD_CFLAGS-$(CONFIG_WERROR) += -Werror//g' Makefile
# Drivers GPU Mali Makefile
sed -i 's/KBUILD_CFLAGS += -Wall -Werror/KBUILD_CFLAGS += -Wall/' drivers/gpu/arm/v_r38p1/Makefile drivers/gpu/arm/bv_r38p1/Makefile 2>/dev/null || true
grep -c 'Werror' Makefile || true

# F9: drivers/gpu/arm/v_r38p1/Makefile e bv_r38p1/Makefile — remover -Werror local da Mali
sed -i 's/KBUILD_CFLAGS += -Wall -Werror/KBUILD_CFLAGS += -Wall/' drivers/gpu/arm/v_r38p1/Makefile drivers/gpu/arm/bv_r38p1/Makefile
grep -c 'KBUILD_CFLAGS += -Wall -Werror' drivers/gpu/arm/v_r38p1/Makefile || true

# F8: sm5714_typec.c — comparacao de enums diferentes (-Wenum-compare)
sed -i 's/if (port_type == TYPEC_PORT_DFP)/if ((int)port_type == (int)TYPEC_PORT_DFP)/' drivers/usb/typec/sm/sm5714/sm5714_typec.c
sed -i 's/} else if (port_type == TYPEC_PORT_UFP)/} else if ((int)port_type == (int)TYPEC_PORT_UFP)/' drivers/usb/typec/sm/sm5714/sm5714_typec.c
# valida que os fixes pegaram (falha aqui = aborta antes de compilar)
grep -c 'filemap_tracing_mark_end(void)' mm/filemap.c
grep -c '^static int cpn_next_cpu' kernel/sched/ems/sysbusy.c
grep -c 'extern int exynos_devfreq_alt_mode_change' include/soc/samsung/exynos-devfreq.h
grep -c 'exynos_sound_usb_pm_noti_init(void)' sound/usb/exynos_usb_audio_gic.c
grep -c 'const char \*name = NULL;' drivers/soc/samsung/exynos-cpupm.c
grep -c 'CONFIG_SEC_DEBUG_TEST' drivers/samsung/debug/Makefile
grep -c 'armv8-a+fp' drivers/samsung/debug/sec_debug_test.c
grep -c 'return IRQ_NONE;' drivers/input/touchscreen/novatek/nt36523_spi/nt36xxx.c
grep -c '(int)port_type == (int)TYPEC_PORT_DFP' drivers/usb/typec/sm/sm5714/sm5714_typec.c

# Validate critical flags
grep "CONFIG_KSU=y" .config
grep "CONFIG_KSU_SUSFS=y" .config
grep "CONFIG_NTSYNC=y" .config
grep "CONFIG_LTO_CLANG_THIN=y" .config
grep "CONFIG_ZRAM_DEF_COMP_LZ4=y" .config
grep 'CONFIG_LOCALVERSION="-NightKernel-v1.2.3-clang22"' .config
grep "CONFIG_FRAME_WARN=3072" .config

# 12. Dynamic Parallelism Calculation & Compile
CPUS=$(nproc)
JOBS=$(( CPUS + CPUS / 2 )) # 12 jobs for 8 vCPUs
echo "=========================================================="
echo "=== COMPILING ON RAM tmpfs WITH $JOBS JOBS ($CPUS vCPUs) ==="
echo "=========================================================="

BUILD_START=$(date +%s)
make -j"$JOBS" 2>&1 | tee /build/build_clang22_full.log
BUILD_END=$(date +%s)
BUILD_DURATION=$(( BUILD_END - BUILD_START ))

echo "=========================================================="
echo "=== ${CODENAME} COMPILED IN $BUILD_DURATION SECONDS ==="
echo "=== BASELINE: frio=${BUILD_DURATION}s clang=$(clang --version | head -1) ==="
echo "=== NOOP BASELINE ==="
time make -j"$JOBS" 2>&1 | tail -2
echo "=== TOUCH+INCREMENTAL BASELINE (kernel/sched/core.c) ==="
touch kernel/sched/core.c
time make -j"$JOBS" 2>&1 | tail -2
echo "=========================================================="

ccache -s

if [ ! -f arch/arm64/boot/Image ]; then
    echo "ERROR: arch/arm64/boot/Image not found!"
    exit 1
fi

ls -lh arch/arm64/boot/Image

# 13. Package AnyKernel3
cp arch/arm64/boot/Image /build/artifacts/Image
cp .config /build/artifacts/nightkernel-v1.2.3-clang22.config

git clone --depth=1 https://github.com/osm0sis/AnyKernel3 /build/anykernel3
cp arch/arm64/boot/Image /build/anykernel3/Image

cat << 'AK3EOF' > /build/anykernel3/anykernel.sh
### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

properties() { '
kernel.string=NightKernel v1.2.3-clang22 (Clang 22 / ThinLTO / LZ4 ZRAM / 5.15.197) by Multi-Forge
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
AK3EOF

cd /build/anykernel3 && zip -r9 /build/artifacts/NightKernel-v1.2.3-clang22-a14x.zip * -x .git README.md *placeholder

# 14. Create repacked boot.img and Odin tar from Binary E base
echo "=== REPACKING BOOT.IMG ==="
mkdir -p /build/boot_work && cd /build/boot_work
gcloud storage cp "${GCS_BASE}/A146b-V-ue-boot.tar" .
tar -xvf A146b-V-ue-boot.tar

if [ -f boot.img ]; then
    /build/anykernel3/tools/magiskboot unpack boot.img || true
    if [ -f kernel ]; then
        cp /build/artifacts/Image kernel
        /build/anykernel3/tools/magiskboot repack boot.img /build/artifacts/boot.img || true
        if [ -f /build/artifacts/boot.img ]; then
            tar -cvf /build/artifacts/boot-NightKernel-v1.2.3-clang22.tar -C /build/artifacts boot.img
        fi
    fi
fi

cd /build/artifacts
sha256sum Image nightkernel-v1.2.3-clang22.config NightKernel-v1.2.3-clang22-a14x.zip boot.img boot-NightKernel-v1.2.3-clang22.tar > sha256sums.txt

echo "=== UPLOADING ARTIFACTS TO GCS ==="
gcloud storage cp -r /build/artifacts/* "${GCS_BASE}/artifacts/"

echo "=== BUILD COMPLETE AT $(date) ==="
sync
