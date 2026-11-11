// SPDX-License-Identifier: GPL-2.0
/*
 * MoroSound & Sound Control Driver
 *
 * Implements sysfs control nodes for HKTweaks Sound and MoroSound interfaces
 * Compatible with Samsung Exynos Audio (A-Box / Realtek)
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
#include <linux/kobject.h>
#include <linux/mutex.h>

#define MORO_SOUND_VERSION "2.1.0"

static int sound_enabled = 1;
static int headphone_gain = 0;
static int speaker_gain = 0;
static int earpiece_gain = 0;
static int mic_gain = 0;
static int eq_enabled = 0;
static int eq_b1 = 0;
static int eq_b2 = 0;
static int eq_b3 = 0;
static int eq_b4 = 0;
static int eq_b5 = 0;

static DEFINE_MUTEX(sound_mutex);

/* Moro Sound sysfs attributes */
static ssize_t version_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%s\n", MORO_SOUND_VERSION);
}

static ssize_t moro_sound_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%d\n", sound_enabled);
}

static ssize_t moro_sound_store(struct device *dev, struct device_attribute *attr,
				const char *buf, size_t count)
{
	int val;
	if (kstrtoint(buf, 10, &val) == 0)
		sound_enabled = (val != 0);
	return count;
}

static ssize_t headphone_gain_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%d\n", headphone_gain);
}

static ssize_t headphone_gain_store(struct device *dev, struct device_attribute *attr,
				   const char *buf, size_t count)
{
	int val;
	if (kstrtoint(buf, 10, &val) == 0) {
		if (val >= -30 && val <= 20)
			headphone_gain = val;
	}
	return count;
}

static ssize_t speaker_gain_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%d\n", speaker_gain);
}

static ssize_t speaker_gain_store(struct device *dev, struct device_attribute *attr,
				 const char *buf, size_t count)
{
	int val;
	if (kstrtoint(buf, 10, &val) == 0) {
		if (val >= -30 && val <= 20)
			speaker_gain = val;
	}
	return count;
}

static ssize_t earpiece_gain_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%d\n", earpiece_gain);
}

static ssize_t earpiece_gain_store(struct device *dev, struct device_attribute *attr,
				  const char *buf, size_t count)
{
	int val;
	if (kstrtoint(buf, 10, &val) == 0) {
		if (val >= -30 && val <= 20)
			earpiece_gain = val;
	}
	return count;
}

static ssize_t eq_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%d\n", eq_enabled);
}

static ssize_t eq_store(struct device *dev, struct device_attribute *attr,
			const char *buf, size_t count)
{
	int val;
	if (kstrtoint(buf, 10, &val) == 0)
		eq_enabled = (val != 0);
	return count;
}

static ssize_t eq_b1_gain_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%d\n", eq_b1);
}

static ssize_t eq_b1_gain_store(struct device *dev, struct device_attribute *attr,
				const char *buf, size_t count)
{
	int val;
	if (kstrtoint(buf, 10, &val) == 0) eq_b1 = val;
	return count;
}

static ssize_t eq_b2_gain_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%d\n", eq_b2);
}

static ssize_t eq_b2_gain_store(struct device *dev, struct device_attribute *attr,
				const char *buf, size_t count)
{
	int val;
	if (kstrtoint(buf, 10, &val) == 0) eq_b2 = val;
	return count;
}

static ssize_t eq_b3_gain_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%d\n", eq_b3);
}

static ssize_t eq_b3_gain_store(struct device *dev, struct device_attribute *attr,
				const char *buf, size_t count)
{
	int val;
	if (kstrtoint(buf, 10, &val) == 0) eq_b3 = val;
	return count;
}

static ssize_t eq_b4_gain_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%d\n", eq_b4);
}

static ssize_t eq_b4_gain_store(struct device *dev, struct device_attribute *attr,
				const char *buf, size_t count)
{
	int val;
	if (kstrtoint(buf, 10, &val) == 0) eq_b4 = val;
	return count;
}

static ssize_t eq_b5_gain_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%d\n", eq_b5);
}

static ssize_t eq_b5_gain_store(struct device *dev, struct device_attribute *attr,
				const char *buf, size_t count)
{
	int val;
	if (kstrtoint(buf, 10, &val) == 0) eq_b5 = val;
	return count;
}

static ssize_t eq_gains_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%d,%d,%d,%d,%d\n", eq_b1, eq_b2, eq_b3, eq_b4, eq_b5);
}

static ssize_t eq_gains_store(struct device *dev, struct device_attribute *attr,
			      const char *buf, size_t count)
{
	int b1, b2, b3, b4, b5;
	if (sscanf(buf, "%d,%d,%d,%d,%d", &b1, &b2, &b3, &b4, &b5) == 5) {
		eq_b1 = b1;
		eq_b2 = b2;
		eq_b3 = b3;
		eq_b4 = b4;
		eq_b5 = b5;
	}
	return count;
}

static DEVICE_ATTR_RO(version);
static DEVICE_ATTR_RW(moro_sound);
static DEVICE_ATTR_RW(headphone_gain);
static DEVICE_ATTR_RW(speaker_gain);
static DEVICE_ATTR_RW(earpiece_gain);
static DEVICE_ATTR_RW(eq);
static DEVICE_ATTR_RW(eq_b1_gain);
static DEVICE_ATTR_RW(eq_b2_gain);
static DEVICE_ATTR_RW(eq_b3_gain);
static DEVICE_ATTR_RW(eq_b4_gain);
static DEVICE_ATTR_RW(eq_b5_gain);
static DEVICE_ATTR_RW(eq_gains);

static struct attribute *moro_sound_attrs[] = {
	&dev_attr_version.attr,
	&dev_attr_moro_sound.attr,
	&dev_attr_headphone_gain.attr,
	&dev_attr_speaker_gain.attr,
	&dev_attr_earpiece_gain.attr,
	&dev_attr_eq.attr,
	&dev_attr_eq_b1_gain.attr,
	&dev_attr_eq_b2_gain.attr,
	&dev_attr_eq_b3_gain.attr,
	&dev_attr_eq_b4_gain.attr,
	&dev_attr_eq_b5_gain.attr,
	&dev_attr_eq_gains.attr,
	NULL,
};

static const struct attribute_group moro_sound_group = {
	.attrs = moro_sound_attrs,
};

static struct miscdevice moro_sound_dev = {
	.minor = MISC_DYNAMIC_MINOR,
	.name = "moro_sound",
};

/* Additional /sys/kernel/sound_control support for Flar2/Franco interfaces */
static struct kobject *sound_control_kobj;

static ssize_t sc_headphone_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%d\n", headphone_gain);
}
static ssize_t sc_headphone_store(struct kobject *kobj, struct kobj_attribute *attr,
				  const char *buf, size_t count)
{
	int val;
	if (kstrtoint(buf, 10, &val) == 0) headphone_gain = val;
	return count;
}

static ssize_t sc_speaker_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%d\n", speaker_gain);
}
static ssize_t sc_speaker_store(struct kobject *kobj, struct kobj_attribute *attr,
				const char *buf, size_t count)
{
	int val;
	if (kstrtoint(buf, 10, &val) == 0) speaker_gain = val;
	return count;
}

static ssize_t sc_mic_show(struct kobject *kobj, struct kobj_attribute *attr, char *buf)
{
	return scnprintf(buf, PAGE_SIZE, "%d\n", mic_gain);
}
static ssize_t sc_mic_store(struct kobject *kobj, struct kobj_attribute *attr,
			    const char *buf, size_t count)
{
	int val;
	if (kstrtoint(buf, 10, &val) == 0) mic_gain = val;
	return count;
}

static struct kobj_attribute sc_headphone_attr = __ATTR(headphone_gain, 0644, sc_headphone_show, sc_headphone_store);
static struct kobj_attribute sc_speaker_attr = __ATTR(speaker_gain, 0644, sc_speaker_show, sc_speaker_store);
static struct kobj_attribute sc_mic_attr = __ATTR(mic_gain, 0644, sc_mic_show, sc_mic_store);

static struct attribute *sound_control_attrs[] = {
	&sc_headphone_attr.attr,
	&sc_speaker_attr.attr,
	&sc_mic_attr.attr,
	NULL,
};

static const struct attribute_group sound_control_group = {
	.attrs = sound_control_attrs,
};

static int __init moro_sound_init(void)
{
	int ret;

	ret = misc_register(&moro_sound_dev);
	if (ret) {
		pr_err("moro_sound: failed to register misc device (%d)\n", ret);
		return ret;
	}

	ret = sysfs_create_group(&moro_sound_dev.this_device->kobj, &moro_sound_group);
	if (ret) {
		pr_err("moro_sound: failed to create sysfs group (%d)\n", ret);
		misc_deregister(&moro_sound_dev);
		return ret;
	}

	sound_control_kobj = kobject_create_and_add("sound_control", kernel_kobj);
	if (sound_control_kobj) {
		if (sysfs_create_group(sound_control_kobj, &sound_control_group))
			pr_warn("moro_sound: failed to create sound_control sysfs group\n");
	}

	pr_info("MoroSound v%s initialized\n", MORO_SOUND_VERSION);
	return 0;
}

static void __exit moro_sound_exit(void)
{
	if (sound_control_kobj)
		kobject_put(sound_control_kobj);
	sysfs_remove_group(&moro_sound_dev.this_device->kobj, &moro_sound_group);
	misc_deregister(&moro_sound_dev);
}

module_init(moro_sound_init);
module_exit(moro_sound_exit);

MODULE_LICENSE("GPL v2");
MODULE_AUTHOR("NightKernel Team");
MODULE_DESCRIPTION("MoroSound and Sound Control driver for HKTweaks");
MODULE_VERSION(MORO_SOUND_VERSION);
