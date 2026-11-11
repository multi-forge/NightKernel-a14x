// SPDX-License-Identifier: GPL-2.0
/*
 * Boeffla Wakelock Blocker driver
 *
 * Fully safe for atomic & interrupt contexts via RCU lock-free reads.
 * Copyright (C) 2014-2016 Andi Paule <andi@boeffla.de>
 * RCU rework & stack frame elimination for Linux 5.15+ by NightKernel Team
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/miscdevice.h>
#include <linux/fs.h>
#include <linux/string.h>
#include <linux/slab.h>
#include <linux/rcupdate.h>
#include <linux/mutex.h>

#define BOEFFLA_WL_BLOCKER_VERSION "1.3.0-rcu"
#define WL_BUF_SIZE 2048
#define WL_NAME_MAX 64

struct wl_block_entry {
	struct list_head list;
	char name[WL_NAME_MAX];
};

struct wl_block_table {
	struct list_head head;
	struct rcu_head rcu;
	char raw_str[WL_BUF_SIZE];
};

static struct wl_block_table __rcu *global_wl_table;
static DEFINE_MUTEX(wl_config_mutex); /* Protects writes from process context */
static char default_wakelocks[WL_BUF_SIZE] = "wlan_pno_wl;bbd_wake_lock;wlan_extscan_wl;";
static int debug_mode = 0;

static void wl_block_table_free_rcu(struct rcu_head *rcu)
{
	struct wl_block_table *table = container_of(rcu, struct wl_block_table, rcu);
	struct wl_block_entry *entry, *tmp;

	list_for_each_entry_safe(entry, tmp, &table->head, list) {
		list_del(&entry->list);
		kfree(entry);
	}
	kfree(table);
}

/*
 * Fast, non-blocking, zero-stack-allocation wakelock check.
 * Safe to call from hard-IRQ, soft-IRQ, and spinlock contexts.
 */
bool boeffla_wl_blocker_is_blocked(const char *name)
{
	struct wl_block_table *table;
	struct wl_block_entry *entry;
	bool blocked = false;

	if (!name || !name[0])
		return false;

	rcu_read_lock();
	table = rcu_dereference(global_wl_table);
	if (table) {
		list_for_each_entry_rcu(entry, &table->head, list) {
			if (strcmp(entry->name, name) == 0) {
				blocked = true;
				break;
			}
		}
	}
	rcu_read_unlock();

	if (blocked && debug_mode)
		pr_info("Boeffla WL Blocker: blocked wakelock '%s'\n", name);

	return blocked;
}
EXPORT_SYMBOL_GPL(boeffla_wl_blocker_is_blocked);

static int update_wl_table_locked(const char *buf)
{
	struct wl_block_table *new_table, *old_table;
	char *tmp_buf, *pos, *token;

	new_table = kzalloc(sizeof(*new_table), GFP_KERNEL);
	if (!new_table)
		return -ENOMEM;

	INIT_LIST_HEAD(&new_table->head);
	strlcpy(new_table->raw_str, buf, sizeof(new_table->raw_str));
	strim(new_table->raw_str);

	if (new_table->raw_str[0]) {
		tmp_buf = kstrdup(new_table->raw_str, GFP_KERNEL);
		if (tmp_buf) {
			pos = tmp_buf;
			while ((token = strsep(&pos, ";")) != NULL) {
				token = strim(token);
				if (token[0]) {
					struct wl_block_entry *entry = kzalloc(sizeof(*entry), GFP_KERNEL);
					if (entry) {
						strlcpy(entry->name, token, sizeof(entry->name));
						list_add_tail(&entry->list, &new_table->head);
					}
				}
			}
			kfree(tmp_buf);
		}
	}

	old_table = rcu_dereference_protected(global_wl_table, mutex_is_locked(&wl_config_mutex));
	rcu_assign_pointer(global_wl_table, new_table);

	if (old_table)
		call_rcu(&old_table->rcu, wl_block_table_free_rcu);

	return 0;
}

static ssize_t version_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%s\n", BOEFFLA_WL_BLOCKER_VERSION);
}

static ssize_t wakelock_blocker_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	struct wl_block_table *table;
	ssize_t ret = 0;

	rcu_read_lock();
	table = rcu_dereference(global_wl_table);
	if (table && table->raw_str[0])
		ret = scnprintf(buf, PAGE_SIZE, "%s\n", table->raw_str);
	else
		ret = scnprintf(buf, PAGE_SIZE, "\n");
	rcu_read_unlock();

	return ret;
}

static ssize_t wakelock_blocker_store(struct device *dev, struct device_attribute *attr,
				     const char *buf, size_t count)
{
	int ret;

	mutex_lock(&wl_config_mutex);
	ret = update_wl_table_locked(buf);
	mutex_unlock(&wl_config_mutex);

	if (ret)
		return ret;

	if (debug_mode)
		pr_info("Boeffla WL Blocker: updated list via RCU\n");

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

	/* Initialize empty table */
	mutex_lock(&wl_config_mutex);
	update_wl_table_locked("");
	mutex_unlock(&wl_config_mutex);

	pr_info("Boeffla WL Blocker v%s initialized (RCU enabled)\n", BOEFFLA_WL_BLOCKER_VERSION);
	return 0;
}

static void __exit boeffla_wl_blocker_exit(void)
{
	struct wl_block_table *table;

	sysfs_remove_group(&boeffla_wl_blocker_dev.this_device->kobj,
			   &boeffla_wl_blocker_group);
	misc_deregister(&boeffla_wl_blocker_dev);

	mutex_lock(&wl_config_mutex);
	table = rcu_dereference_protected(global_wl_table, mutex_is_locked(&wl_config_mutex));
	RCU_INIT_POINTER(global_wl_table, NULL);
	mutex_unlock(&wl_config_mutex);

	if (table) {
		synchronize_rcu();
		wl_block_table_free_rcu(&table->rcu);
	}
}

module_init(boeffla_wl_blocker_init);
module_exit(boeffla_wl_blocker_exit);

MODULE_LICENSE("GPL v2");
MODULE_AUTHOR("Andi Paule <andi@boeffla.de>, NightKernel Team");
MODULE_DESCRIPTION("Boeffla Wakelock Blocker driver (RCU enabled, atomic safe)");
MODULE_VERSION(BOEFFLA_WL_BLOCKER_VERSION);
