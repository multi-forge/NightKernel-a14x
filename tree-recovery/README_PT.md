# Samsung Galaxy A14 5G (`SM-A146M/DS` / `SM-A146B` — `a14x`)

<p align="center">
  <a href="README_PT.md"><img src="https://img.shields.io/badge/L%C3%ADngua-Portugu%C3%AAs%20(Brasil)-green?style=for-the-badge&logo=google-translate" alt="Português"></a>
  <a href="README.md"><img src="https://img.shields.io/badge/Language-English-blue?style=for-the-badge&logo=google-translate" alt="English"></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Dispositivo-Samsung%20Galaxy%20A14%205G-blue?style=for-the-badge&logo=samsung" alt="Device">
  <img src="https://img.shields.io/badge/SoC-Exynos%201330%20(s5e8535)-orange?style=for-the-badge" alt="SoC">
  <img src="https://img.shields.io/badge/Android-15%20(One%20UI%207)-green?style=for-the-badge&logo=android" alt="Android">
  <img src="https://img.shields.io/badge/Recovery-TWRP%20v3.7%20Persistente%20🟢-brightgreen?style=for-the-badge" alt="Recovery">
</p>

<p align="center">
  <a href="https://github.com/multi-forge/android_device_samsung_a14x/releases/tag/unbrick-dze1"><img src="https://img.shields.io/badge/Download-TWRP%20Recovery%20(DZE1)-red?style=for-the-badge&logo=twrp" alt="Download TWRP"></a>
  <a href="https://github.com/multi-forge/NightKernel-a14x"><img src="https://img.shields.io/badge/Kernel-NightKernel%20a14x-purple?style=for-the-badge" alt="NightKernel"></a>
</p>

Repositório oficial da árvore de dispositivo (Device Tree), módulos de persistência de recovery, configurações de kernel e procedimentos de desbrickagem para o **Samsung Galaxy A14 5G** (`SM-A146M` e `SM-A146B`, codinome `a14x`), plataforma **Exynos 1330 (`s5e8535`)**, rodando **Android 15 (One UI 7 - PDA `A146MUBSDDZE1`, Binário D)**.

---

## 📱 Especificações Técnicas do Dispositivo

| Parâmetro | Valor / Especificação |
|---|---|
| **Modelo** | Samsung Galaxy A14 5G (`SM-A146M/DS` / `SM-A146B`) |
| **Codinome** | `a14x` / `s5e8535` |
| **SoC / Chipset** | Samsung Exynos 1330 (2× Cortex-A78 @ 2.4 GHz + 6× Cortex-A55 @ 2.0 GHz) |
| **GPU** | ARM Mali-G68 MP2 |
| **Codec de Áudio** | `SMA1305` |
| **PDA / AP** | `A146MUBSDDZE1` |
| **CSC** | `A146MOWODDZE1` (OWO / ZTO / LATAM) |
| **Versão Android** | Android 15 / One UI 7 (Binário D - Bootloader v4/v2) |
| **Kernel Baseline** | Linux `5.15.180` (Branch `V-sd-perm`, commit `ca3d9d162`) |
| **Partição Recovery** | `100.663.296` bytes (96 MB) — Boot Header v2 |
| **Partição Boot** | `67.108.864` bytes (64 MB) — Boot Header v4 (ramdisk 0) |
| **Partição Init Boot** | `16.777.216` bytes (16 MB) — Contém o ramdisk do sistema |
| **Custom Kernel Oficial** | [multi-forge/NightKernel-a14x](https://github.com/multi-forge/NightKernel-a14x) |

---

## 🛠️ Arquitetura do TWRP Recovery no Android 15

### 1. Formato e Particionamento
- O recovery reside na partição `/dev/block/by-name/recovery` (96 MB) e utiliza o formato **Boot Header v2** (kernel integrado + ramdisk TWRP + DTB da Samsung compilado para `s5e8535`).
- Suporta modo **Fastbootd** integrado para flashing de partições dinâmicas (`system`, `vendor`, `product`, `system_ext`).

### 2. Mecanismo de Persistência (Anti-Recovery Restore)
Nos firmwares stock da Samsung, o sistema operacional tenta restaurar automaticamente o recovery de fábrica a cada boot através do arquivo `/system/bin/install-recovery.sh` e do patch delta `/system/recovery-from-boot.p`.
- **Como neutralizamos:** 
  - O módulo [modules/keep-twrp](modules/keep-twrp) é injetado no ambiente de inicialização (Magisk/KernelSU).
  - Ele intercepta a execução de scripts de restauração e bloqueia qualquer gravação não autorizada na partição de recovery, garantindo que o TWRP permaneça permanentemente instalado após reboots.

### 3. Failsafe Local em `/cache` (Contorno da Criptografia FBE)
No Android 15, a partição `/data` utiliza criptografia FBE (File-Based Encryption) baseada em chaves do hardware TrustZone/Keystore. Por este motivo, o TWRP **não descriptografa** o armazenamento interno `/sdcard`.
- **Solução Arquitetural:** 
  - A partição `/cache` (`/dev/block/by-name/cache`, ext4) **não é criptografada** e é montada nativamente pelo TWRP com leitura e escrita totais.
  - Mantemos uma suíte completa de recuperação permanente em `/cache`:
    - `/cache/Restore-Stock-Boot.zip`: AnyKernel3 para restauração stock instantânea (1 clique).
    - `/cache/Kernel-Base-a14x-Vsd.zip`: AnyKernel3 do novo kernel base.
    - `/cache/boot-backup.img`: Dump bruto de 64 MB da partição de boot funcional.
    - `/cache/restore_boot.sh`: Script executável direto pelo Terminal do TWRP.

### 4. Trava de Handshake USB do Bootloader (`sboot`) & Solução Autônoma
No bootloader stock da Samsung para a plataforma Exynos 1330:
- Para acionar o recovery com os botões físicos (`Vol+` + `Power`) durante a inicialização a frio, o `sboot` stock **exige que um cabo USB esteja conectado a um PC ou carregador** (detecção de sinal elétrico `VBUS` / handshake USB).
- Se os botões forem pressionados sem o cabo plugado, o bootloader ignora a solicitação e prossegue com a inicialização normal do Android.
- ⚡ **Solução Integrada com NightKernel:**
  - Com o [NightKernel v1.2+](https://github.com/multi-forge/NightKernel-a14x) instalado, essa limitação é superada: você pode reiniciar diretamente no TWRP a qualquer momento sem cabo USB executando:
    ```bash
    echo 1 > /proc/nightkernel_reboot
    ```
    ou segurando `Power + Vol+` durante o reboot do sistema operacional.

---

## 🚀 Como Instalar o TWRP Recovery

### Método 1: Via Odin / Heimdall (Download Mode)
1. Coloque o aparelho em **Download Mode** (com o aparelho desligado, segure `Vol+` + `Vol-` e conecte o cabo USB ao PC).
2. Abra o Odin e insira o pacote [`twrp-12-vsd-dze1.tar`](https://github.com/multi-forge/android_device_samsung_a14x/releases/tag/unbrick-dze1) no campo **AP** (ou use o Heimdall para gravar a partição `RECOVERY`).
3. No Odin, desmarque a opção **Auto Reboot**.
4. Inicie o flash. Quando concluir, force o reboot segurando `Vol-` + `Power` e, assim que a tela apagar, mude imediatamente para `Vol+` + `Power` (mantendo o cabo USB conectado) para entrar diretamente no TWRP.

### Método 2: Diretamente pelo Terminal (Root)
```bash
su
dd if=/caminho/para/recovery.img of=/dev/block/by-name/recovery bs=4096
sync
```

---

## 🆘 Procedimento de Desbrickagem (Unbrick / Odin)

Caso ocorra corrupção de partições ou falha crítica durante experimentos:
1. Coloque o aparelho em Download Mode (`Vol -` + `Vol +` com cabo USB).
2. Baixe os artefatos oficiais da [Release unbrick-dze1](https://github.com/multi-forge/android_device_samsung_a14x/releases/tag/unbrick-dze1):
   - `unbrick-dze1-recovery.tar`: Restaura a partição `/dev/block/by-name/recovery`.
   - `unbrick-dze1-boot.tar`: Restaura as partições `/dev/block/by-name/boot` e `/dev/block/by-name/init_boot`.
3. Flasheie via Odin (PC) ou Brokkr (OTG de outro celular Android).

---

## 🔐 Checksums de Verificação (Stock DZE1 Baseline)

```text
05fdc90b152966526553dca7bdbf21a0e35464d4905221adf49ee9677b732e32  recovery-stock.img
7659b2fd80a7d8537fba98073179f338bf205fb1694abe81b2134690754a2545  boot-current.img
2c0b60b7c93a184029d590ff508d920a5c205787ba248f423af348ca1553f423  init_boot-current.img
19c06b501ef7e0cfdd33d513078da98eaaecda7d4ab56bc83dcbb4fe81031015  dtbo-stock.img
9824851c3fda31a911ccc4fc6e134306e6f0ac502218375d7b3bd2a2289cec15  vbmeta-stock.img
cecc9b258175e228fc80c2237b8ba9baa66b93be4540cc5c8728d60f8718163f  config.gz
4bdf87b9274fb1e31c4aab5bc2fa871498a69b5499c6cb91b6011a722835af3f  unbrick-dze1-recovery.tar
0c388562d71dc648134fe43d4a501dd339cc7998106b49125c19f9daacd71cab  unbrick-dze1-boot.tar
```

---

## 🔗 Projetos Relacionados
- **Kernel Customizado Oficial:** [multi-forge/NightKernel-a14x](https://github.com/multi-forge/NightKernel-a14x)
- **Árvore Fonte do Kernel:** [physwizz/a146b-a146m](https://github.com/physwizz/a146b-a146m) (branch `V-sd-perm`)
