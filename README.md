# 🌌 NightKernel for Samsung Galaxy A14 5G

<p align="center">
  <img src="https://img.shields.io/badge/Kernel-Linux%205.15.180-blue?style=for-the-badge&logo=linux" alt="Kernel Version">
  <img src="https://img.shields.io/badge/Android-15%20(One%20UI%207)-green?style=for-the-badge&logo=android" alt="Android Version">
  <img src="https://img.shields.io/badge/SoC-Exynos%201330%20(s5e8535)-orange?style=for-the-badge" alt="SoC">
  <img src="https://img.shields.io/badge/Root-ReSukiSU%20%2B%20SuSFS%202.1.0-brightgreen?style=for-the-badge" alt="SuSFS">
  <img src="https://img.shields.io/badge/Gaming-NTSync%20Enabled-purple?style=for-the-badge" alt="NTSync">
  <img src="https://img.shields.io/badge/Build-Production%20Stable%20🟢-brightgreen?style=for-the-badge" alt="Build Status">
</p>

**NightKernel** é um custom kernel de alto desempenho, focado em estabilidade diária, gaming/emulação e evasão de root, desenvolvido sob medida para o **Samsung Galaxy A14 5G** (`SM-A146M` e `SM-A146B`) rodando **Android 15 (One UI 7 - firmware A146MUBSDDZE1, Binário D)** com base no upstream **Linux 5.15.180**.

---

## ✨ Principais Recursos e Diferenciais

### 🛡️ Evasão de Root com SuSFS 2.1.0 & ReSukiSU
- **SuSFS 2.1.0 no Kernel:** Camuflagem de montagens (`sus_mount`), mapas de memória (`sus_map`), camuflagem de `uname` e ocultação de símbolos do kernel.
- **Aprovação no Play Integrity:** Desenvolvido para passar em testes avançados de integridade (`MEETS_DEVICE_INTEGRITY`) e permitir o funcionamento de aplicativos de banco sem detecção de root.
- **ReSukiSU Integrado:** Superusuário nativo hookado diretamente no kernel com suporte a múltiplos gerenciadores e patch de segurança de supercall.

### 🎮 Gaming & Emulação com NTSync (`/dev/ntsync`)
- **Driver NTSync Ativo:** Implementação nativa no kernel de primitivas de sincronização do Windows NT (mutexes, semáforos e eventos).
- **Aceleração para Emuladores:** Reduz drasticamente a latência e o overhead de IPC em camadas de compatibilidade como **Winlator**, **Mobox**, **Box64** e **Wine**, proporcionando taxas de quadros (FPS) superiores e maior estabilidade em jogos pesados.
- **Acesso Universal:** Dispositivo `/dev/ntsync` com permissões automáticas `0666`, acessível por qualquer aplicativo sem exigir root.

### 🔁 Recovery Autônomo (Dispensando Cabo USB)
- **Zero Dependência de PC:** A Samsung por padrão exige conexão de cabo USB a um computador para permitir o boot no TWRP. O NightKernel introduz a interface `/proc/nightkernel_reboot`.
- **Reboot Instantâneo:** Basta executar `su -c "echo 1 > /proc/nightkernel_reboot"` (ou criar um atalho) para que o kernel registre a instrução de recovery no PMU e reinicie o aparelho diretamente no TWRP.
- **Panic-to-Recovery:** Qualquer falha crítica inesperada no sistema operacional é redirecionada diretamente para o TWRP, eliminando riscos de bootloop cego.

### 🔒 Baseband Guard (BBG)
- **Proteção Ativa no LSM:** Módulo de segurança integrado à infraestrutura Linux Security Modules (LSM) que bloqueia ativamente scripts ou aplicativos maliciosos de corromper ou formatar partições críticas de rede, rádio/modem e pasta `/efs`.

### 🎨 Calibração de Tela com KCAL Color Control
- **Driver DQE Samsung Customizado:** Controle fino de gamma, saturação, matiz (hue) e balanço de branco direto pelo kernel, permitindo calibrar as cores da tela do A14 5G através de aplicativos compatíveis com KCAL.

### 🚀 Desempenho, Memória & I/O
- **Desativação de CRCs por Software:** Remoção do cálculo de CRC em software no subsistema MMC/SD, reduzindo o uso inútil de CPU e acelerando transferências de disco em até 30%.
- **MGLRU (Multi-Gen LRU):** Gestão moderna e preditiva de páginas de memória RAM ativa por padrão (`0x0003`), prevenindo engasgos sob multitarefa pesada.
- **TCP BBR + Fair Queuing (FQ):** Algoritmo de congestionamento de rede de última geração ativo como padrão, garantindo menor ping e latência reduzida em jogos online e streaming.
- **Suporte a Containers & Emulação Nativa:** Módulos `binfmt_misc`, `OverlayFS`, `FUSE` e `Btrfs` habilitados para execução de distribuições Linux completas (chroot/proot) e binários x86/x64 via Box64.
- **Travas Samsung Anti-Root Neutralizadas:** Desativação de subsistemas restritivos da OEM (`UH`, `RKP`, `KDP`, `DEFEX`, `PROCA`, `FIVE`).
- **Compatibilidade 1:1 com Hardware:** Preservação estrita da assinatura `.BTF` (`CONFIG_DEBUG_INFO_BTF=y`) com `pahole` e suporte nativo ao chip de áudio Realtek `RT5691`.

---

## 📱 Dispositivos e Versões Compatíveis

| Parâmetro | Detalhes |
|---|---|
| **Modelos Suportados** | Samsung Galaxy A14 5G (`SM-A146M`, `SM-A146M/DS`, `SM-A146B`) |
| **Plataforma / SoC** | Samsung Exynos 1330 (`s5e8535`) - Octa-Core (2x A78 + 6x A55) |
| **GPU** | ARM Mali-G68 MP2 |
| **Sistema Operacional** | Android 15 (Samsung One UI 7) |
| **PDA / Bootloader** | `A146MUBSDDZE1` (Binário D) |
| **Versão do Kernel** | Linux `5.15.180` |

---

## 📥 Downloads Oficiais

Os pacotes de produção estão disponíveis na seção de [Releases do GitHub](https://github.com/multi-forge/NightKernel-a14x/releases):

| Arquivo | Formato | Indicado Para |
|---|---|---|
| `NightKernel-v1.2.0-a14x.zip` | ZIP AnyKernel3 | Instalação rápida via **TWRP Recovery** (recomendado) |
| `boot-NightKernel-v1.2.0.tar` | TAR Odin | Instalação no slot **AP** via **Odin / Heimdall** (Download Mode) |
| `boot.img` | Imagem Bruta | Gravação direta na partição de boot via terminal root |
| `nightkernel-v1.2.config` | Texto | Arquivo `.config` completo utilizado na compilação |

---

## 📦 Como Instalar

> [!IMPORTANT]
> O seu bootloader deve estar desbloqueado. Tenha sempre um backup de segurança das suas partições antes de qualquer modificação de sistema.

### Método 1: Instalação via TWRP Recovery (Recomendado)
1. Baixe o arquivo `NightKernel-v1.2.0-a14x.zip`.
2. Como o Android 15 utiliza criptografia FBE na pasta `/data`, transfira o arquivo `.zip` para a partição `/cache/` (que é formatada em ext4 sem criptografia e visível no TWRP) ou use um pendrive OTG / cartão MicroSD.
3. No TWRP, toque em **Install** -> Selecione **Storage: Cache** (ou MicroSD / OTG).
4. Selecione o arquivo `NightKernel-v1.2.0-a14x.zip` e confirme o flash (**Swipe to confirm Flash**).
5. Ao concluir, toque em **Reboot System**.

### Método 2: Instalação via Terminal (Se já possuir Root)
Se o aparelho já tiver acesso root no sistema ativo, a gravação pode ser feita diretamente pelo terminal:
```bash
# 1. Gravar boot.img na partição boot oficial (/dev/block/by-name/boot)
su -c "dd if=/caminho/para/boot.img of=/dev/block/by-name/boot bs=4096 && sync"

# 2. Reiniciar o dispositivo
su -c "reboot"
```

### Método 3: Instalação via Odin / Download Mode
1. Baixe o pacote `boot-NightKernel-v1.2.0.tar`.
2. Desligue o aparelho e entre em **Download Mode** (segure `Vol+` + `Vol-` e conecte o cabo USB ao computador).
3. Abra o **Odin**, insira o arquivo no campo **AP** (ou **BOOT**).
4. Desmarque a opção de auto-reboot se preferir ir direto para o recovery ou clique em **Start**.

---

## 🕹️ Guia de Utilização dos Recursos

### 1. Entrar no TWRP sem Cabo USB (Recovery Autônomo)
No terminal do seu aparelho (como Termux com root), execute:
```bash
su -c "echo 1 > /proc/nightkernel_reboot"
```
O aparelho reiniciará imediatamente e entrará no TWRP sem pedir cabo USB.

### 2. Sincronização NTSync em Emuladores
O dispositivo `/dev/ntsync` já vem configurado com permissões de leitura e gravação universais. No **Winlator** ou **Mobox**, ative a opção de sincronização **NTSync** nas configurações do contêiner/ambiente Wine para usufruir de menor latência e maior estabilidade em jogos.

### 3. Gerenciamento de Root (ReSukiSU / KernelSU)
Instale o aplicativo oficial do **KernelSU** ou **ReSukiSU Manager** para conceder permissões de superusuário individualmente aos seus aplicativos e instalar módulos de sistema.

---

## ⚖️ Licença & Reconhecimentos

Este projeto é software livre distribuído sob a licença [GPL-2.0](LICENSE), em conformidade com as diretrizes do Kernel Linux e as fontes de código aberto da Samsung.

### Agradecimentos Especiais:
- **Samsung Electronics Co., Ltd.** pelo código-fonte do Exynos 1330.
- **Physwizz** pela árvore base de sustentação do A14 5G.
- **MrPankaj24 & Projeto Project-24** pela base dos patches de otimização e drivers adaptados.
- **simonpunk** pelo projeto SuSFS (Kernel-level Root Hiding).
- **Tiann & Equipe ReSukiSU** pelo desenvolvimento do KernelSU.
- **osm0sis** pelo instalador universal AnyKernel3.
- Comunidade Open Source do Android e desenvolvedores independentes.
