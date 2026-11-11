// SPDX-License-Identifier: GPL-2.0
/*
 * Samsung Exynos mp-cpufreq Compatibility & Hardware Tuning Driver
 *
 * Implements direct in-kernel hardware undervolt (ACPM IPC) and thermal
 * throttling relaxation for Samsung Galaxy A14 5G (Exynos 1330 / s5e8535),
 * while preserving complete sysfs interfaces for HKTweaks and power management.
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
#include <linux/thermal.h>
#include <linux/workqueue.h>
#include <soc/samsung/cal-if.h>

#define CPUCL0_CAL_ID 0xb040002
#define CPUCL1_CAL_ID 0xb040003
#define G3D_CAL_ID    0xb040008

static struct kobject *mp_cpufreq_kobj;
static struct kobject *power_kobj_ref;
static DEFINE_MUTEX(mp_lock);

static int dvfs_mode = 1; /* 0: Battery, 1: Balance, 2: Performance */
static unsigned int little_thermal_temp = 65000;
static unsigned int cluster1_max_freq = 2400000;

/* Hardware Undervolt Percent Margins (Safe: CL0 -3%, CL1 -2%, G3D -2%) */
static int cluster0_volt_margin = -3;
static int cluster1_volt_margin = -2;
static int gpu_volt_margin = -2;

/* Relaxed Thermal Trip Points (mC: GPU 72C/82C, BIG 78C/90C, LITTLE 78C/90C) */
static unsigned int gpu_thermal_trip1 = 72000;
static unsigned int gpu_thermal_trip2 = 82000;
static unsigned int big_thermal_trip1 = 78000;
static unsigned int big_thermal_trip2 = 90000;
static unsigned int little_thermal_trip1 = 78000;
static unsigned int little_thermal_trip2 = 90000;

static struct delayed_work mp_init_work;

/* Cached tables for clusters if CAL table is dynamically adjusted */
struct dvfs_rate_volt cl0_table[48];
int cl0_table_size = 0;

struct dvfs_rate_volt cl1_table[48];
int cl1_table_size = 0;

/* Apply hardware undervolt margins directly to Exynos ACPM */
static void apply_hardware_volt_margins(void)
{
	void (*cal_set_margin_fn)(unsigned int id, int volt) = NULL;

	cal_set_margin_fn = __symbol_get("cal_dfs_set_volt_margin");
	if (cal_set_margin_fn) {
		cal_set_margin_fn(CPUCL1_CAL_ID, cluster1_volt_margin);
		cal_set_margin_fn(CPUCL0_CAL_ID, cluster0_volt_margin);
		cal_set_margin_fn(G3D_CAL_ID, gpu_volt_margin);
		__symbol_put("cal_dfs_set_volt_margin");
		pr_info("mp-cpufreq: hardware undervolt applied via ACPM: CL1=%d%% CL0=%d%% GPU=%d%%\n",
			cluster1_volt_margin, cluster0_volt_margin, gpu_volt_margin);
	} else {
		pr_debug("mp-cpufreq: cal_dfs_set_volt_margin symbol not yet available\n");
	}
}

/* Apply direct in-kernel thermal trip points to G3D, BIG, and LITTLE zones */
static void apply_thermal_trip_points(void)
{
	struct thermal_zone_device *tz;

	tz = thermal_zone_get_zone_by_name("G3D");
	if (tz && tz->ops && tz->ops->set_trip_temp) {
		tz->ops->set_trip_temp(tz, 1, gpu_thermal_trip1);
		tz->ops->set_trip_temp(tz, 2, gpu_thermal_trip2);
		pr_info("mp-cpufreq: G3D thermal trips configured to %u / %u mC\n",
			gpu_thermal_trip1, gpu_thermal_trip2);
	}

	tz = thermal_zone_get_zone_by_name("BIG");
	if (tz && tz->ops && tz->ops->set_trip_temp) {
		tz->ops->set_trip_temp(tz, 1, big_thermal_trip1);
		tz->ops->set_trip_temp(tz, 2, big_thermal_trip2);
		pr_info("mp-cpufreq: BIG thermal trips configured to %u / %u mC\n",
			big_thermal_trip1, big_thermal_trip2);
	}

	tz = thermal_zone_get_zone_by_name("LITTLE");
	if (tz && tz->ops && tz->ops->set_trip_temp) {
		tz->ops->set_trip_temp(tz, 1, little_thermal_trip1);
		tz->ops->set_trip_temp(tz, 2, little_thermal_trip2);
		pr_info("mp-cpufreq: LITTLE thermal trips configured to %u / %u mC\n",
			little_thermal_trip1, little_thermal_trip2);
	}
}

static void mp_delayed_work_fn(struct work_struct *work)
{
	apply_hardware_volt_margins();
	apply_thermal_trip_points();
}

static void init_cluster_tables(void)
{
	mutex_lock(&mp_lock);
	if (!cl0_table_size) {
		struct cpufreq_policy *policy0 = cpufreq_cpu_get(0);
		if (policy0) {
			if (policy0->freq_table) {
				struct cpufreq_frequency_table *pos;
				int idx = 0;
				cpufreq_for_each_valid_entry(pos, policy0->freq_table) {
					if (idx < 48) {
						cl0_table[idx].rate = pos->frequency;
						cl0_table[idx].volt = 762500 - (idx * 12500);
						if (cl0_table[idx].volt < 550000)
							cl0_table[idx].volt = 550000;
						idx++;
					}
				}
				cl0_table_size = idx;
			}
			cpufreq_cpu_put(policy0);
		}
		if (!cl0_table_size) {
			/* Fallback Little cluster defaults if cpufreq not yet populated */
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
		struct cpufreq_policy *policy6 = cpufreq_cpu_get(6);
		if (policy6) {
			if (policy6->freq_table) {
				struct cpufreq_frequency_table *pos;
				int idx = 0;
				cpufreq_for_each_valid_entry(pos, policy6->freq_table) {
					if (idx < 48) {
						cl1_table[idx].rate = pos->frequency;
						cl1_table[idx].volt = 925000 - (idx * 12500);
						if (cl1_table[idx].volt < 575000)
							cl1_table[idx].volt = 575000;
						idx++;
					}
				}
				cl1_table_size = idx;
			}
			cpufreq_cpu_put(policy6);
		}
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

/* Hardware Undervolt Margin Sysfs Controls */
static ssize_t cluster0_volt_margin_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%d\n", cluster0_volt_margin);
}

static ssize_t cluster0_volt_margin_store(struct kobject *kobj, struct kobj_attribute *attr,
					 const char *buf, size_t count)
{
	int val;
	if (kstrtoint(buf, 10, &val) == 0) {
		if (val >= -100 && val <= 100) {
			cluster0_volt_margin = val;
			apply_hardware_volt_margins();
		}
	}
	return count;
}

static ssize_t cluster1_volt_margin_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%d\n", cluster1_volt_margin);
}

static ssize_t cluster1_volt_margin_store(struct kobject *kobj, struct kobj_attribute *attr,
					 const char *buf, size_t count)
{
	int val;
	if (kstrtoint(buf, 10, &val) == 0) {
		if (val >= -100 && val <= 100) {
			cluster1_volt_margin = val;
			apply_hardware_volt_margins();
		}
	}
	return count;
}

static ssize_t gpu_volt_margin_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%d\n", gpu_volt_margin);
}

static ssize_t gpu_volt_margin_store(struct kobject *kobj, struct kobj_attribute *attr,
				    const char *buf, size_t count)
{
	int val;
	if (kstrtoint(buf, 10, &val) == 0) {
		if (val >= -100 && val <= 100) {
			gpu_volt_margin = val;
			apply_hardware_volt_margins();
		}
	}
	return count;
}

/* Thermal Trip Point Sysfs Controls */
static ssize_t gpu_thermal_trip1_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%u\n", gpu_thermal_trip1);
}

static ssize_t gpu_thermal_trip1_store(struct kobject *kobj, struct kobj_attribute *attr,
				      const char *buf, size_t count)
{
	unsigned int val;
	if (kstrtouint(buf, 10, &val) == 0) {
		gpu_thermal_trip1 = val;
		apply_thermal_trip_points();
	}
	return count;
}

static ssize_t gpu_thermal_trip2_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%u\n", gpu_thermal_trip2);
}

static ssize_t gpu_thermal_trip2_store(struct kobject *kobj, struct kobj_attribute *attr,
				      const char *buf, size_t count)
{
	unsigned int val;
	if (kstrtouint(buf, 10, &val) == 0) {
		gpu_thermal_trip2 = val;
		apply_thermal_trip_points();
	}
	return count;
}

static ssize_t big_thermal_trip1_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%u\n", big_thermal_trip1);
}

static ssize_t big_thermal_trip1_store(struct kobject *kobj, struct kobj_attribute *attr,
				      const char *buf, size_t count)
{
	unsigned int val;
	if (kstrtouint(buf, 10, &val) == 0) {
		big_thermal_trip1 = val;
		apply_thermal_trip_points();
	}
	return count;
}

static ssize_t big_thermal_trip2_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%u\n", big_thermal_trip2);
}

static ssize_t big_thermal_trip2_store(struct kobject *kobj, struct kobj_attribute *attr,
				      const char *buf, size_t count)
{
	unsigned int val;
	if (kstrtouint(buf, 10, &val) == 0) {
		big_thermal_trip2 = val;
		apply_thermal_trip_points();
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

static struct kobj_attribute cluster0_volt_margin_attr =
	__ATTR(cluster0_volt_margin, 0644, cluster0_volt_margin_show, cluster0_volt_margin_store);

static struct kobj_attribute cluster1_volt_margin_attr =
	__ATTR(cluster1_volt_margin, 0644, cluster1_volt_margin_show, cluster1_volt_margin_store);

static struct kobj_attribute gpu_volt_margin_attr =
	__ATTR(gpu_volt_margin, 0644, gpu_volt_margin_show, gpu_volt_margin_store);

static struct kobj_attribute gpu_thermal_trip1_attr =
	__ATTR(gpu_thermal_trip1, 0644, gpu_thermal_trip1_show, gpu_thermal_trip1_store);

static struct kobj_attribute gpu_thermal_trip2_attr =
	__ATTR(gpu_thermal_trip2, 0644, gpu_thermal_trip2_show, gpu_thermal_trip2_store);

static struct kobj_attribute big_thermal_trip1_attr =
	__ATTR(big_thermal_trip1, 0644, big_thermal_trip1_show, big_thermal_trip1_store);

static struct kobj_attribute big_thermal_trip2_attr =
	__ATTR(big_thermal_trip2, 0644, big_thermal_trip2_show, big_thermal_trip2_store);

static struct kobj_attribute little_thermal_temp_attr =
	__ATTR(little_thermal_temp, 0644, little_thermal_temp_show, little_thermal_temp_store);

static struct attribute *mp_cpufreq_attrs[] = {
	&cluster0_volt_table_attr.attr,
	&cluster1_volt_table_attr.attr,
	&cpu_dvfs_mode_control_attr.attr,
	&cluster1_all_cores_max_freq_attr.attr,
	&cluster0_volt_margin_attr.attr,
	&cluster1_volt_margin_attr.attr,
	&gpu_volt_margin_attr.attr,
	&gpu_thermal_trip1_attr.attr,
	&gpu_thermal_trip2_attr.attr,
	&big_thermal_trip1_attr.attr,
	&big_thermal_trip2_attr.attr,
	NULL,
};

static const struct attribute_group mp_cpufreq_group = {
	.attrs = mp_cpufreq_attrs,
};

extern struct kobject *cpufreq_global_kobject;

static int __init mp_cpufreq_init(void)
{
	int ret;
	struct kobject *cpufreq_kobj = cpufreq_global_kobject;

	if (!cpufreq_kobj) {
		/* Fallback: try from cpu0 policy parent if available */
		struct cpufreq_policy *policy = cpufreq_cpu_get(0);
		if (policy && policy->kobj.parent) {
			cpufreq_kobj = policy->kobj.parent;
			cpufreq_cpu_put(policy);
		}
	}

	if (!cpufreq_kobj)
		cpufreq_kobj = kernel_kobj;

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

	/* Also create symlink in /sys/kernel/mp-cpufreq for compatibility */
	sysfs_create_link(kernel_kobj, mp_cpufreq_kobj, "mp-cpufreq");

	/* Also create little_thermal_temp under /sys/power */
	power_kobj_ref = power_kobj;
	if (power_kobj_ref) {
		ret = sysfs_create_file(power_kobj_ref, &little_thermal_temp_attr.attr);
		if (ret)
			pr_warn("mp-cpufreq: failed to create little_thermal_temp sysfs\n");
	}

	init_cluster_tables();

	/* Schedule delayed hardware undervolt and thermal trip enforcement */
	INIT_DELAYED_WORK(&mp_init_work, mp_delayed_work_fn);
	schedule_delayed_work(&mp_init_work, msecs_to_jiffies(4000));

	pr_info("mp-cpufreq: initialized in-kernel undervolt, thermal trips, and HKTweaks interfaces successfully\n");
	return 0;
}

late_initcall(mp_cpufreq_init);

MODULE_LICENSE("GPL v2");
MODULE_AUTHOR("NightKernel Project");
MODULE_DESCRIPTION("Samsung Exynos mp-cpufreq in-kernel undervolt & thermal control driver");
