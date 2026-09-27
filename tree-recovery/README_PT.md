# Device Tree do TWRP para Samsung Galaxy A14 5G (`a14x`)

[Português](README_PT.md) | [English](README.md)

<p align="center">
  <img src="https://raw.githubusercontent.com/multi-forge/NightKernel-a14x/main/assets/banner.jpg" alt="NightKernel & TWRP" width="100%">
</p>

Árvore de dispositivo oficial do TWRP, módulos de persistência e recursos de desbrickagem para o **Samsung Galaxy A14 5G** (`SM-A146M` / `SM-A146B`), plataforma **Exynos 1330 (`s5e8535`)**, rodando **Android 15 (One UI 7 - PDA `A146MUBSDDZE1`, Binário D)**.

---

## Especificações do Dispositivo

| Parâmetro | Especificação |
|---|---|
| **Aparelho** | Samsung Galaxy A14 5G (`SM-A146M/DS` / `SM-A146B`) |
| **SoC** | Samsung Exynos 1330 (2× Cortex-A78 @ 2.4 GHz + 6× Cortex-A55 @ 2.0 GHz) |
| **GPU** | ARM Mali-G68 MP2 |
| **Codec de Áudio** | Realtek `RT5691` |
| **PDA / AP** | `A146MUBSDDZE1` |
| **CSC** | `A146MOWODDZE1` (OWO / ZTO / LATAM) |
| **Versão Android** | Android 15 / One UI 7 (Binário D) |
| **Kernel Base** | Linux `5.15.180` (physwizz `V-sd-perm`) |
| **Partição Recovery** | `100.663.296` bytes (96 MB) — Boot Header v2 |
| **Partição Boot** | `67.108.864` bytes (64 MB) — Boot Header v4 (ramdisk 0) |
| **Partição Init Boot** | `16.777.216` bytes (16 MB) — Contém o ramdisk do sistema |
| **Custom Kernel Oficial** | [multi-forge/NightKernel-a14x](https://github.com/multi-forge/NightKernel-a14x) |

---

## Notas Técnicas

### 1. Particionamento e Boot Header
- A partição de recovery é `/dev/block/by-name/recovery` (96 MB) utilizando o formato **Boot Header v2** (kernel + ramdisk TWRP + DTB compilado para `s5e8535`).
- Suporte nativo ao modo **Fastbootd** para gravação de partições dinâmicas (`system`, `vendor`, `product`, `system_ext`).

### 2. Persistência do Recovery (`keep-twrp`)
O firmware stock da Samsung executa `/system/bin/install-recovery.sh` a cada inicialização para restaurar o recovery de fábrica a partir de `/system/recovery-from-boot.p`.
- O módulo [`modules/keep-twrp`](modules/keep-twrp) atua no early init (Magisk/KernelSU) para bloquear gravações não autorizadas na partição de recovery, garantindo que o TWRP permaneça instalado após reinicializações.

### 3. Criptografia FBE e Failsafe em `/cache`
O Android 15 utiliza criptografia FBE baseada em hardware TrustZone. O TWRP não descriptografa a partição interna de dados (`/sdcard`).
- A partição `/cache` (`/dev/block/by-name/cache`, ext4) não é criptografada e é montada nativamente pelo TWRP com leitura e escrita completas.
- Você pode armazenar pacotes de kernel e backups diretamente em `/cache/` ou utilizar um cartão MicroSD / pendrive USB OTG.

### 4. Bypass da Trava de Handshake USB
O bootloader stock da Samsung ignora os botões físicos de recovery (`Power + Vol Up`) no boot a frio caso não haja um cabo USB conectado ao computador.
- Ao utilizar o [NightKernel](https://github.com/multi-forge/NightKernel-a14x), essa dependência é eliminada. Você pode reiniciar diretamente no TWRP com:
  ```bash
  echo 1 > /proc/nightkernel_reboot
  ```
  ou segurando `Power + Vol Up` durante o reboot do sistema.

---

## Como Instalar

### Método 1: Odin / Heimdall (Download Mode)
1. Coloque o aparelho em Download Mode (`Vol+ + Vol-` com cabo USB conectado ao PC).
2. Baixe o pacote [`twrp-12-vsd-dze1.tar`](https://github.com/multi-forge/android_device_samsung_a14x/releases/tag/unbrick-dze1).
3. Insira o arquivo `twrp-12-vsd-dze1.tar` no campo **AP** do Odin.
4. Desmarque a opção **Auto Reboot** nas opções do Odin.
5. Inicie o flash. Quando concluir, force o reboot segurando `Vol- + Power` e, assim que a tela apagar, mude imediatamente para `Vol+ + Power` (mantendo o cabo USB conectado) para entrar diretamente no TWRP no primeiro boot.

### Método 2: Terminal com Root
```bash
dd if=recovery.img of=/dev/block/by-name/recovery bs=4096 && sync
```

---

## Desbrickagem
Artefatos de restauração stock para recovery e boot estão disponíveis na [Release unbrick-dze1](https://github.com/multi-forge/android_device_samsung_a14x/releases/tag/unbrick-dze1):
- `unbrick-dze1-recovery.tar`: Restaura o recovery stock.
- `unbrick-dze1-boot.tar`: Restaura `boot` e `init_boot` de fábrica.

---

## Links
- **Downloads do TWRP:** [Releases](https://github.com/multi-forge/android_device_samsung_a14x/releases)
- **Código do NightKernel:** [NightKernel-a14x](https://github.com/multi-forge/NightKernel-a14x)
