# /init — NightKernel Project Master Context & System Directive

> **Source of Truth:** Este arquivo é o inicializador mestre (`/init`) do **NightKernel**.
> Ao iniciar qualquer nova sessão no Antigravity CLI ou outro assistente, este arquivo fornece o contexto completo, as diretrizes de engenharia, regras de publicação e a arquitetura do projeto.

---

## 1. Identidade e Escopo do Projeto

* **Projeto:** **NightKernel** (desenvolvido por Multi-Forge).
* **Dispositivo Alvo:** Samsung Galaxy A14 5G:
  * `SM-A146M` / `SM-A146M/DS` (América Latina / Brasil — dispositivo de validação física).
  * `SM-A146B` / `SM-A146B/DS` (Global / Europa / Índia / Ásia — 100% compatível).
* **SoC:** Samsung Exynos 1330 (`s5e8535` / arquitetura `a14x`).
* **Sistema Operacional:** Android 15 (Samsung One UI 7).
* **Compatibilidade de Bootloader:** Dual Firmware (Binário D `A146MUBSDDZE1` e Binário E).
* **Base do Kernel:** Linux `5.15.197` LTS (sincronizado com a árvore `physwizz V-ue`, commit `69d6e0522`).
* **⚠️ Restrição Crítica:** NUNCA compilar ou instalar em variantes dos EUA (`SM-A146U`, `SM-A146U1`, `SM-S146VL`), que utilizam MediaTek Dimensity 700 e sofrerão hard-brick.

---

## 2. Stack Tecnológica e Recursos do Kernel

### A. Root Stealth & VFS Isolation
* **ReSukiSU 3.0.0:** Integrado diretamente na árvore do kernel com isolamento de chamadas supercall (`dispatch.c`).
* **SuSFS 2.1.0:** Mascaramento e isolamento em nível de VFS (`sus_mount`, `sus_kstat_redirect`, `sus_map`, `sus_set_uname`).
* **Regra de Documentação do SuSFS:** O SuSFS auxilia no ocultamento de caminhos e montagens de root contra detecções de aplicativos bancários, mas **NÃO garante a aprovação de Play Integrity por si só** (a integridade do dispositivo depende da ROM e do keystore do usuário).

### B. Recuperação e Failsafe (Panic-to-Recovery)
* **Kernel Panic Handler:** Em `drivers/samsung/sec_reboot.c`, o manipulador de pânico grava `SEC_RESET_REASON_RECOVERY` nos registradores de retenção da PMU. Se ocorrer um kernel panic, o aparelho reinicia direto no TWRP recovery em vez de travar em modo de upload ou entrar em bootloop severo.
* **Hardware Key Handling:** Pressionar `Power + Volume Up` durante o reinício direciona para o TWRP sem exigir conexão via cabo USB a um computador.
* **Nota de Release:** Não documentar nós internos como `/proc/nightkernel_reboot` em changelogs públicos; documentar apenas como **Panic-to-Recovery Failsafe**.

### C. Desempenho, I/O e Emulação
* **NTSync Nativo:** Driver `/dev/ntsync` (`drivers/misc/ntsync.c`) com ioctl de compatibilidade 32-bit (`CONFIG_NTSYNC_COMPAT=y`) para emuladores Windows (Winlator, Mobox, Box64).
* **MMC CRC Bypass:** Checagens de software CRC desativadas (`use_spi_crc = 0`) para menor consumo de CPU e ganhos de velocidade em I/O de armazenamento.
* **Gerenciamento de Memória & Rede:** MGLRU ativo por padrão (`0x0003`) e algoritmo TCP BBR v1 + FQ.
* **Containers & DroidSpaces:** `CONFIG_SYSVIPC=y` habilitado via padding KABI do Android, permitindo execução de Chroot, Proot, DroidSpaces e containers Linux no Termux.
* **Segurança:** Módulo LSM Baseband Guard (BBG) protegendo as partições `/efs` e de rádio contra gravações indevidas.

---

## 3. Pipeline de Compilação & Infraestrutura GCP

### Ferramental de Compilação
* **Compilador:** Clang AOSP `r450784d` + ferramentas de build do kernel Android (`prebuilts/build-tools`).
* **Configuração Oficial:** ThinLTO ativo (`CONFIG_LTO_CLANG_THIN=y`) e símbolos DWARF4 (`CONFIG_DEBUG_INFO_DWARF4=y`).
* **Advertência de Stack Frame:** Em compilações de debug sem LTO, ajustar `CONFIG_FRAME_WARN=3072` para evitar erro de limite de 2048 bytes em `drivers/samsung/debug/sec_debug_extra_info.c`.

### Infraestrutura de Nuvem Efêmera (Custo Zero Recorrente)
* **Tipo de Instância:** GCP Compute Engine Spot VM `n2-standard-8` (8 vCPUs, 32 GB RAM, zona `us-central1-a`).
* **Compilação em RAM (tmpfs):** Montar 24 GB `tmpfs` em `/build` (`mount -t tmpfs -o size=24G tmpfs /build`). Árvore de fontes, toolchains e artefatos de saída rodam inteiramente em memória.
* **Cache Persistente:** Disco `a14x-ccache` (15 GB `pd-balanced`, atualmente com ~8.3 GB de cache) montado com `-o noatime,commit=60`.
* **Variáveis de Cache:** Sempre exportar:
  ```bash
  export CCACHE_DIR=/mnt/ccache
  export CCACHE_BASEDIR=/build
  export CCACHE_NOHASHDIR=1
  export CCACHE_COMPRESS=1
  export CCACHE_COMPRESSLEVEL=1
  ```
* **Paralelismo Dinâmico:** `-j12` (fórmula: `nproc + nproc / 2`).
* **Autodestruição e Limpeza:** Todo script de startup DEVE conter `trap cleanup EXIT` para deletar a instância Spot imediatamente após a finalização:
  ```bash
  cleanup() {
      gcloud compute instances delete "$INSTANCE_NAME" --zone="$ZONE" --project="$PROJECT_ID" --quiet || true
  }
  trap cleanup EXIT
  ```

---

## 4. Diretrizes de Publicação & Estilo de Comunicação

### Releases no GitHub (`multi-forge/NightKernel-a14x`)
* **Banner:** Sempre incluir o banner no topo da release:
  `![NightKernel Banner](https://raw.githubusercontent.com/multi-forge/NightKernel-a14x/main/assets/banner.jpg)`
* **Tom & Linguagem:** Direto, técnico e autêntico de desenvolvedor humano.
* **SEM EMOJIS:** Proibido o uso de excesso de emojis e decorações vazias que pareçam geradas por IA.
* **Clareza de Mudança:** Explicar explicitamente a natureza da atualização (ex: bump de kernel LTS, correções de firmware).
* **Artefatos Obrigatórios por Release:**
  1. `NightKernel-vX.X.X-a14x.zip` (AnyKernel3 instalador TWRP)
  2. `boot-NightKernel-vX.X.X.tar` (Pacote Odin para slot AP)
  3. `boot.img` (Imagem de boot pura)
  4. `Image` (Kernel descompactado)
  5. `nightkernel-vX.X.X.config` (Arquivo .config utilizado)
  6. `sha256sums.txt` (Hashes de validação)

### Canal Oficial no Telegram (`@nightkernel`)
* Posts com banner fotográfico anexado.
* Texto conciso em formato de changelog humano.
* Links funcionais para as releases do GitHub e repositório de recovery TWRP.

---

## 5. Estrutura de Diretórios Local (Termux)

* **Workspace do Projeto:** `/data/data/com.termux/files/home/a14x-workspace/NightKernel/`
* **Repositório Git:** `https://github.com/multi-forge/NightKernel-a14x` (branch `main`).
* **Scripts de Automação:** `scripts/` (launchers e startups do GCP).
* **Downloads do Usuário:** `/sdcard/Download/` (linkado para `~/storage/downloads`).
