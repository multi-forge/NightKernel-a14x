# NightKernel (Debug Branch) — High-Performance Logging & Diagnostic Kernel

Branch especializada em **depuração profunda e diagnósticos rápidos** para o Samsung Galaxy A14 5G (`SM-A146M` / `SM-A146B`).

---

### Otimizações do Build de Debug

1. **Velocidade de Compilação Ultra-Rápida:**
   - **`CONFIG_LTO_NONE=y`** (ThinLTO desativado): elimina o passo pesado de otimização global em link time (`vmlinux.o`), reduzindo o tempo de build em mais de 70% (tempo de link cai de minutos para segundos).

2. **Diagnósticos e Logs Expandidos na ROM:**
   - **`CONFIG_LOG_BUF_SHIFT=22`**: Buffer de `dmesg` / `printk` quadruplicado para **4 MB** (o padrão é 1 MB), evitando que logs essenciais de boot ou falhas sejam sobrescritos rapidamente.
   - **`CONFIG_DYNAMIC_DEBUG=y`**: Permite ativar mensagens de debug em tempo de execução via `debugfs` (`/sys/kernel/debug/dynamic_debug/control`).
   - **`CONFIG_PRINTK_PROCESS=y`**: Identifica nos logs do kernel o nome e PID exato do processo responsável por cada evento.

3. **PStore (Persistent RAM Logging):**
   - **`CONFIG_PSTORE=y`**, **`CONFIG_PSTORE_CONSOLE=y`**, **`CONFIG_PSTORE_PMSG=y`**, **`CONFIG_PSTORE_RAM=y`**: Registra mensagens de console e eventos de usuários no buffer persistente de RAM.
   - **`CONFIG_PSTORE_DEFAULT_KMSG_BYTES=65536`**: Buffer de kmsg persistente aumentado para 64 KB para garantir captura de stack traces completos de pânico/kernel crash mesmo após reinicialização.
   - Arquivos preservados acessíveis em `/sys/fs/pstore/` após reboot.

4. **Failsafe Ativo:**
   - Mantido o `panic_to_recovery` para garantir que o aparelho entre no TWRP caso ocorra um pânico severo.

---

### Como Compilar

```bash
# Carregar o defconfig de debug
make CC=clang LLVM=1 nightkernel_debug_defconfig

# Compilar o kernel
make -j$(nproc) CC=clang LLVM=1 Image
```
