# NightKernel para Samsung Galaxy A14 5G

[Português](README_PT.md) | [English](README.md)

<p align="center">
  <img src="assets/banner.jpg" alt="NightKernel Banner" width="100%">
</p>

Custom kernel Linux para o **Samsung Galaxy A14 5G** (`SM-A146M` / `SM-A146B`, codinome `a14x` / `s5e8535`), rodando **Android 15 (Samsung One UI 7 - PDA `A146MUBSDDZE1`, Binário D)**. Construído a partir da base `physwizz/a146b-a146m` (`V-sd-perm`) com o **Linux 5.15.180** upstream.

> [!WARNING]
> **Compatibilidade:** Suporte exclusivo para `SM-A146M` e `SM-A146B` (Samsung Exynos 1330).  
> **NÃO INSTALE nas variantes dos EUA (`SM-A146U`, `SM-A146U1`, `SM-S146VL`)** — esses modelos usam SoC MediaTek Dimensity 700 e sofrerão brick imediato.

> [!CAUTION]
> ```text
> * Sua garantia agora está anulada.
> * Eu não me responsabilizo por dispositivos brickados, cartões SD mortos,
> * ou por você perder o despertador de manhã. Pesquise antes de instalar.
> * Você escolheu fazer essas modificações e assume total responsabilidade.
> ```

---

## Recursos e Modificações

### Autonomous Recovery (`/proc/nightkernel_reboot`)
No bootloader stock da Samsung (`sboot`) do Exynos 1330, existe uma trava que exige cabo USB conectado ao PC ou carregador para reconhecer os botões físicos (`Power + Vol Up`) no boot a frio. Sem USB, o celular ignora os botões e inicia o Android normalmente.
- **Solução no kernel:** Em `drivers/samsung/sec_reboot.c`, o comando `recovery` grava diretamente o código `SEC_RESET_REASON_RECOVERY` nos registradores de retenção da PMU da Samsung (`panic_inform` / `regmap_write`).
- **Interface procfs:** Nó com permissão de escrita universal (`0666`) em `/proc/nightkernel_reboot`. Execute como root:
  ```bash
  echo 1 > /proc/nightkernel_reboot
  ```
  para reiniciar imediatamente no TWRP sem precisar de cabo ou computador.
- **Atalho no reboot:** Segurar `Power + Vol Up` durante o reinício do sistema também entra direto no TWRP.
- **Panic-to-Recovery:** O manipulador de pânico do kernel redireciona falhas críticas para `"recovery"`, fazendo o aparelho reiniciar em segurança no TWRP em vez de travar na tela preta ou modo de upload.

### Root e Evasão de Detecção (ReSukiSU 3.0.0 + SuSFS 2.1.0)
- **ReSukiSU 3.0.0:** Integrado diretamente na árvore de código com patches de proteção de supercall em `dispatch.c`.
- **SuSFS 2.1.0:** Isolamento em nível de VFS que oculta montagens de root (`sus_mount`), mapas de memória (`sus_map`) e atributos de arquivo (`sus_kstat_redirect`). Passa no Google Play Integrity (`MEETS_DEVICE_INTEGRITY`) e em aplicativos bancários.
- **Uname spoofing:** Permite alterar a string pública da versão do kernel em tempo de execução (`sus_set_uname`).

### Sincronização Windows NT (NTSync)
- **Driver `/dev/ntsync`:** Implementa primitivas de sincronização do Windows NT (mutexes, semáforos, eventos) diretamente no kernel Linux (`drivers/misc/ntsync.c`).
- **Impacto em emuladores:** Reduz drasticamente o overhead do `wineserver` em camadas de compatibilidade Windows (**Winlator**, **Mobox**, **Termux-Box**, **Wine-GE**), melhorando o ritmo de quadros e latência em jogos multithread DirectX 9/11/12 e Vulkan.
- **Compatibilidade:** Inclui handlers de ioctl para 32-bit (`CONFIG_NTSYNC_COMPAT=y`) e permissões `0666` nativas.

### Calibração de Tela (KCAL Color Control)
- Driver KCAL integrado na pipeline DQE da Samsung (`drivers/gpu/drm/samsung/dqe/`).
- Permite controle fino de RGB, saturação, contraste e matiz através de aplicativos KCAL convencionais.

### Armazenamento e I/O
- Checagens de software CRC desativadas em MMC/SD (`use_spi_crc = 0` em `drivers/mmc/core/core.c`), reduzindo o consumo de CPU e acelerando leitura/escrita no armazenamento e microSD.
- Bypass de verificação de versão de módulos em `kernel/module.c` para carregar LKMs externos sem erro de incompatibilidade de vermagic.

### Containers e Virtualização Linux
- `CONFIG_SYSVIPC=y` habilitado via padding KABI do Android sem quebrar o ABI do vendor.
- Suporte a DroidSpaces (`binfmt_misc`, `OverlayFS`, `FUSE`, `Btrfs`) para execução de chroots, LXC e Docker no Termux.

### Segurança de Hardware (Baseband Guard)
- Módulo LSM Baseband Guard (BBG) em `security/bbg/`.
- Bloqueia gravações não autorizadas, formatação ou corrupção de partições de modem e da pasta `/efs`, protegendo IMEI e dados de calibração RF.

### Sistema e Memória
- **MGLRU (Multi-Gen LRU):** Ativado por padrão (`CONFIG_LRU_GEN=y`, `0x0003`) para gerenciamento e descarte eficiente de páginas de memória.
- **TCP BBR v1 + FQ:** Algoritmo de congestionamento de rede padrão configurado para BBR com escalonador Fair Queuing.
- **Áudio Realtek RT5691:** Driver do codec de hardware real ativado (`CONFIG_SND_SOC_RT5691=m`).
- **Restrições Samsung neutralizadas:** KNOX, DEFEX, RKP, KDP, PROCA, FIVE e UH desativados.
- **Símbolos BTF:** Compilado com `CONFIG_DEBUG_INFO_BTF=y` e `pahole 1.24` para suporte completo a diagnósticos e ferramentas eBPF.

---

## Métodos de Instalação

### 1. TWRP Recovery (Recomendado)
1. Baixe o arquivo `NightKernel-v1.2.0-a14x.zip` na aba [Releases](https://github.com/multi-forge/NightKernel-a14x/releases/tag/v1.2.0).
2. Entre no TWRP.
3. *Nota:* Como a partição `/data` é criptografada no Android 15, coloque o zip em um **cartão MicroSD**, **pendrive USB OTG** ou na pasta `/cache/` (partição ext4 não criptografada).
4. Instale o zip e reinicie o sistema.

### 2. Odin / Download Mode
1. Baixe `boot-NightKernel-v1.2.0.tar` nas [Releases](https://github.com/multi-forge/NightKernel-a14x/releases/tag/v1.2.0).
2. Coloque o aparelho em Download Mode (`Vol+ + Vol-` com cabo USB no PC).
3. Insira o arquivo `boot-NightKernel-v1.2.0.tar` no slot **AP** do Odin.
4. Flasheie e reinicie.

### 3. Terminal com Root
```bash
dd if=boot.img of=/dev/block/by-name/boot bs=4096 && sync && reboot
```

---

## Compilação a Partir da Fonte

### Pré-requisitos
- Ambiente Linux (Ubuntu 22.04 ou 24.04 LTS)
- AOSP Clang 18 (r522817) ou superior
- Toolchain AArch64 GCC / binutils LLVM

### Comandos de Build
```bash
export ARCH=arm64
export SUBARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
export CLANG_TRIPLE=aarch64-linux-gnu-
export PATH=/caminho/para/clang-r522817/bin:$PATH

make CC=clang LLVM=1 nightkernel_v1.2_defconfig
make -j$(nproc) CC=clang LLVM=1 Image
```
A imagem gerada estará em `arch/arm64/boot/Image`.

---

## Estrutura do Repositório
- [`tree/`](tree/): Árvore completa do código-fonte com todos os patches aplicados.
- [`tree-recovery/`](tree-recovery/): Device tree funcional do TWRP para o Galaxy A14 5G.
- [`configs/`](configs/): Defconfig de produção (`nightkernel_v1.2_defconfig`).
- [`patches/`](patches/): Arquivos de patch individuais para cada modificação.

## Links Úteis
- **Releases:** [Releases do NightKernel](https://github.com/multi-forge/NightKernel-a14x/releases)
- **TWRP Recovery:** [android_device_samsung_a14x](https://github.com/multi-forge/android_device_samsung_a14x)
- **Árvore Base:** [physwizz/a146b-a146m](https://github.com/physwizz/a146b-a146m) (`V-sd-perm`)
