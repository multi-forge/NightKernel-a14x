// SPDX-License-Identifier: GPL-2.0
/*
 * Boeffla Wakelock Blocker driver
 *
 * Copyright (C) 2014-2016 Andi Paule <andi@boeffla.de>
 * Adapted for NightKernel / Exynos 1330
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/types.h>
#include <linux/device.h>
#include <linux/miscdevice.h>
#include <linux/fs.h>
#include <linux/slab.h>
#include <linux/string.h>
#include <linux/mutex.h>

#define BOEFFLA_WL_BLOCKER_VERSION "1.1.0"
#define WL_BUF_SIZE 2048

static char blocked_wakelocks[WL_BUF_SIZE] = "";
static char default_wakelocks[WL_BUF_SIZE] = "wlan_pno_wl;bbd_wake_lock;wlan_extscan_wl;";
static int debug_mode = 0;
static DEFINE_MUTEX(wl_lock);

bool boeffla_wl_blocker_is_blocked(const char *name)
{
	char *pos, *token;
	char temp_buf[WL_BUF_SIZE];
	bool blocked = false;

	if (!name || !name[0] || !blocked_wakelocks[0])
		return false;

	mutex_lock(&wl_lock);
	strlcpy(temp_buf, blocked_wakelocks, sizeof(temp_buf));
	mutex_unlock(&wl_lock);

	pos = temp_buf;
	while ((token = strsep(&pos, ";")) != NULL) {
		token = strim(token);
		if (token[0] && strcmp(token, name) == 0) {
			blocked = true;
			if (debug_mode)
				pr_info("Boeffla WL Blocker: blocked wakelock '%s'\n", name);
			break;
		}
	}

	return blocked;
}
EXPORT_SYMBOL_GPL(boeffla_wl_blocker_is_blocked);

static ssize_t version_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%s\n", BOEFFLA_WL_BLOCKER_VERSION);
}

static ssize_t wakelock_blocker_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	ssize_t ret;
	mutex_lock(&wl_lock);
	ret = scnprintf(buf, PAGE_SIZE, "%s\n", blocked_wakelocks);
	mutex_unlock(&wl_lock);
	return ret;
}

static ssize_t wakelock_blocker_store(struct device *dev, struct device_attribute *attr,
				     const char *buf, size_t count)
{
	mutex_lock(&wl_lock);
	strlcpy(blocked_wakelocks, buf, sizeof(blocked_wakelocks));
	strim(blocked_wakelocks);
	mutex_unlock(&wl_lock);

	if (debug_mode)
		pr_info("Boeffla WL Blocker: updated list to '%s'\n", blocked_wakelocks);

	return count;
}

static ssize_t wakelock_blocker_default_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%s\n", default_wakelocks);
}

static ssize_t debug_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%d\n", debug_mode);
}

static ssize_t debug_store(struct device *dev, struct device_attribute *attr,
			  const char *buf, size_t count)
{
	int val;
	if (kstrtoint(buf, 10, &val) == 0)
		debug_mode = (val != 0);
	return count;
}

static DEVICE_ATTR_RO(version);
static DEVICE_ATTR_RW(wakelock_blocker);
static DEVICE_ATTR_RO(wakelock_blocker_default);
static DEVICE_ATTR_RW(debug);

static struct attribute *boeffla_wl_blocker_attrs[] = {
	&dev_attr_version.attr,
	&dev_attr_wakelock_blocker.attr,
	&dev_attr_wakelock_blocker_default.attr,
	&dev_attr_debug.attr,
	NULL,
};

static const struct attribute_group boeffla_wl_blocker_group = {
	.attrs = boeffla_wl_blocker_attrs,
};

static struct miscdevice boeffla_wl_blocker_dev = {
	.minor = MISC_DYNAMIC_MINOR,
	.name = "boeffla_wakelock_blocker",
};

static int __init boeffla_wl_blocker_init(void)
{
	int ret;

	ret = misc_register(&boeffla_wl_blocker_dev);
	if (ret) {
		pr_err("Boeffla WL Blocker: failed to register misc device (%d)\n", ret);
		return ret;
	}

	ret = sysfs_create_group(&boeffla_wl_blocker_dev.this_device->kobj,
				 &boeffla_wl_blocker_group);
	if (ret) {
		pr_err("Boeffla WL Blocker: failed to create sysfs group (%d)\n", ret);
		misc_deregister(&boeffla_wl_blocker_dev);
		return ret;
	}

	pr_info("Boeffla WL Blocker v%s initialized\n", BOEFFLA_WL_BLOCKER_VERSION);
	return 0;
}

static void __exit boeffla_wl_blocker_exit(void)
{
	sysfs_remove_group(&boeffla_wl_blocker_dev.this_device->kobj,
			   &boeffla_wl_blocker_group);
	misc_deregister(&boeffla_wl_blocker_dev);
}

module_init(boeffla_wl_blocker_init);
module_exit(boeffla_wl_blocker_exit);

MODULE_LICENSE("GPL v2");
MODULE_AUTHOR("Andi Paule <andi@boeffla.de>");
MODULE_DESCRIPTION("Boeffla Wakelock Blocker driver");
MODULE_VERSION(BOEFFLA_WL_BLOCKER_VERSION);
