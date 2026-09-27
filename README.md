# 🌌 NightKernel for Samsung Galaxy A14 5G (SM-A146M / SM-A146B)

<p align="center">
  <img src="https://img.shields.io/badge/Kernel-Linux%205.15.180-blue?style=for-the-badge&logo=linux" alt="Kernel Version">
  <img src="https://img.shields.io/badge/Android-15%20(One%20UI%207)-green?style=for-the-badge&logo=android" alt="Android Version">
  <img src="https://img.shields.io/badge/SoC-Exynos%201330%20(s5e8535)-orange?style=for-the-badge" alt="SoC">
  <img src="https://img.shields.io/badge/Status-Base%20Homologada%20🟢-brightgreen?style=for-the-badge" alt="Status">
</p>

**NightKernel** é um projeto de custom kernel de alta fidelidade e desempenho voltado para o **Samsung Galaxy A14 5G** (`SM-A146M` e `SM-A146B`, codename `a14x`), rodando **Android 15 (One UI 7 - firmware A146MUBSDDZE1, Binário D)** com base no upstream **Linux 5.15.180**.

---

## 📱 Especificações do Dispositivo & Alvo

| Parâmetro | Detalhes |
|---|---|
| **Aparelho** | Samsung Galaxy A14 5G (`SM-A146M/DS` / `SM-A146B`) |
| **Codinome** | `a14x` / `s5e8535` |
| **SoC / Plataforma** | Samsung Exynos 1330 (Octa-core 2x A78 @ 2.4 GHz + 6x A55 @ 2.0 GHz) |
| **GPU** | ARM Mali-G68 MP2 |
| **Codec de Áudio** | `SMA1305` |
| **Versão Android** | Android 15 (One UI 7) - PDA `A146MUBSDDZE1` (Binary D) |
| **Versão Base do Kernel** | Linux `5.15.180` |
| **Árvore de Origem** | `physwizz/a146b-a146m` branch `V-sd-perm` (Commit `ca3d9d162788e0dcae9e049d5336bf9ff9b867c4`) |
| **Toolchain Exata** | Android Clang 14.0.6 (`clang-r450784d`) + LLD 14.0.6 |

---

## 🔬 Descobertas Técnicas Críticas & Arquitetura de Boot

Durante a homologação em campo, identificamos os requisitos fundamentais para o boot estável no Android 15 One UI 7 da Samsung:

### 1. Requisito Obrigatório de BTF (BPF Type Format)
A partição `vendor_boot` do Galaxy A14 5G contém ~15 MB de módulos DLKM essenciais compilados pela Samsung (`ufs_exynos_core.ko`, drivers de PMIC, display e barramento).
- O `first-stage init` do Android 15 valida estritamente a seção `.BTF` de todos os módulos contra o binário principal `Image`.
- Compilar o kernel sem BTF (`--disable CONFIG_DEBUG_INFO_BTF`) ou sem a ferramenta `dwarves` (`pahole`) remove a seção `.BTF`, fazendo com que o driver do disco UFS (`ufs_exynos_core.ko`) seja rejeitado no primeiro segundo de boot, travando em bootloop imediato para o recovery.
- O NightKernel é compilado **com suporte integral a BTF (`CONFIG_DEBUG_INFO_BTF=y`)** gerando o binário `Image` de ~38,7 MB idêntico ao kernel ativo funcional.

### 2. Header v4 do Boot Image
No Android 13+ com partição `init_boot`, o `boot.img` usa formato **Header v4**:
- O ramdisk de boot reside exclusivamente na partição `init_boot`. O tamanho de ramdisk no `boot.img` é rigorosamente **0 bytes**.
- O AnyKernel3 foi customizado para operar exclusivamente no modo `split_boot; flash_boot;`, substituindo o binário `Image` sem corromper a estrutura de cabeçalho do bootloader.

### 3. Failsafe Local em `/cache` (Sem Criptografia)
Como o Android 15 utiliza criptografia FBE (File-Based Encryption), o TWRP não consegue descriptografar a partição `/data` (`/sdcard`) sem chave.
- A partição de cache (`/dev/block/by-name/cache`, ext4) **não é criptografada** e é montada nativamente pelo TWRP.
- Mantemos a suíte de emergência e recuperação stock diretamente em `/cache`:
  - `/cache/Restore-Stock-Boot.zip` (Restauração stock 1-click via AnyKernel3)
  - `/cache/boot-backup.img` (Dump binário bruto da partição de boot original)
  - `/cache/restore_boot.sh` (Script de recuperação imediata via terminal do TWRP)

---

## 🗺️ Roadmap de Desenvolvimento (Fases do Projeto)

- [x] **Fase P0 (Unbrick Baseline):** Pacotes Odin `.tar` publicados na release [`unbrick-dze1`](https://github.com/multi-forge/android_device_samsung_a14x/releases/tag/unbrick-dze1).
- [x] **Fase P1 & P2 (TWRP Persistente):** TWRP persistente testado e validado com scripts anti-restore.
- [x] **Fase P4A (Kernel Base 1:1 Funcional):** 🟢 **HOMOLOGADO EM CAMPO!** Kernel 5.15.180 limpo com BTF compilado na nuvem GCP e boot validado no Android 15 One UI 7.
- [ ] **Fase P4B (Reboot Autônomo para TWRP):** Patch no driver PMIC/reboot para contornar a trava do `sboot` da Samsung, permitindo entrar no recovery com `Vol+` + `Power` sem necessidade de cabo USB conectado.
- [ ] **Fase P4C (Stack Project-24):**
  - Integração de **ReSukiSU / KernelSU Next**
  - Integração de **SuSFS 2.1.0** (Stealth Root / Play Integrity bypass)
  - Integração do driver **NTSync** (sincronização de alto rendimento para emuladores e games)
  - Perfil de desempenho `perf.config` adaptado mantendo áudio `SMA1305`.
- [ ] **Fase P4D (Otimizações Avançadas):** Agendador de tarefas (EAS tweaks), governadores e redução de jitter.

---

## 📦 Como Instalar

### Método 1: Via TWRP (Recomendado)
1. Coloque o arquivo `NightKernel-Base-v1.0-a14x.zip` na partição `/cache` (ou OTG / MicroSD).
2. Reinicie no TWRP (`Vol+` + `Power` com cabo USB plugado ao PC).
3. Vá em **Install** -> Selecione **Storage: Cache**.
4. Selecione `NightKernel-Base-v1.0-a14x.zip` e confirme o flash (**Swipe to confirm Flash**).
5. Selecione **Reboot System**.

### Método 2: Via Odin / Heimdall (Download Mode)
1. Baixe o pacote `boot-nightkernel.tar`.
2. Reinicie o aparelho em Download Mode (`Vol+` + `Vol-` conectados ao cabo USB).
3. Insira o arquivo `boot-nightkernel.tar` no slot **AP** (ou **BOOT**) e inicie o flash.

### Método 3: Diretamente pelo Terminal (Root)
```bash
dd if=/caminho/para/boot.img of=/dev/block/by-name/boot bs=4096
sync
reboot
```

---

## 🛠️ Como Compilar a Partir do Código-Fonte

Consulte o script de automação em [scripts/build_nightkernel_gcp.sh](scripts/build_nightkernel_gcp.sh) para o pipeline completo de build com Clang 14 e geração de BTF.

```bash
# 1. Obter o script de build
chmod +x scripts/build_nightkernel_gcp.sh

# 2. Executar em ambiente Linux x86_64 / VM GCP
./scripts/build_nightkernel_gcp.sh
```

---

## ⚖️ Licença

Este projeto é distribuído sob a licença [GPL-2.0](LICENSE), em conformidade com os termos do kernel Linux e da Samsung Electronics Co., Ltd.
