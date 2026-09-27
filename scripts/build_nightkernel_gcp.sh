#!/usr/bin/env bash
# ==============================================================================
# NightKernel Build Script for Samsung Galaxy A14 5G (Exynos 1330 / a14x)
# Target OS: Android 15 (One UI 7 - A146MUBSDDZE1)
# ==============================================================================
set -euo pipefail

export ARCH=arm64
export SUBARCH=arm64
export KBUILD_BUILD_USER="MultiForge"
export KBUILD_BUILD_HOST="nightkernel-builder"

WORK_DIR="/build"
KERNEL_DIR="${WORK_DIR}/kernel"
CLANG_DIR="${WORK_DIR}/toolchains/clang-r450784d"
OUT_DIR="${WORK_DIR}/out"
ARTIFACTS_DIR="${WORK_DIR}/artifacts"
CCACHE_DIR="/mnt/ccache"

mkdir -p "${WORK_DIR}" "${OUT_DIR}" "${ARTIFACTS_DIR}" "${WORK_DIR}/toolchains"

# 1. Dependências do sistema (Debian/Ubuntu)
if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -y
    sudo apt-get install -y --no-install-recommends \
        build-essential bc bison flex libssl-dev libelf-dev ccache zip unzip \
        git curl wget python3 pahole dwarves qemu-user-static
fi

# 2. Toolchain Clang 14.0.6 (r450784d - Match 1:1 Samsung One UI 7)
if [ ! -d "${CLANG_DIR}" ]; then
    echo "[-] Baixando Clang clang-r450784d..."
    mkdir -p "${CLANG_DIR}"
    CLANG_URL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main/clang-r450784d.tar.gz"
    curl -sSL "${CLANG_URL}" | tar -xz -C "${CLANG_DIR}"
fi

export PATH="${CLANG_DIR}/bin:${PATH}"
export CLANG_TRIPLE="aarch64-linux-gnu-"
export CROSS_COMPILE="aarch64-linux-gnu-"
export LLVM=1
export LLVM_IAS=1

# 3. Configurar ccache se disponível
if [ -d "${CCACHE_DIR}" ]; then
    export CCACHE_DIR="${CCACHE_DIR}"
    export CC="ccache clang"
    ccache -M 15G
fi

# 4. Clone da Árvore Base (branch V-sd-perm)
if [ ! -d "${KERNEL_DIR}" ]; then
    echo "[-] Clonando árvore do kernel..."
    git clone --depth 1 -b V-sd-perm https://github.com/physwizz/a146b-a146m "${KERNEL_DIR}"
fi

cd "${KERNEL_DIR}"

# 5. Injetar defconfig do NightKernel
echo "[-] Aplicando defconfig do NightKernel..."
if [ -f "${WORK_DIR}/nightkernel_a14x_defconfig" ]; then
    cp "${WORK_DIR}/nightkernel_a14x_defconfig" "${OUT_DIR}/.config"
else
    make O="${OUT_DIR}" defconfig
fi

# 6. Compilação
echo "[-] Compilando NightKernel com BTF habilitado..."
make -j"$(nproc)" O="${OUT_DIR}" \
    CC="${CC:-clang}" \
    LLVM=1 \
    LLVM_IAS=1 \
    Image modules

echo "[+] Compilação concluída com sucesso!"
cp "${OUT_DIR}/arch/arm64/boot/Image" "${ARTIFACTS_DIR}/Image"
