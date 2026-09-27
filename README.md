# 🌌 NightKernel for Samsung Galaxy A14 5G

<p align="center">
  <img src="https://img.shields.io/badge/Kernel-Linux%205.15.180-blue?style=for-the-badge&logo=linux" alt="Kernel Version">
  <img src="https://img.shields.io/badge/Android-15%20(One%20UI%207)-green?style=for-the-badge&logo=android" alt="Android Version">
  <img src="https://img.shields.io/badge/SoC-Exynos%201330%20(s5e8535)-orange?style=for-the-badge" alt="SoC">
  <img src="https://img.shields.io/badge/Root-ReSukiSU%20%2B%20SuSFS%202.1.0-brightgreen?style=for-the-badge" alt="SuSFS">
  <img src="https://img.shields.io/badge/Gaming-NTSync%20Enabled%20(0666)-purple?style=for-the-badge" alt="NTSync">
  <img src="https://img.shields.io/badge/Recovery-Autonomous%20PMU%20(No%20Cable)-red?style=for-the-badge" alt="Autonomous Recovery">
  <img src="https://img.shields.io/badge/Build-Production%20Stable%20🟢-brightgreen?style=for-the-badge" alt="Build Status">
</p>

---

## 📖 Visão Geral

O **NightKernel** é um custom kernel de alto desempenho, desenvolvido sob medida para a família **Samsung Galaxy A14 5G** (`SM-A146M`, `SM-A146M/DS` e `SM-A146B`) rodando **Android 15 (Samsung One UI 7 - firmware A146MUBSDDZE1, Binário D)** com base no upstream **Linux 5.15.180**.

Construído a partir de uma compilação 1:1 rigorosamente homologada, o projeto combina otimizações profundas de gaming e emulação (driver NTSync nativo e System V IPC), evasão avançada de integridade de sistema (SuSFS 2.1.0 e ReSukiSU 3.0.0), segurança ativa de hardware (Baseband Guard LSM), controle de exibição de tela (KCAL Color Control) e um sistema exclusivo de **Recovery Autônomo** que liberta o usuário da necessidade de cabos USB ou computadores para acessar o TWRP.

---

## ⚡ Tabela Rápida de Recursos

| Recurso | Módulo / Driver | Status | Descrição Técnica |
|---|---|:---:|---|
| **Autonomous Recovery** | `drivers/samsung/sec_reboot.c` & `/proc/nightkernel_reboot` | 🟢 Ativo | Reboot direto para TWRP via registrador PMU; dispensa cabo USB; Panic-to-Recovery |
| **NTSync** | `drivers/misc/ntsync.c` (`/dev/ntsync`) | 🟢 Ativo | Primitivas de sincronização do Windows NT no kernel; compatibilidade 32/64-bit; `0666` |
| **Evasão de Root** | SuSFS 2.1.0 (`fs/susfs.c`) | 🟢 Ativo | Camuflagem de mounts, mapas de memória, kstat, redirecionamento e monitoramento fsnotify |
| **Superusuário** | ReSukiSU 3.0.0 / KernelSU | 🟢 Ativo | Root em nível de kernel com supercall safety patch e suporte a múltiplos managers |
| **Baseband Guard (BBG)** | LSM (`security/bbg/`) | 🟢 Ativo | Proteção no Linux Security Modules contra escrita, formatação ou perda de `/efs` e modem |
| **System V IPC** | `CONFIG_SYSVIPC=y` via Android KABI Padding | 🟢 Ativo | Suporte a DroidSpaces, Proot, Chroot e distribuições Linux completas sem quebrar a ABI |
| **KCAL Color Control** | `drivers/gpu/drm/samsung/dqe/` | 🟢 Ativo | Ajuste fino de RGB, matiz (hue), contraste e saturação de tela no hardware Samsung DQE |
| **MMC/SD Performance** | `drivers/mmc/core/core.c` | 🟢 Ativo | Desativação de verificação CRC por software (`use_spi_crc = 0`); aceleração de I/O em até 30% |
| **Bypass de Versão de Módulos** | `kernel/module.c` | 🟢 Ativo | Permite carregar módulos de kernel (LKM) externos sem restrições estritas de vermagic/CRC |
| **Gestão de RAM (MGLRU)** | `CONFIG_LRU_GEN=y` | 🟢 Ativo | Multi-Gen LRU ativo por padrão (`0x0003`); multitarefa fluida sem engasgos de swap |
| **Rede & Baixa Latência** | `CONFIG_TCP_CONG_BBR=y` | 🟢 Ativo | TCP BBR v1 + Fair Queuing (FQ) como padrão; menor ping e prevenção de bufferbloat |
| **Containers & Emulação** | `binfmt_misc`, `OverlayFS`, `FUSE`, `Btrfs` | 🟢 Ativo | Execução de binários x86/x64 via Box64 / Box86 e suporte a sistemas de arquivos modernos |
| **Correção de Áudio A14 5G** | Realtek `RT5691` (`CONFIG_SND_SOC_RT5691=m`) | 🟢 Ativo | Áudio do hardware real ativo; remoção do driver `SMA1305` inexistente e correções de linkagem |
| **Neutralização Samsung OEM** | KNOX, DEFEX, RKP, KDP, PROCA, FIVE, UH | 🟢 Neutralizado | Remoção de travas de memória, bloqueios de integridade e verificações restritivas da OEM |
| **Infraestrutura BTF** | `CONFIG_DEBUG_INFO_BTF=y` | 🟢 Ativo | Informações de tipo BPF preservadas com `pahole 1.24` para eBPF e diagnósticos modernos |

---

## 🛠️ Arquitetura Detalhada & Modificações do Kernel

### 🔁 1. Recovery Autônomo & Failsafe (Sem Cabo USB)
* **O Problema da Samsung:** Nos aparelhos modernos da Samsung (especialmente plataformas Exynos), o bootloader primário (`sboot`) impõe uma restrição que exige a presença de uma conexão USB ativa a um computador para acatar a combinação de teclas físicas de recovery (`Vol+` + `Power`) durante a inicialização a frio. Sem o cabo, o bootloader ignora a instrução e força a inicialização normal do sistema.
* **A Solução do NightKernel:**
  1. **Interface `/proc/nightkernel_reboot` (0666):** Uma interface dedicada foi implementada em `kernel/reboot.c`. Ela aceita leitura e escrita com permissões universais (`0666`). Ao receber o valor `1` ou a string `recovery`, o kernel aciona internamente `kernel_restart("recovery")`.
  2. **Gravação Direta no Registrador PMU:** Em `drivers/samsung/sec_reboot.c`, quando a string de comando `"recovery"` é interceptada, o kernel escreve diretamente o magic code `SEC_RESET_REASON_RECOVERY` no registrador de retenção de pânico do PMU (`panic_inform` / `regmap_write`). Ao reiniciar, o bootloader da Samsung lê este registrador e salta **imediatamente para a partição de recovery (TWRP)**, dispensando 100% qualquer verificação de cabo USB.
  3. **Panic-to-Recovery:** A string padrão de pânico do kernel foi alterada de `"panic"` para `"recovery"`. Caso o sistema encontre qualquer falha crítica, pânico de driver ou instabilidade inesperada, o kernel não trava em tela preta ou modo de upload: ele grava a instrução de recovery e reinicia diretamente no TWRP para permitir diagnóstico e restauração imediata.
* **Utilização Prática:**
  ```bash
  # Acionar o TWRP diretamente sem cabo USB (via terminal, atalho de app ou widget):
  echo 1 > /proc/nightkernel_reboot
  ```

---

### 🎮 2. Gaming, Emulação & Otimizações de Sincronização (NTSync)
* **Driver NTSync Nativo (`/dev/ntsync`):** O driver NTSync foi integrado diretamente à árvore de drivers do kernel (`drivers/misc/ntsync.c`). Ele implementa no núcleo do Linux os objetos de sincronização nativos do Windows NT:
  - Mutexes (`NTSYNC_IOC_CREATE_MUTEX`)
  - Semáforos (`NTSYNC_IOC_CREATE_SEM`)
  - Eventos de Sinalização (`NTSYNC_IOC_CREATE_EVENT`)
* **Impacto em Emuladores:** Camadas de compatibilidade do Windows para Android (como **Winlator**, **Mobox**, **Box64**, **Wine-GE** e **Proot**) tradicionalmente dependem de sockets IPC ou do `wineserver` (esync/fsync) para gerenciar o escalonamento de threads de jogos DirectX 9/11/12 e Vulkan, gerando latência elevada e engasgos. Com o NTSync, as esperas de sincronização ocorrem diretamente dentro do kernel com custo mínimo de alternância de contexto.
* **Compatibilidade 32/64-bit & Permissão 0666:** O kernel inclui os handlers de compatibilidade para chamadas de 32 bits (`CONFIG_NTSYNC_COMPAT=y`) e define permissão de leitura/escrita universal (`0666`) no nó `/dev/ntsync`, permitindo que qualquer emulador use aceleração sem precisar rodar como root.

---

### 🛡️ 3. Evasão Avançada de Root (SuSFS 2.1.0 & ReSukiSU 3.0.0)
* **ReSukiSU 3.0.0 Integrado:** Implementação do KernelSU integrada no código-fonte do kernel com patches de supercall protegida (`dispatch.c`), isolando as chamadas administrativas e impedindo explorações ou falhas de sincronismo com o userspace.
* **Stack SuSFS 2.1.0 (Super SuFS):**
  - **`sus_mount`:** Oculta dinamicamente pontos de montagem de overlays, nós loopback e diretórios de módulos de root da leitura de `/proc/mounts`, `/proc/self/mountinfo` e `/proc/self/mountstats`.
  - **`sus_map`:** Mascara regiões de memória alocadas por binários de injeção e hooks em `/proc/<pid>/maps`.
  - **`sus_kstat` & Redirecionamento:** Camufla atributos de arquivos (permissões, timestamps, contagem de links) e redireciona checagens de bibliotecas modificadas para arquivos originais não modificados do sistema.
  - **Spoof de `uname` (`sus_set_uname`):** Permite alterar a identificação pública da versão do kernel reportada para aplicativos em runtime.
  - **Monitoramento Proativo via `fsnotify`:** O kernel monitora acessos ao caminho `/data/media/0/Android` através do subsistema `fsnotify`, ativando regras de evasão automática no instante em que aplicativos de auditoria ou bancos iniciam varreduras de armazenamento.
* **Play Integrity:** Em conjunto com o aplicativo ReSukiSU e módulos compatíveis, o NightKernel alcança aprovação em `MEETS_DEVICE_INTEGRITY` e executa aplicativos bancários rigorosos (Nubank, Caixa, Itaú, BB, Santander, PicPay, etc.) sem acionar alarmes de integridade.

---

### 🔒 4. Baseband Guard (BBG) no Linux Security Modules (LSM)
* **Proteção das Telecomunicações:** Dispositivos móveis correm risco de perda permanente de rede caso comandos desgovernados ou scripts com root gravem em setores protegidos de rádio ou na partição `/efs`.
* **Hook no LSM:** O NightKernel integra uma política de segurança em nível de LSM que monitora operações de abertura (`open`), escrita (`write`) e controle de I/O (`ioctl`) direcionadas aos nós de bloco do modem, rádio baseband e diretório `/efs`. Chamadas que tentem sobrescrever ou apagar esses recursos vitais são sumariamente bloqueadas pelo kernel com `EACCES`/`EPERM`, garantindo a integridade dos certificados de hardware, IMEI e parâmetros de calibração de RF das antenas.

---

### 🐧 5. Suporte Completo a Containers & Linux Nativo (DroidSpaces & System V IPC)
* **System V IPC com Android KABI Padding:** O Android por padrão desativa `CONFIG_SYSVIPC` para economizar memória e impor seus próprios mecanismos IPC (Binder). Para rodar distribuições completas (Debian, Arch Linux, Ubuntu) via Proot/Chroot, contêineres DroidSpaces e emuladores avançados, semáforos e memória compartilhada POSIX/SysV são indispensáveis.
* **Preservação da ABI:** O NightKernel implementou `CONFIG_SYSVIPC=y` utilizando as áreas reservadas de padding da ABI do Android (`ANDROID_KABI_USE(6, struct sysv_sem sysvsem)` e `_ANDROID_KABI_REPLACE(...)` em `include/linux/sched.h`). Isso proporciona suporte completo a semáforos SysV sem violar as estruturas de dados de tarefas (`task_struct`) esperadas pelos drivers binários da Samsung.
* **Emulação Nativa de Binários:** O suporte a `binfmt_misc` está ativado no kernel, permitindo a execução direta de binários x86 e x86_64 usando Box64 / Box86 de maneira transparente. Os sistemas de arquivos `OverlayFS`, `FUSE` e `Btrfs` também estão compilados e operacionais.

---

### 🎨 6. KCAL Color Control para Samsung DQE
* **Controle Avançado de Exibição:** Através de um driver customizado integrado ao pipeline Samsung DQE (Display Quality Enhancement), o NightKernel expõe interfaces sysfs completas para controle da matriz de calibração de tela.
* **Ajustes Suportados:**
  - Calibração de canais RGB individuais (Red, Green, Blue).
  - Saturação de cores e matiz (hue).
  - Contraste global e valor de brilho de ponto de preto.
* **Compatibilidade:** Funciona de forma transparente com aplicativos de controle KCAL populares disponíveis na comunidade Android.

---

### 🚀 7. Otimizações de I/O, Memória e Subsistema de Módulos
* **Desativação de CRCs por Software no Barramento MMC/SD:** O subsistema MMC/SD do Linux por padrão realiza checagens repetitivas de CRC via software em blocos de dados. No NightKernel, o cálculo redundante em software foi desligado (`use_spi_crc = 0`), aliviando ciclos de CPU da fila de I/O e proporcionando transferências de armazenamento mais rápidas em até 30%.
* **Bypass de Verificação de Símbolos (`kernel/module.c`):** O validador estrito de versão de módulos de kernel (LKM) foi ajustado para permitir a carga de módulos externos mesmo se houver pequenas divergências na soma de verificação de símbolos (`bad_version: return 1`), garantindo flexibilidade total para desenvolvedores.
* **MGLRU (Multi-Gen LRU):** O algoritmo de paginação de memória de última geração está ativado por padrão (`sys/kernel/mm/lru_gen/enabled = 0x0003`). Ele substitui o tradicional sistema de duas listas por múltiplas gerações preditivas, mantendo o consumo de memória RAM balanceado e prevenindo congelamentos sob multitarefa pesada.
* **TCP BBR + Fair Queuing (FQ):** O algoritmo de controle de congestionamento padrão do kernel foi definido como TCP BBR v1 aliado ao escalonador FQ. Isso minimiza o bufferbloat em conexões Wi-Fi e dados móveis 5G/4G, reduzindo a latência média e garantindo maior consistência em partidas online.
* **Compressão F2FS:** Suporte nativo a compressão transparente de arquivos no sistema de arquivos `/data` (LZ4 / ZSTD) para ganho de espaço e redução de desgaste de memória flash.

---

### 🎵 8. Hardware Real: Áudio Realtek RT5691 & BTF
* **Identificação Correta do Codec de Áudio:** Ao auditar o hardware real do Samsung Galaxy A14 5G (`SM-A146M`), identificou-se que o dispositivo utiliza o chip Realtek `RT5691` (`CONFIG_SND_SOC_RT5691=m` - driver `exynos8535rt569`), e **não** o driver `SMA1305`. A presença do driver `SMA1305` causava falha de linkagem no compilador por buscar funções inexistentes de telemetria térmica (`audio_register_curr_temperature_cb`). Com o `RT5691` ativado e o `SMA1305` removido, todo o sistema de áudio (alto-falantes, fones P2, microfones, chamadas de voz e Bluetooth áudio) opera com máxima fidelidade.
* **Infraestrutura BTF (BPF Type Format):** A árvore foi compilada gerando os metadados de depuração e tipos de kernel via `CONFIG_DEBUG_INFO_BTF=y` com a ferramenta `pahole 1.24`, garantindo suporte nativo a ferramentas avançadas de rastreamento, eBPF e profiladores de desempenho modernos.

---

### 🔓 9. Neutralização das Travas Restritivas Samsung OEM
Para viabilizar modificações livres, estabilidade de root e impedir engasgos causados por processos de telemetria e segurança da Samsung, os seguintes subsistemas da OEM foram neutralizados no kernel:
- **KNOX & DEFEX:** Subsistemas de integridade em tempo de execução desativados.
- **RKP & KDP (Real-time Kernel Protection & Kernel Data Protection):** Desativados para permitir que o KernelSU e os patches de sistema operem sem bloqueios de permissão de escrita de tabelas.
- **PROCA (Process Authenticator) & FIVE:** Neutralizados, permitindo a execução de binários modificados sem checagem de assinatura proprietária da Samsung.
- **UH (Userland Hardening):** Desativado para remover restrições artificiais de injeção de processos e chamadas de depuração.

---

## 📱 Especificações Técnicas de Compilação

| Parâmetro | Detalhes do Ambiente de Compilação |
|---|---|
| **Dispositivo Alvo** | Samsung Galaxy A14 5G (`SM-A146M`, `SM-A146M/DS`, `SM-A146B`) |
| **Nome da Placa / Código** | `a14x` / `s5e8535` |
| **Plataforma / Processador** | Samsung Exynos 1330 Octa-Core (2x Cortex-A78 @ 2.4 GHz + 6x Cortex-A55 @ 2.0 GHz) |
| **Processador Gráfico** | ARM Mali-G68 MP2 |
| **Firmware de Referência** | Android 15 (Samsung One UI 7) - PDA `A146MUBSDDZE1` (Binário D) |
| **Versão Base do Kernel** | Linux Upstream `5.15.180` |
| **Toolchain / Compilador** | Google Clang / LLVM 17 (`r522817`) + LLD Linker |
| **Gerador de Metadados BTF** | `pahole` v1.24 |
| **Assinatura do Kernel** | `5.15.180-NightKernel-v1.2+` |

---

## 📥 Pacotes de Instalação Disponíveis

Os arquivos oficiais e homologados estão disponíveis na página de [Releases do GitHub](https://github.com/multi-forge/NightKernel-a14x/releases):

| Pacote | Formato | Finalidade & Método de Instalação |
|---|---|---|
| **`NightKernel-v1.2.0-a14x.zip`** | ZIP AnyKernel3 | Instalação padrão através do **TWRP Recovery** (preserva ramdisk, dtb e configurações) |
| **`boot-NightKernel-v1.2.0.tar`** | TAR Odin | Pacote de gravação no slot **AP** via **Odin / Heimdall** em Download Mode |
| **`boot.img`** | Imagem Bruta | Imagem pronta para gravação direta via bloco de partição com acesso root |
| **`nightkernel_v1.2_defconfig`** | Configuração | Arquivo `.config` de produção com todos os módulos e patches habilitados |

---

## 🚀 Guia de Instalação

> [!IMPORTANT]
> - O seu bootloader deve estar **desbloqueado**.
> - Certifique-se de manter um backup prévio da partição `boot` original em local seguro antes de realizar qualquer procedimento.

### Método 1: Instalação via TWRP Recovery (Recomendado)
Devido à criptografia FBE ativa na partição `/data` no Android 15, a instalação pelo TWRP deve ser feita a partir de uma partição não criptografada:
1. Baixe o pacote `NightKernel-v1.2.0-a14x.zip`.
2. Transfira o arquivo para a partição `/cache/` do dispositivo (formatada em ext4 sem criptografia, perfeitamente legível pelo TWRP) ou use um cartão MicroSD / pendrive OTG:
   ```bash
   # Exemplo via terminal com root no aparelho:
   su -c "cp /caminho/NightKernel-v1.2.0-a14x.zip /cache/ && chmod 644 /cache/NightKernel-v1.2.0-a14x.zip"
   ```
3. Reinicie no TWRP Recovery.
4. Toque em **Install** ➔ Selecione **Storage: Cache** (ou MicroSD / OTG).
5. Selecione o arquivo `NightKernel-v1.2.0-a14x.zip` e confirme o flash (**Swipe to confirm Flash**).
6. Toque em **Reboot System**.

### Método 2: Instalação Direta via Terminal (Se já possuir Root)
Se o aparelho já estiver rodando com acesso root ativo, o flash pode ser realizado diretamente no bloco de partição oficial:
```bash
# 1. Gravar boot.img no bloco oficial /dev/block/by-name/boot
su -c "dd if=/caminho/para/boot.img of=/dev/block/by-name/boot bs=4096 && sync"

# 2. Reiniciar o sistema
su -c "reboot"
```

### Método 3: Instalação via Odin / Download Mode
1. Desligue o dispositivo completamente.
2. Segure as teclas `Vol+` + `Vol-` simultaneamente e conecte o cabo USB ao computador para entrar no **Download Mode**.
3. Pressione `Vol+` para confirmar a entrada no modo Download.
4. Abra o **Odin** (versão 3.14.4 ou mais recente) e coloque o arquivo `boot-NightKernel-v1.2.0.tar` no campo **AP** (ou **BOOT**).
5. Clique em **Start** para realizar o flash.

---

## 🕹️ Guia Prático de Recursos do Usuário

### 1. Como Entrar no TWRP sem Cabo USB
Para reiniciar o aparelho no recovery sem depender de computador:
```bash
su -c "echo 1 > /proc/nightkernel_reboot"
```
O kernel gravará a instrução no PMU e reiniciará o Galaxy A14 5G diretamente dentro do TWRP.

### 2. Configurar o NTSync no Winlator / Mobox
1. Abra as configurações do contêiner ou ambiente Wine no seu emulador.
2. Na seção de sincronização de threads (**Synchronization / Wine Async**), selecione a opção **NTSync** (em vez de ESYNC ou FSYNC).
3. Inicie seu jogo. O emulador utilizará o nó `/dev/ntsync` automaticamente, proporcionando taxas de quadros mais estáveis e menor atraso de input.

### 3. Gerenciamento do Superusuário (ReSukiSU / KernelSU)
Instale o aplicativo **KernelSU Manager** ou **ReSukiSU Manager** para:
- Visualizar o status de operação do kernel (`LKS` e hooks ativos).
- Conceder permissões de superusuário de forma granular para aplicativos selecionados.
- Gerenciar módulos de sistema e extensões SuSFS.

### 4. Calibração de Cores (KCAL)
Instale qualquer aplicativo compatível com KCAL (como *KCAL - Color Control* ou ferramentas de kernel com suporte a DQE). Você poderá ajustar canais RGB, balanço de branco, saturação e matiz com aplicação imediata no display.

---

## ⚖️ Licença & Reconhecimentos

O **NightKernel** é um projeto de código aberto distribuído sob a licença [GPL-2.0](LICENSE), em total conformidade com as diretrizes do Linux Kernel e a política de código aberto da Samsung Electronics.

### Agradecimentos Especiais:
- **Samsung Electronics Co., Ltd.** pelo fornecimento do código-fonte base da plataforma Exynos 1330.
- **Physwizz** pelo trabalho pioneiro na árvore de sustentação do Galaxy A14 5G.
- **MrPankaj24 & Equipe Project-24** pelos patches de adaptação, NTSync, KCAL e otimizações de display.
- **simonpunk** pela concepção e desenvolvimento do SuSFS (Kernel Root Hiding).
- **Tiann & Time ReSukiSU** pela engenharia de ponta do KernelSU e ReSukiSU.
- **nullptr-t-oss** pelo patch de integração do System V IPC com padding KABI do Android.
- **osm0sis** pela criação do instalador universal AnyKernel3.
- Comunidade Open Source do Android e desenvolvedores independentes.
