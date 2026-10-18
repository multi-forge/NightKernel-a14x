#!/data/data/com.termux/files/usr/bin/bash
set -e

PROJECT="stt-465818"
ZONE="us-central1-a"
INSTANCE_NAME="nightkernel-v210-$(date +%s)"
STARTUP_SCRIPT="/data/data/com.termux/files/home/a14x-workspace/NightKernel/scripts/startup_build_v210_clang22.sh"

echo "=== LAUNCHING GCP WORKER FOR NIGHTKERNEL v2.1.0 ==="
echo "Project: $PROJECT"
echo "Zone: $ZONE"
echo "Instance: $INSTANCE_NAME"
echo "Machine: n2-custom-10-40960 (10 vCPUs, 40GB RAM SPOT)"
echo "Target: Linux 5.15.221 + Clang 22 + ThinLTO + 30GB RAM tmpfs + QEMU Sanity Test"

gcloud compute instances create "$INSTANCE_NAME" \
  --project="$PROJECT" \
  --zone="$ZONE" \
  --machine-type="n2-custom-10-40960" \
  --provisioning-model=SPOT \
  --instance-termination-action=STOP \
  --no-restart-on-failure \
  --image-family=ubuntu-2404-lts-amd64 \
  --image-project=ubuntu-os-cloud \
  --boot-disk-size=35GB \
  --boot-disk-type=pd-balanced \
  --boot-disk-auto-delete \
  --disk="name=a14x-ccache,device-name=a14x-ccache,mode=rw,auto-delete=no" \
  --scopes=cloud-platform \
  --metadata-from-file="startup-script=$STARTUP_SCRIPT"

echo "=== NIGHTKERNEL v2.1.0 BUILD INSTANCE LAUNCHED: $INSTANCE_NAME ==="
