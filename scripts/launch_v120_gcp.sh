#!/data/data/com.termux/files/usr/bin/bash
set -e

PROJECT="stt-465818"
ZONE="us-central1-a"
INSTANCE_NAME="nightkernel-v12-$(date +%s)"
STARTUP_SCRIPT="/data/data/com.termux/files/home/a14x-workspace/NightKernel/scripts/startup_build_v120.sh"
GH_TOKEN=$(gh auth token)

echo "=== CREATING GCP WORKER FOR NIGHTKERNEL v1.2.0 ==="
echo "Project: $PROJECT"
echo "Zone: $ZONE"
echo "Instance: $INSTANCE_NAME"
echo "ccache: a14x-ccache attached"

gcloud compute instances create "$INSTANCE_NAME" \
  --project="$PROJECT" \
  --zone="$ZONE" \
  --machine-type="n2-standard-8" \
  --provisioning-model=STANDARD \
  --no-restart-on-failure \
  --image-family=ubuntu-2404-lts-amd64 \
  --image-project=ubuntu-os-cloud \
  --boot-disk-size=50GB \
  --boot-disk-type=pd-balanced \
  --boot-disk-auto-delete \
  --disk="name=a14x-ccache,device-name=a14x-ccache,mode=rw,auto-delete=no" \
  --scopes=cloud-platform \
  --metadata="gh_token=$GH_TOKEN" \
  --metadata-from-file="startup-script=$STARTUP_SCRIPT"

echo "=== NIGHTKERNEL v1.2.0 BUILD INSTANCE LAUNCHED ==="
echo "Instance: $INSTANCE_NAME"
