#!/data/data/com.termux/files/usr/bin/bash
set -e

PROJECT="stt-465818"
ZONE="us-central1-a"
INSTANCE_NAME="nightkernel-v123c22f9-$(date +%s)"
STARTUP_SCRIPT="/data/data/com.termux/files/home/a14x-workspace/NightKernel/scripts/startup_build_v123c22f9.sh"

echo "=== LAUNCHING GCP WORKER FOR NIGHTKERNEL v1.2.3-clang22 (f9) ==="
echo "Project: $PROJECT"
echo "Zone: $ZONE"
echo "Instance: $INSTANCE_NAME"
echo "Machine: n2-standard-8 (8 vCPUs, 32GB RAM SPOT)"
echo "Target: Linux 5.15.197 (V-ue Binary E) + Clang 22 + ThinLTO + LZ4 ZRAM + FRAME_WARN=3072"

gcloud compute instances create "$INSTANCE_NAME" \
  --project="$PROJECT" \
  --zone="$ZONE" \
  --machine-type="n2-standard-8" \
  --provisioning-model=SPOT \
  --instance-termination-action=DELETE \
  --no-restart-on-failure \
  --image-family=ubuntu-2404-lts-amd64 \
  --image-project=ubuntu-os-cloud \
  --boot-disk-size=30GB \
  --boot-disk-type=pd-balanced \
  --boot-disk-auto-delete \
  --disk="name=a14x-ccache,device-name=a14x-ccache,mode=rw,auto-delete=no" \
  --scopes=cloud-platform \
  --metadata-from-file="startup-script=$STARTUP_SCRIPT"

echo "=== NIGHTKERNEL v1.2.3-clang22 BUILD INSTANCE LAUNCHED: $INSTANCE_NAME ==="
