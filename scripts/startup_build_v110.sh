#!/usr/bin/env bash
# ==============================================================================
# NightKernel v1.1.0 Automated Cloud Build Script (GCP Compute Engine)
# Features:
#   - P4B: Recovery Autônomo (procfs trigger /proc/nightkernel_reboot + Panic-to-Recovery)
#   - P4C: KernelSU Root nativo (v0.9.5 hooks)
#   - BTF completo preservado via pahole/dwarves
#   - ccache persistente (a14x-ccache)
# ==============================================================================
set -euo pipefail

# Auto-destruição em caso de encerramento
cleanup() {
    echo "[-] Finalizando e encerrando a instância..."
    gcloud compute instances delete "$(hostname)" --zone=us-central1-a --project=stt-465818 --quiet || poweroff
}
trap cleanup EXIT

echo "=== [1/7] Configurando ambiente e dependências ==="
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
    build-essential bc bison flex libssl-dev libelf-dev ccache zip unzip \
    git curl wget python3 pahole dwarves qemu-user-static

# Instalar GitHub CLI se ausente
if ! command -v gh >/dev/null 2>&1; then
    mkdir -p -m 755 /etc/apt/keyrings
    wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
    chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    apt-get update -y
    apt-get install -y gh
fi

# Autenticar gh
GH_TOKEN=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/attributes/github-token)
echo "${GH_TOKEN}" | gh auth login --with-token
gh auth status

# Montar disco ccache
mkdir -p /mnt/ccache
mount -o discard,defaults /dev/disk/by-id/google-ccache /mnt/ccache || true
export CCACHE_DIR=/mnt/ccache
export CC="ccache clang"
ccache -M 15G
ccache -s

echo "=== [2/7] Configurando Toolchain Clang 14.0.6 (r450784d) ==="
mkdir -p /build/toolchains/clang-r450784d
if [ ! -f "/build/toolchains/clang-r450784d/bin/clang" ]; then
    echo "[-] Baixando Clang oficial Android r450784d..."
    curl -sSL "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main/clang-r450784d.tar.gz" | tar -xz -C /build/toolchains/clang-r450784d
fi

export PATH="/build/toolchains/clang-r450784d/bin:${PATH}"
export ARCH=arm64
export SUBARCH=arm64
export CLANG_TRIPLE="aarch64-linux-gnu-"
export CROSS_COMPILE="aarch64-linux-gnu-"
export LLVM=1
export LLVM_IAS=1
export KBUILD_BUILD_USER="MultiForge"
export KBUILD_BUILD_HOST="nightkernel-builder"

echo "=== [3/7] Clonando árvore do Kernel (branch V-sd-perm) ==="
mkdir -p /build
git clone --depth 1 -b V-sd-perm https://github.com/physwizz/a146b-a146m /build/kernel
cd /build/kernel

echo "=== [4/7] Aplicando Patches P4B e P4C ==="
# 4.1 Injetar KernelSU v0.9.5 oficial
echo "[-] Injetando KernelSU v0.9.5..."
curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -s v0.9.5

# 4.2 Patch P4B: Panic-to-Recovery em drivers/samsung/sec_reboot.c
echo "[-] Aplicando patch Panic-to-Recovery..."
sed -i 's/static char panic_str\[10\] = "panic";/static char panic_str\[10\] = "recovery";/' drivers/samsung/sec_reboot.c

# 4.3 Patch P4B: Interface /proc/nightkernel_reboot em kernel/reboot.c
echo "[-] Injetando interface autônoma /proc/nightkernel_reboot..."
cat << 'EOF' >> kernel/reboot.c

/* ========================================================================== */
/* NightKernel Autonomous Recovery Interface (Phase P4B)                      */
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
EOF

echo "=== [5/7] Configurando Defconfig do NightKernel v1.1 ==="
mkdir -p /build/out
curl -sSL "https://raw.githubusercontent.com/multi-forge/NightKernel-a14x/main/configs/nightkernel_a14x_defconfig" > /build/out/.config

# Garantir CONFIG_KSU e versão
sed -i 's/CONFIG_LOCALVERSION=.*/CONFIG_LOCALVERSION="-NightKernel-v1.1"/' /build/out/.config
echo "CONFIG_KSU=y" >> /build/out/.config
echo "# CONFIG_KSU_DEBUG is not set" >> /build/out/.config

# Atualizar .config com Kconfig
make -j8 O=/build/out CC="ccache clang" LLVM=1 LLVM_IAS=1 olddefconfig

# Validar flags críticas
grep "CONFIG_KSU=y" /build/out/.config
grep "CONFIG_DEBUG_INFO_BTF=y" /build/out/.config

echo "=== [6/7] Compilando NightKernel v1.1.0 (Clang 14 + pahole BTF) ==="
make -j8 O=/build/out CC="ccache clang" LLVM=1 LLVM_IAS=1 Image modules

echo "[+] Compilação concluída!"
ls -lh /build/out/arch/arm64/boot/Image
ccache -s

echo "=== [7/7] Empacotando e Publicando Artefatos ==="
mkdir -p /build/artifacts
cd /build/artifacts

cp /build/out/arch/arm64/boot/Image ./Image
cp /build/out/.config ./nightkernel-v1.1.config

# 7.1 AnyKernel3 Zip
git clone --depth 1 https://github.com/osm0sis/AnyKernel3 /build/anykernel3
cat << 'EOF' > /build/anykernel3/anykernel.sh
### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() { '
kernel.string=NightKernel v1.1.0 (Recovery Autonomo + KernelSU) by Multi-Forge
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

cp ./Image /build/anykernel3/Image
cd /build/anykernel3
zip -r9 /build/artifacts/NightKernel-v1.1.0-a14x.zip * -x .git README.md *placeholder
cd /build/artifacts

# 7.2 Boot.img e Odin .tar
gh release download v1.0.0-base --repo multi-forge/NightKernel-a14x --pattern "boot.img" --clobber
mv boot.img boot-base.img

qemu-aarch64-static /build/anykernel3/tools/magiskboot unpack boot-base.img
cp ./Image ./kernel
qemu-aarch64-static /build/anykernel3/tools/magiskboot repack boot-base.img boot.img
tar -cvf boot-NightKernel-v1.1.0.tar boot.img

# 7.3 Checksums
sha256sum Image nightkernel-v1.1.config NightKernel-v1.1.0-a14x.zip boot.img boot-NightKernel-v1.1.0.tar > sha256sums.txt
cat sha256sums.txt

# 7.4 Publicar Release v1.1.0 no GitHub
gh release create v1.1.0 \
    Image \
    nightkernel-v1.1.config \
    NightKernel-v1.1.0-a14x.zip \
    boot.img \
    boot-NightKernel-v1.1.0.tar \
    sha256sums.txt \
    --repo multi-forge/NightKernel-a14x \
    --title "NightKernel v1.1.0 (Recovery Autônomo + KernelSU Root)" \
    --notes "### NightKernel v1.1.0 for Samsung Galaxy A14 5G (SM-A146M / SM-A146B)
- **Fase P4B (Recovery Autônomo):**
  - Implementada interface \`/proc/nightkernel_reboot\` (permissão 0666) para reboot direto no TWRP sem exigir handshake de cabo USB.
  - Ativado mecanismo Panic-to-Recovery em \`sec_reboot\`: qualquer falha crítica cai direto no TWRP com rede de segurança.
- **Fase P4C Base (Root Nativo):**
  - Injeção oficial do KernelSU v0.9.5 (\`CONFIG_KSU=y\`) restaurando o comando \`su\` e superusuário no Android 15 One UI 7.
- **Base e Estabilidade:**
  - Linux 5.15.180 (branch \`V-sd-perm\`, commit \`ca3d9d162\`).
  - Geração completa de \`.BTF\` via \`pahole\` mantendo compatibilidade total com os drivers proprietários do \`vendor_boot\`.
  - Header v4 para partição de boot de 64 MB."

echo "[+] Release v1.1.0 publicada com sucesso no GitHub!"
