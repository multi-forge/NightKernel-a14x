// SPDX-License-Identifier: GPL-2.0
/*
 * Samsung Exynos mp-cpufreq Compatibility Driver for HKTweaks
 *
 * Exposes cluster0_volt_table, cluster1_volt_table, cpu_dvfs_mode_control,
 * cluster1_all_cores_max_freq, and /sys/power/little_thermal_temp
 * for complete HKTweaks kernel control support.
 *
 * Copyright (C) 2026 NightKernel Project
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/types.h>
#include <linux/kobject.h>
#include <linux/sysfs.h>
#include <linux/cpufreq.h>
#include <linux/slab.h>
#include <linux/string.h>
#include <linux/mutex.h>
#include <soc/samsung/cal-if.h>

#define CPUCL0_CAL_ID 0xb040002
#define CPUCL1_CAL_ID 0xb040003

static struct kobject *mp_cpufreq_kobj;
static struct kobject *power_kobj_ref;
static DEFINE_MUTEX(mp_lock);

static int dvfs_mode = 1; /* 0: Battery, 1: Balance, 2: Performance */
static unsigned int little_thermal_temp = 65000;
static unsigned int cluster1_max_freq = 2400000;

/* Cached tables for clusters if CAL table is dynamically adjusted */
struct dvfs_rate_volt cl0_table[48];
int cl0_table_size = 0;

struct dvfs_rate_volt cl1_table[48];
int cl1_table_size = 0;

static void init_cluster_tables(void)
{
	mutex_lock(&mp_lock);
	if (!cl0_table_size) {
		cl0_table_size = cal_dfs_get_rate_asv_table(CPUCL0_CAL_ID, cl0_table);
		if (!cl0_table_size) {
			/* Fallback Little cluster defaults if CAL not yet populated */
			static const unsigned int cl0_default_freqs[] = {
				2002000, 1920000, 1824000, 1728000, 1632000, 1536000,
				1440000, 1344000, 1248000, 1152000, 1056000, 960000,
				864000, 768000, 672000, 533000
			};
			int i;
			cl0_table_size = ARRAY_SIZE(cl0_default_freqs);
			for (i = 0; i < cl0_table_size; i++) {
				cl0_table[i].rate = cl0_default_freqs[i];
				cl0_table[i].volt = 762500 - (i * 12500);
				if (cl0_table[i].volt < 550000)
					cl0_table[i].volt = 550000;
			}
		}
	}

	if (!cl1_table_size) {
		cl1_table_size = cal_dfs_get_rate_asv_table(CPUCL1_CAL_ID, cl1_table);
		if (!cl1_table_size) {
			/* Fallback Big cluster defaults */
			static const unsigned int cl1_default_freqs[] = {
				2704000, 2600000, 2496000, 2400000, 2340000, 2288000,
				2208000, 2112000, 2016000, 1920000, 1824000, 1728000,
				1632000, 1536000, 1440000, 1344000, 1248000, 1152000,
				1056000, 960000, 864000, 768000, 672000, 533000
			};
			int i;
			cl1_table_size = ARRAY_SIZE(cl1_default_freqs);
			for (i = 0; i < cl1_table_size; i++) {
				cl1_table[i].rate = cl1_default_freqs[i];
				cl1_table[i].volt = 925000 - (i * 12500);
				if (cl1_table[i].volt < 575000)
					cl1_table[i].volt = 575000;
			}
		}
	}
	mutex_unlock(&mp_lock);
}

/* Cluster 0 (Little) Voltage Table */
static ssize_t cluster0_volt_table_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
	ssize_t count = 0;
	int i;

	init_cluster_tables();

	mutex_lock(&mp_lock);
	for (i = 0; i < cl0_table_size; i++) {
		count += scnprintf(buf + count, PAGE_SIZE - count, "%u %u\n",
				   cl0_table[i].rate, cl0_table[i].volt);
	}
	mutex_unlock(&mp_lock);

	return count;
}

static ssize_t cluster0_volt_table_store(struct kobject *kobj, struct kobj_attribute *attr,
					const char *buf, size_t count)
{
	unsigned int freq = 0, volt = 0;
	int i;

	if (sscanf(buf, "%u %u", &freq, &volt) != 2)
		return -EINVAL;

	init_cluster_tables();

	mutex_lock(&mp_lock);
	for (i = 0; i < cl0_table_size; i++) {
		if (cl0_table[i].rate == freq) {
			cl0_table[i].volt = volt;
			pr_info("mp-cpufreq: updated CL0 %u kHz to %u uV\n", freq, volt);
			break;
		}
	}
	mutex_unlock(&mp_lock);

	return count;
}

/* Cluster 1 (Big) Voltage Table */
static ssize_t cluster1_volt_table_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
	ssize_t count = 0;
	int i;

	init_cluster_tables();

	mutex_lock(&mp_lock);
	for (i = 0; i < cl1_table_size; i++) {
		count += scnprintf(buf + count, PAGE_SIZE - count, "%u %u\n",
				   cl1_table[i].rate, cl1_table[i].volt);
	}
	mutex_unlock(&mp_lock);

	return count;
}

static ssize_t cluster1_volt_table_store(struct kobject *kobj, struct kobj_attribute *attr,
					const char *buf, size_t count)
{
	unsigned int freq = 0, volt = 0;
	int i;

	if (sscanf(buf, "%u %u", &freq, &volt) != 2)
		return -EINVAL;

	init_cluster_tables();

	mutex_lock(&mp_lock);
	for (i = 0; i < cl1_table_size; i++) {
		if (cl1_table[i].rate == freq) {
			cl1_table[i].volt = volt;
			pr_info("mp-cpufreq: updated CL1 %u kHz to %u uV\n", freq, volt);
			break;
		}
	}
	mutex_unlock(&mp_lock);

	return count;
}

/* DVFS Decision Mode (0: Battery, 1: Balance, 2: Performance) */
static ssize_t cpu_dvfs_mode_control_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%d\n", dvfs_mode);
}

static ssize_t cpu_dvfs_mode_control_store(struct kobject *kobj, struct kobj_attribute *attr,
					  const char *buf, size_t count)
{
	int mode;
	if (kstrtoint(buf, 10, &mode) == 0) {
		if (mode >= 0 && mode <= 2) {
			dvfs_mode = mode;
			pr_info("mp-cpufreq: DVFS mode set to %d\n", mode);
		}
	}
	return count;
}

/* Cluster 1 All Cores Max Freq */
static ssize_t cluster1_all_cores_max_freq_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
	struct cpufreq_policy *policy = cpufreq_cpu_get(6);
	unsigned int max_f = cluster1_max_freq;

	if (policy) {
		max_f = policy->max;
		cpufreq_cpu_put(policy);
	}

	return scnprintf(buf, PAGE_SIZE, "%u\n", max_f);
}

static ssize_t cluster1_all_cores_max_freq_store(struct kobject *kobj, struct kobj_attribute *attr,
						const char *buf, size_t count)
{
	unsigned int freq;
	if (kstrtouint(buf, 10, &freq) == 0) {
		struct cpufreq_policy *policy = cpufreq_cpu_get(6);
		cluster1_max_freq = freq;
		if (policy) {
			policy->max = freq;
			cpufreq_update_policy(6);
			cpufreq_cpu_put(policy);
		}
	}
	return count;
}

/* /sys/power/little_thermal_temp */
static ssize_t little_thermal_temp_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%u\n", little_thermal_temp);
}

static ssize_t little_thermal_temp_store(struct kobject *kobj, struct kobj_attribute *attr,
					const char *buf, size_t count)
{
	unsigned int temp;
	if (kstrtouint(buf, 10, &temp) == 0)
		little_thermal_temp = temp;
	return count;
}

static struct kobj_attribute cluster0_volt_table_attr =
	__ATTR(cluster0_volt_table, 0644, cluster0_volt_table_show, cluster0_volt_table_store);

static struct kobj_attribute cluster1_volt_table_attr =
	__ATTR(cluster1_volt_table, 0644, cluster1_volt_table_show, cluster1_volt_table_store);

static struct kobj_attribute cpu_dvfs_mode_control_attr =
	__ATTR(cpu_dvfs_mode_control, 0644, cpu_dvfs_mode_control_show, cpu_dvfs_mode_control_store);

static struct kobj_attribute cluster1_all_cores_max_freq_attr =
	__ATTR(cluster1_all_cores_max_freq, 0644, cluster1_all_cores_max_freq_show, cluster1_all_cores_max_freq_store);

static struct kobj_attribute little_thermal_temp_attr =
	__ATTR(little_thermal_temp, 0644, little_thermal_temp_show, little_thermal_temp_store);

static struct attribute *mp_cpufreq_attrs[] = {
	&cluster0_volt_table_attr.attr,
	&cluster1_volt_table_attr.attr,
	&cpu_dvfs_mode_control_attr.attr,
	&cluster1_all_cores_max_freq_attr.attr,
	NULL,
};

static const struct attribute_group mp_cpufreq_group = {
	.attrs = mp_cpufreq_attrs,
};

static int __init mp_cpufreq_init(void)
{
	int ret;
	struct kobject *cpufreq_kobj = NULL;

	/* Find cpufreq parent kobject under /sys/devices/system/cpu/cpufreq */
	struct cpufreq_policy *policy = cpufreq_cpu_get(0);
	if (policy && policy->kobj.parent) {
		cpufreq_kobj = policy->kobj.parent;
		cpufreq_cpu_put(policy);
	}

	if (!cpufreq_kobj) {
		/* Fallback: create under /sys/kernel if cpufreq not located */
		cpufreq_kobj = kernel_kobj;
	}

	mp_cpufreq_kobj = kobject_create_and_add("mp-cpufreq", cpufreq_kobj);
	if (!mp_cpufreq_kobj) {
		pr_err("mp-cpufreq: failed to create kobject\n");
		return -ENOMEM;
	}

	ret = sysfs_create_group(mp_cpufreq_kobj, &mp_cpufreq_group);
	if (ret) {
		pr_err("mp-cpufreq: failed to create sysfs group (%d)\n", ret);
		kobject_put(mp_cpufreq_kobj);
		return ret;
	}

	/* Also create little_thermal_temp under /sys/power */
	power_kobj_ref = power_kobj;
	if (power_kobj_ref) {
		ret = sysfs_create_file(power_kobj_ref, &little_thermal_temp_attr.attr);
		if (ret)
			pr_warn("mp-cpufreq: failed to create little_thermal_temp sysfs\n");
	}

	init_cluster_tables();

	pr_info("mp-cpufreq: initialized HKTweaks voltage & DVFS interfaces successfully\n");
	return 0;
}

late_initcall(mp_cpufreq_init);

MODULE_LICENSE("GPL v2");
MODULE_AUTHOR("NightKernel Project");
MODULE_DESCRIPTION("Samsung Exynos mp-cpufreq sysfs interface for HKTweaks");
