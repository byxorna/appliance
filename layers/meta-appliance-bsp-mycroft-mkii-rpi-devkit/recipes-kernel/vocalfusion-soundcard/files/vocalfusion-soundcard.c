// SPDX-License-Identifier: GPL-2.0
/*
 * XMOS VocalFusion soundcard driver.
 *
 * Brings up the SJ201 audio path described by the sj201 device tree overlay:
 * sets GPCLK0/MCLK (GPIO 4) to the DT-specified rate, then asserts the XMOS
 * power (GPIO 16) and reset (GPIO 27) lines and releases them back to
 * userspace.  The actual sound card is a simple-audio-card defined in the DT.
 *
 * Vendored from OpenVoiceOS/VocalFusionDriver (GPL-2.0) and adapted for the
 * Linux 6.6 platform_driver API, whose .remove callback returns int.
 *
 * Original authors: Paul Creaser, Huan Truong, Peter Steenbergen (OpenVoiceOS).
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/platform_device.h>
#include <linux/of.h>
#include <linux/clk.h>
#include <linux/gpio/consumer.h>
#include <linux/delay.h>
#include <sound/simple_card.h>

static int vocalfusion_soundcard_probe(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	struct clk *mclk;
	struct gpio_desc *pwr_gpio, *rst_gpio;
	u32 rate;
	int ret;

	mclk = devm_clk_get(dev, NULL);
	if (IS_ERR(mclk)) {
		dev_err(dev, "Failed to get clock: %ld\n", PTR_ERR(mclk));
		return PTR_ERR(mclk);
	}

	ret = of_property_read_u32(dev->of_node, "clock-frequency", &rate);
	if (ret) {
		dev_err(dev, "Failed to read 'clock-frequency': %d\n", ret);
		return ret;
	}

	dev_info(dev, "rate set to: %u Hz\n", rate);

	ret = clk_set_rate(mclk, rate);
	if (ret) {
		dev_err(dev, "Failed to set clock rate: %d\n", ret);
		return ret;
	}

	ret = clk_prepare_enable(mclk);
	if (ret) {
		dev_err(dev, "Failed to enable clock: %d\n", ret);
		return ret;
	}
	dev_info(dev, "mclk set to: %lu Hz\n", clk_get_rate(mclk));

	pwr_gpio = devm_gpiod_get(dev, "pwr", GPIOD_OUT_HIGH);
	if (IS_ERR(pwr_gpio)) {
		dev_err(dev, "Failed to get PWR GPIO: %ld\n", PTR_ERR(pwr_gpio));
		clk_disable_unprepare(mclk);
		return PTR_ERR(pwr_gpio);
	}

	rst_gpio = devm_gpiod_get(dev, "rst", GPIOD_OUT_HIGH);
	if (IS_ERR(rst_gpio)) {
		dev_err(dev, "Failed to get RST GPIO: %ld\n", PTR_ERR(rst_gpio));
		devm_gpiod_put(dev, pwr_gpio);
		clk_disable_unprepare(mclk);
		return PTR_ERR(rst_gpio);
	}

	/* Release the GPIOs so userspace tooling can drive them. */
	devm_gpiod_put(dev, rst_gpio);
	devm_gpiod_put(dev, pwr_gpio);

	platform_set_drvdata(pdev, mclk);

	pr_info("VocalFusion soundcard module loaded\n");
	return 0;
}

static int vocalfusion_soundcard_remove(struct platform_device *pdev)
{
	struct clk *mclk = platform_get_drvdata(pdev);

	if (!IS_ERR_OR_NULL(mclk))
		clk_disable_unprepare(mclk);

	pr_info("VocalFusion soundcard module unloaded\n");
	return 0;
}

static const struct of_device_id vocalfusion_soundcard_of_match[] = {
	{ .compatible = "vocalfusion-soundcard", },
	{},
};
MODULE_DEVICE_TABLE(of, vocalfusion_soundcard_of_match);

static struct platform_driver vocalfusion_soundcard_driver = {
	.driver = {
		.name = "vocalfusion-driver",
		.owner = THIS_MODULE,
		.of_match_table = vocalfusion_soundcard_of_match,
	},
	.probe = vocalfusion_soundcard_probe,
	.remove = vocalfusion_soundcard_remove,
};

module_platform_driver(vocalfusion_soundcard_driver);

MODULE_DESCRIPTION("XMOS VocalFusion I2S Driver");
MODULE_AUTHOR("OpenVoiceOS");
MODULE_LICENSE("GPL v2");
MODULE_ALIAS("platform:vocalfusion-soundcard");
