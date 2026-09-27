#!/bin/bash
set -x
exec > >(tee -a /var/log/tree-sync.log) 2>&1

echo "=== STARTING NIGHTKERNEL TREE SYNC WORKER $(date) ==="

ZONE=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone | awk -F/ '{print $NF}')
INSTANCE_NAME=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/name)
PROJECT_ID=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/project/project-id)
GH_TOKEN=$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/attributes/gh_token)
export GH_TOKEN="$GH_TOKEN"
export GITHUB_TOKEN="$GH_TOKEN"

cleanup() {
    echo "=== CLEANING UP INSTANCE $INSTANCE_NAME in $ZONE ==="
    gcloud compute instances delete "$INSTANCE_NAME" --zone="$ZONE" --project="$PROJECT_ID" --quiet || true
}
trap cleanup EXIT

# 1. Install dependencies
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y git curl patch rsync

# Configure git credentials
git config --global user.name "Multi-Forge"
git config --global user.email "cooprevisaude@gmail.com"
git config --global credential.helper store
echo "https://x-access-token:${GH_TOKEN}@github.com" > ~/.git-credentials
git config --global http.postBuffer 1048576000

# 2. Clone NightKernel-a14x
mkdir -p /work && cd /work
git clone https://x-access-token:${GH_TOKEN}@github.com/multi-forge/NightKernel-a14x.git repo
cd repo
git checkout main

# 3. Clone TWRP device tree into tree-recovery/
echo "=== IMPORTING TWRP DEVICE TREE ==="
rm -rf tree-recovery
git clone --depth=1 https://x-access-token:${GH_TOKEN}@github.com/multi-forge/android_device_samsung_a14x.git tree-recovery
rm -rf tree-recovery/.git

# 4. Clone and patch Kernel Tree into tree/
echo "=== PREPARING PATCHED KERNEL TREE ==="
rm -rf tree
git clone --depth=1 -b V-sd-perm https://github.com/physwizz/a146b-a146m.git tree
cd tree

# Apply Patch 1: Autonomous Recovery
sed -i 's/static char panic_str\[10\] = "panic";/static char panic_str\[10\] = "recovery";/' drivers/samsung/sec_reboot.c

cat << 'PROCEOF' >> kernel/reboot.c

/* ========================================================================== */
/* NightKernel Autonomous Recovery Interface                                  */
/* Allows unprivileged and programmatic reboot to TWRP without USB handshake  */
/* ========================================================================== */
#include <linux/proc_fs.h>
#include <linux/uaccess.h>

static ssize_t nightkernel_reboot_read(struct file *file, char __user *buf, size_t count, loff_t *ppos)
{
	const char *msg = "NightKernel Autonomous Recovery Interface\nUsage: echo 1 > /proc/nightkernel_reboot\n";
	return simple_read_from_buffer(buf, count, ppos, msg, strlen(msg));
}

static ssize_t nightkernel_reboot_write(struct file *file, const char __user *buf, size_t count, loff_t *ppos)
{
	char kbuf[32];
	size_t len = min(count, sizeof(kbuf) - 1);

	if (copy_from_user(kbuf, buf, len))
		return -EFAULT;
	kbuf[len] = '\0';

	if (strstr(kbuf, "1") || strstr(kbuf, "recovery")) {
		pr_emerg("NightKernel: Autonomous reboot to recovery requested!\n");
		kernel_restart("recovery");
	}
	return count;
}

static const struct proc_ops nightkernel_reboot_fops = {
	.proc_read = nightkernel_reboot_read,
	.proc_write = nightkernel_reboot_write,
};

static int __init nightkernel_reboot_init(void)
{
	struct proc_dir_entry *ent = proc_create("nightkernel_reboot", 0666, NULL, &nightkernel_reboot_fops);
	if (!ent)
		pr_err("NightKernel: Failed to create /proc/nightkernel_reboot\n");
	else
		pr_info("NightKernel: Autonomous recovery interface initialized (/proc/nightkernel_reboot)\n");
	return 0;
}
late_initcall(nightkernel_reboot_init);
PROCEOF

# Apply Patch 3: ReSukiSU + Safety
curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" | bash -s main
patch -p1 -d KernelSU < /work/repo/patches/03_resukisu_safety.patch || true

# Apply Patch 2: SuSFS 2.1.0
git clone --depth=1 -b gki-android13-5.15 https://gitlab.com/simonpunk/susfs4ksu.git /tmp/susfs_repo
cd /tmp/susfs_repo && git checkout 9f0415bb2c8fc581e93d384e09aba088bd36733a || true && cd /work/repo/tree
cp -rf /tmp/susfs_repo/kernel_patches/fs/* fs/
cp -rf /tmp/susfs_repo/kernel_patches/include/linux/* include/linux/
patch -p1 --forward < /tmp/susfs_repo/kernel_patches/50_add_susfs_in_gki-android13-5.15.patch || true
patch -p1 --forward < /work/repo/patches/02_susfs_fix_stock_a14.patch || true
rm -rf /tmp/susfs_repo

# Apply Patch 4 & 5: NTSync
patch -p1 --forward < /work/repo/patches/04_ntsync_base.patch || true
patch -p1 --forward < /work/repo/patches/05_ntsync_compat.patch || true

# Apply Patch 6: DroidSpaces
patch -p1 --forward < /work/repo/patches/06_droidspace.patch || true

# Apply Baseband Guard
curl -LSs https://github.com/vc-teahouse/Baseband-guard/raw/main/setup.sh | bash || true

# Apply Patch 7: KCAL
patch -p1 --forward < /work/repo/patches/07_kcal_dqe.patch || true

# Apply Patch 8: CRCs Disable
patch -p1 --forward < /work/repo/patches/08_crcs_disable.patch || true

# Clean up patch residue
find . -name "*.orig" -delete -o -name "*.rej" -delete
rm -rf .git

# Copy defconfig into place
cp /work/repo/configs/nightkernel_v1.2_defconfig arch/arm64/configs/nightkernel_v1.2_defconfig

# Return to repo root
cd /work/repo

# 5. Commit and push
echo "=== COMMITTING AND PUSHING TREES TO GITHUB ==="
git add tree tree-recovery
git commit -m "feat(tree): add production-booted patched kernel tree in tree/ and TWRP device tree in tree-recovery/"

echo "Rebasing against origin/main in case of remote changes..."
git pull --rebase origin main || true

echo "Pushing trees to GitHub..."
PUSH_SUCCESS=false
for i in 1 2 3; do
    echo "Push attempt $i/3..."
    if git push origin main; then
        PUSH_SUCCESS=true
        echo "=== GIT PUSH SUCCESSFUL ==="
        break
    else
        echo "Push attempt $i failed. Retrying in 10s..."
        sleep 10
    fi
done

if [ "$PUSH_SUCCESS" = "true" ]; then
    echo "=== TREES SYNCED SUCCESSFULLY $(date) ==="
else
    echo "=== ERROR: PUSH FAILED AFTER 3 ATTEMPTS ==="
    sleep 120
    exit 1
fi
