#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

DEST="${1:-$HOME/nightkernel_v123_clang22}"
mkdir -p "$DEST"

export CLOUDSDK_CORE_PROJECT=stt-465818
echo "=== BAIXANDO ARTEFATOS DO NIGHTKERNEL v1.2.3-clang22 PARA $DEST ==="
gcloud storage cp gs://laya-onnx-stt-465818/nightkernel-v123-clang22/artifacts/* "$DEST/"

cd "$DEST"
echo "=== VERIFICANDO SHA256 ==="
sha256sum -c sha256sums.txt
echo "=== DOWNLOAD E INTEGRIDADE CONCLUÍDOS COM SUCESSO! ==="
ls -lh "$DEST"
