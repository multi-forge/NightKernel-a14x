#!/data/data/com.termux/files/usr/bin/bash
set -e

PROJECT="stt-465818"
ZONE="us-central1-a"
INSTANCE_NAME="nightkernel-treesync-$(date +%s)"
STARTUP_SCRIPT="/data/data/com.termux/files/home/a14x-workspace/NightKernel/scripts/startup_sync_trees.sh"
GH_TOKEN=$(gh auth token)

echo "=== LAUNCHING GCP WORKER FOR NIGHTKERNEL TREE SYNC ==="
echo "Project: $PROJECT"
echo "Zone: $ZONE"
echo "Instance: $INSTANCE_NAME"

gcloud compute instances create "$INSTANCE_NAME" \
  --project="$PROJECT" \
  --zone="$ZONE" \
  --machine-type="e2-standard-4" \
  --provisioning-model=SPOT \
  --instance-termination-action=DELETE \
  --no-restart-on-failure \
  --image-family=ubuntu-2404-lts-amd64 \
  --image-project=ubuntu-os-cloud \
  --boot-disk-size=40GB \
  --boot-disk-type=pd-balanced \
  --boot-disk-auto-delete \
  --scopes=cloud-platform \
  --metadata="gh_token=$GH_TOKEN" \
  --metadata-from-file="startup-script=$STARTUP_SCRIPT"

echo "=== INSTANCE $INSTANCE_NAME LAUNCHED SUCCESSFULLY ==="
