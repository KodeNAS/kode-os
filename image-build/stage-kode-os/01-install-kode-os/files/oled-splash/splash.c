/*
 * kode-splash — minimal SH1122 OLED splash painter for initramfs.
 *
 * Statically linked, ~10 KB stripped. Talks SPI directly to
 * /dev/spidev0.0 and the DC + RST pins on /dev/gpiochip0 using
 * raw kernel ioctls — no libgpiod, no shared libs other than libc.
 *
 * Renders the framebuffer in splash_bitmap.h (generated at build
 * time from a brand bitmap by gen-bitmap.py) onto a Waveshare
 * 2.08" 256x64 SH1122 wired to:
 *
 *   CLK -> GPIO 11   CS  -> GPIO  8 (CE0)
 *   SDA -> GPIO 10   DC  -> GPIO 24
 *   RST -> GPIO 25
 *
 * (Pin assignments must match pebble/kode_nas_display.py — they're
 * the project's canonical OLED wiring.)
 *
 * Exit codes:
 *   0 — splash painted (or kernel reports the display already off)
 *   1 — couldn't open /dev/spidev0.0 (SPI not enabled?)
 *   2 — couldn't open /dev/gpiochip0
 *   3 — couldn't request DC / RST GPIO lines
 *
 * The main kode-nas-display daemon takes over from the splash after
 * the boot finishes. The splash leaves the display ON; the daemon's
 * first frame replaces the splash content seamlessly.
 */

/* _GNU_SOURCE is set via the Makefile's -D_GNU_SOURCE — don't redefine. */
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <linux/spi/spidev.h>
#include <linux/gpio.h>

#include "splash_bitmap.h"  /* defines splash_framebuffer[FB_SIZE] */

#define DEV_SPI       "/dev/spidev0.0"
#define DEV_GPIOCHIP  "/dev/gpiochip0"
#define DC_PIN        24
#define RST_PIN       25
#define WIDTH         256
#define HEIGHT        64
#define FB_SIZE       (WIDTH / 2 * HEIGHT)   /* 4-bit packed = 8192 bytes */
#define SPI_SPEED_HZ  8000000                /* 8 MHz — what the daemon uses */
#define SPI_CHUNK     4096                   /* matches Python's writebytes2 */

static int spi_fd = -1;
static int dc_fd  = -1;
static int rst_fd = -1;

/* Request a single GPIO line from the chip as an output, initial value set.
 * Returns the line-handle FD or -1 on failure. The chip FD can be closed
 * immediately — the line FD keeps the line reserved until it's closed. */
static int gpio_get_output(const char *chip_path, unsigned int pin, int initial)
{
    int chip_fd = open(chip_path, O_RDWR | O_CLOEXEC);
    if (chip_fd < 0) return -1;

    struct gpiohandle_request req;
    memset(&req, 0, sizeof(req));
    req.lineoffsets[0]    = pin;
    req.default_values[0] = (uint8_t)(initial ? 1 : 0);
    req.flags             = GPIOHANDLE_REQUEST_OUTPUT;
    req.lines             = 1;
    strncpy(req.consumer_label, "kode-splash",
            sizeof(req.consumer_label) - 1);

    int rc = ioctl(chip_fd, GPIO_GET_LINEHANDLE_IOCTL, &req);
    close(chip_fd);
    if (rc < 0) return -1;
    return req.fd;
}

static int gpio_set(int line_fd, int value)
{
    struct gpiohandle_data data;
    memset(&data, 0, sizeof(data));
    data.values[0] = (uint8_t)(value ? 1 : 0);
    return ioctl(line_fd, GPIOHANDLE_SET_LINE_VALUES_IOCTL, &data);
}

/* Tiny helper: nanosleep wrapped to be EINTR-safe and accept ms. */
static void sleep_ms(unsigned int ms)
{
    struct timespec ts = { .tv_sec = ms / 1000,
                           .tv_nsec = (long)(ms % 1000) * 1000000L };
    while (nanosleep(&ts, &ts) == -1 && errno == EINTR) { /* retry */ }
}

static int spi_write_all(const uint8_t *buf, size_t len)
{
    while (len > 0) {
        size_t chunk = len > SPI_CHUNK ? SPI_CHUNK : len;
        ssize_t n = write(spi_fd, buf, chunk);
        if (n < 0) return -1;
        buf += n;
        len -= (size_t)n;
    }
    return 0;
}

/* DC low = command byte. */
static int oled_cmd(uint8_t c)
{
    if (gpio_set(dc_fd, 0) < 0) return -1;
    return spi_write_all(&c, 1);
}

/* DC high = data bytes. */
static int oled_data(const uint8_t *buf, size_t len)
{
    if (gpio_set(dc_fd, 1) < 0) return -1;
    return spi_write_all(buf, len);
}

/* Same init sequence as pebble/kode_nas_display.py _init_display().
 * If the daemon's sequence ever changes, change this to match. */
static int oled_init(void)
{
    /* Hardware reset: pulse RST low for 10ms, then high + settle. */
    if (gpio_set(rst_fd, 0) < 0) return -1;
    sleep_ms(10);
    if (gpio_set(rst_fd, 1) < 0) return -1;
    sleep_ms(50);

    static const uint8_t init_cmds[] = {
        /* 0xC8 + 0xA1 = 180° rotated. Match kode_nas_display.py
         * exactly so the splash → daemon handoff stays seamless
         * (the daemon's first frame would otherwise re-orient and
         * the buyer would see a half-second flip). */
        0xAE, 0xB0, 0x10, 0x00, 0xC8, 0x40,
        0x81, 0x80, 0xA1, 0xA4, 0xA6,
        0xA8, 0x3F, 0xAD, 0x81,
        0xD3, 0x10, 0xD5, 0x50,
        0xD9, 0x22, 0xDB, 0x35, 0xDC, 0x35, 0x30
    };
    for (size_t i = 0; i < sizeof(init_cmds); i++) {
        if (oled_cmd(init_cmds[i]) < 0) return -1;
    }
    sleep_ms(100);
    return oled_cmd(0xAF);  /* display on */
}

static int oled_paint(const uint8_t *fb, size_t len)
{
    if (oled_cmd(0xB0) < 0) return -1;  /* page address */
    if (oled_cmd(0x10) < 0) return -1;  /* column high */
    if (oled_cmd(0x00) < 0) return -1;  /* column low */
    return oled_data(fb, len);
}

int main(void)
{
    /* Open SPI bus and configure mode 0, 8 bits, 8 MHz. */
    spi_fd = open(DEV_SPI, O_RDWR | O_CLOEXEC);
    if (spi_fd < 0) {
        fprintf(stderr, "kode-splash: open(%s): %s\n",
                DEV_SPI, strerror(errno));
        return 1;
    }
    uint8_t  mode  = SPI_MODE_0;
    uint8_t  bits  = 8;
    uint32_t speed = SPI_SPEED_HZ;
    if (ioctl(spi_fd, SPI_IOC_WR_MODE, &mode) < 0 ||
        ioctl(spi_fd, SPI_IOC_WR_BITS_PER_WORD, &bits) < 0 ||
        ioctl(spi_fd, SPI_IOC_WR_MAX_SPEED_HZ, &speed) < 0) {
        fprintf(stderr, "kode-splash: SPI config: %s\n", strerror(errno));
        return 1;
    }

    /* Reserve DC + RST lines. RST starts HIGH (not in reset), DC LOW
     * (command mode). gpio_get_output applies these initial values
     * atomically with the request. */
    dc_fd = gpio_get_output(DEV_GPIOCHIP, DC_PIN, 0);
    if (dc_fd < 0) {
        fprintf(stderr, "kode-splash: GPIO DC request: %s\n", strerror(errno));
        return 2;
    }
    rst_fd = gpio_get_output(DEV_GPIOCHIP, RST_PIN, 1);
    if (rst_fd < 0) {
        fprintf(stderr, "kode-splash: GPIO RST request: %s\n", strerror(errno));
        return 3;
    }

    if (oled_init() < 0) {
        fprintf(stderr, "kode-splash: oled_init: %s\n", strerror(errno));
        return 1;
    }
    if (oled_paint(splash_framebuffer, FB_SIZE) < 0) {
        fprintf(stderr, "kode-splash: oled_paint: %s\n", strerror(errno));
        return 1;
    }

    /* Deliberately don't close the GPIO/SPI FDs — exiting with them
     * open lets the kernel hand the lines off cleanly when the main
     * daemon takes over (otherwise there's a small window where the
     * lines briefly revert to input + the display can flicker). */
    return 0;
}
