// SPDX-License-Identifier: Apache-2.0
/*
 * tas5806-init: bring the SJ201's TAS5806MD Class-D amplifier out of
 * standby/mute into play mode.
 *
 * The amp sits on I2C bus 1 at address 0x2F. After power-on it stays muted
 * until this register sequence runs.  The sequence (and the deep-sleep -> HiZ
 * -> play transition on the run-state register 0x03) is derived from the
 * OpenVoiceOS tas5806-init script (Apache-2.0) and the TI TAS5806M datasheet.
 *
 * Reimplemented in C against Linux i2c-dev so the appliance needs no Python /
 * smbus2 runtime on the read-only rootfs.
 */

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include <linux/i2c-dev.h>
#include <sys/ioctl.h>

#define I2C_BUS  "/dev/i2c-1"
#define DEV_ADDR 0x2f

/* run-state register (0x03) values */
#define STATE_DEEP_SLEEP 0x00
#define STATE_HIZ        0x02
#define STATE_PLAY       0x03

static int write_reg(int fd, uint8_t reg, uint8_t val)
{
	uint8_t buf[2] = { reg, val };

	if (write(fd, buf, 2) != 2) {
		fprintf(stderr, "tas5806-init: write reg 0x%02x = 0x%02x failed: %s\n",
			reg, val, strerror(errno));
		return -1;
	}
	return 0;
}

static void settle(void)
{
	/* 100 ms between writes, matching the reference init timing. */
	struct timespec ts = { .tv_sec = 0, .tv_nsec = 100 * 1000 * 1000 };

	nanosleep(&ts, NULL);
}

int main(void)
{
	int fd;

	fd = open(I2C_BUS, O_RDWR);
	if (fd < 0) {
		fprintf(stderr, "tas5806-init: open %s failed: %s\n",
			I2C_BUS, strerror(errno));
		return 1;
	}

	if (ioctl(fd, I2C_SLAVE, DEV_ADDR) < 0) {
		fprintf(stderr, "tas5806-init: select 0x%02x failed: %s\n",
			DEV_ADDR, strerror(errno));
		close(fd);
		return 1;
	}

	const struct { uint8_t reg, val; } seq[] = {
		{ 0x01, 0x11 },          /* reset chip */
		{ 0x78, 0x80 },          /* clear faults */
		{ 0x01, 0x00 },          /* remove reset */
		{ 0x78, 0x00 },          /* remove clear-fault */
		{ 0x33, 0x03 },          /* I2S word length = 32-bit */
		/*
		 * Digital volume (reg 0x4c): each LSB = 0.5 dB attenuation.
		 *   0x00 =   0.0 dB (maximum, no attenuation)
		 *   0x30 = -24.0 dB
		 *   0x60 = -48.0 dB
		 *   0xFF = -127.5 dB (near-silent)
		 * Software volume control (PipeWire) operates on top of this
		 * hardware ceiling.
		 */
		{ 0x4c, 0x30 },          /* digital volume: -24 dB */
		{ 0x30, 0x01 },          /* SDOUT = DSP input */
		{ 0x03, STATE_DEEP_SLEEP },
		{ 0x03, STATE_HIZ },
		{ 0x5c, 0x01 },          /* BQ coefficient write start */
		{ 0x03, STATE_PLAY },
	};

	for (size_t i = 0; i < sizeof(seq) / sizeof(seq[0]); i++) {
		if (write_reg(fd, seq[i].reg, seq[i].val) < 0) {
			close(fd);
			return 1;
		}
		settle();
	}

	close(fd);
	printf("tas5806-init: TAS5806MD initialized (play mode)\n");
	return 0;
}
