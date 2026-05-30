#!/usr/bin/env python3
"""
KODE NAS — pebble v1 display (Raspberry Pi native port)

Drives the SH1122 OLED directly from Pi GPIO/SPI and gathers all stats
locally — no Arduino, no USB serial. Same UI as the Arduino sketch:
splash → 3 rotating screens (Address / Storage / Status), with a button
for manual advance + long-press lock.

Wiring (BCM):
  VCC -> 3.3V        DC  -> GPIO 24
  GND -> GND         RST -> GPIO 25
  CLK -> GPIO 11     CS  -> GPIO  8 (CE0)
  SDA -> GPIO 10
  Button (optional) -> GPIO 17 to GND (uses internal pull-up)

Run on boot via systemd (see README at bottom of file).
"""

import math
import os
import socket
import shutil
import subprocess
import time
from pathlib import Path
from io import BytesIO

import psutil
import spidev
from gpiozero import DigitalOutputDevice, Button
from PIL import Image, ImageDraw, ImageFont


# ============================================================================
# CONFIG
# ============================================================================
COMPANY_NAME = "KODE NAS"
PRODUCT_NAME = "pebble v1"

LOADING_MIN_SEC   = 1.4
SPLASH_DURATION   = 1.6
AUTO_ROTATE_SEC   = 3.0
LONG_PRESS_SEC    = 1.5
STATS_INTERVAL    = 2.0
DOTS_TICK_SEC     = 0.5
REDRAW_HZ         = 15           # smoother loading animation

NAS_ROOT          = "/"
NUM_SCREENS       = 4
BUTTON_PIN        = None         # set to a BCM pin (e.g. 17) to enable

# Outer drawing margin (px). Everything sits inside this safe area.
MARGIN_X          = 4
MARGIN_Y_TOP      = 2
MARGIN_Y_BOT      = 2

DC_PIN, RST_PIN   = 24, 25
SPI_BUS, SPI_DEV  = 0, 0
SPI_HZ            = 8_000_000


# ============================================================================
# SH1122 DRIVER
# ============================================================================
class SH1122:
    WIDTH, HEIGHT = 256, 64

    def __init__(self, spi_bus=0, spi_device=0, dc_pin=24, rst_pin=25,
                 spi_hz=8_000_000):
        self.dc  = DigitalOutputDevice(dc_pin,  initial_value=False)
        self.rst = DigitalOutputDevice(rst_pin, initial_value=True)
        self.spi = spidev.SpiDev()
        self.spi.open(spi_bus, spi_device)
        self.spi.max_speed_hz = spi_hz
        self.spi.mode = 0
        self._reset()
        self._init_display()

    def _reset(self):
        self.rst.on();  time.sleep(0.01)
        self.rst.off(); time.sleep(0.05)
        self.rst.on();  time.sleep(0.05)

    def _cmd(self, *bytes_):
        self.dc.off()
        self.spi.writebytes(list(bytes_))

    def _data(self, buf):
        self.dc.on()
        mv = memoryview(buf)
        for i in range(0, len(buf), 4096):
            self.spi.writebytes2(mv[i:i+4096])

    def _init_display(self):
        # 0xC8 (was 0xC0) + 0xA1 (was 0xA0) rotates the display 180°.
        # SH1122 has no software rotation API beyond these two flip
        # bits, so a remount that turns the OLED upside-down means
        # toggling these. To undo: 0xC0 + 0xA0 = native orientation.
        for b in [0xAE, 0xB0, 0x10, 0x00, 0xC8, 0x40,
                  0x81, 0x80, 0xA1, 0xA4, 0xA6,
                  0xA8, 0x3F, 0xAD, 0x81,
                  0xD3, 0x10, 0xD5, 0x50,
                  0xD9, 0x22, 0xDB, 0x35, 0xDC, 0x35, 0x30]:
            self._cmd(b)
        time.sleep(0.1)
        self._cmd(0xAF)

    def display(self, image):
        if image.mode != "L":
            image = image.convert("L")
        raw = image.tobytes()
        buf = bytearray(self.WIDTH // 2 * self.HEIGHT)
        for i in range(0, len(raw), 2):
            buf[i >> 1] = (raw[i] & 0xF0) | (raw[i + 1] >> 4)
        self._cmd(0xB0); self._cmd(0x10); self._cmd(0x00)
        self._data(buf)

    def clear(self):
        self.display(Image.new("L", (self.WIDTH, self.HEIGHT), 0))

    def cleanup(self):
        self._cmd(0xAE)
        self.spi.close()
        self.dc.close()
        self.rst.close()


# ============================================================================
# KODE LOGO (48x48 XBM, decoded once at startup)
# ============================================================================
KODE_LOGO_BYTES = bytes([
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0xf8,0xff,0x00,0xe0,0xff,0x0f,0xf8,0xff,0x00,0xf0,0xff,0x07,
    0xf8,0xff,0x00,0xf8,0xff,0x03,0xf8,0xff,0x00,0xfc,0xff,0x01,
    0xf8,0xff,0x00,0xfe,0xff,0x00,0xf8,0xff,0x00,0xff,0x7f,0x00,
    0xf8,0xff,0x00,0xff,0x3f,0x00,0xf8,0xff,0x80,0xff,0x1f,0x00,
    0xf8,0xff,0xc0,0xff,0x1f,0x00,0xf8,0xff,0xe0,0xff,0x0f,0x00,
    0xf8,0xff,0xf0,0xff,0x07,0x00,0xf8,0xff,0xf8,0xff,0x03,0x00,
    0xf8,0xff,0xfc,0xff,0x01,0x00,0xf8,0xff,0xfe,0xff,0x00,0x00,
    0xf8,0xff,0xff,0x7f,0x00,0x00,0xf8,0xff,0xff,0x3f,0x00,0x00,
    0xf8,0xff,0xff,0x1f,0x00,0x00,0xf8,0xff,0xff,0x0f,0x00,0x00,
    0xf8,0xff,0xff,0x1f,0x00,0x00,0xf8,0xff,0xff,0x3f,0x00,0x00,
    0xf8,0xff,0xff,0x3f,0x00,0x00,0xf8,0xff,0xff,0x7f,0x00,0x00,
    0xf8,0xff,0xff,0xff,0x00,0x00,0xf8,0xff,0xff,0xff,0x01,0x00,
    0xf8,0xff,0xff,0xff,0x01,0x00,0xf8,0xff,0xff,0xff,0x03,0x00,
    0xf8,0xff,0xff,0xff,0x07,0x00,0xf8,0xff,0xf7,0xff,0x0f,0x00,
    0xf8,0xff,0xe3,0xff,0x0f,0x00,0xf8,0xff,0xe1,0xff,0x1f,0x00,
    0xf8,0xff,0xc0,0xff,0x3f,0x00,0xf8,0xff,0x80,0xff,0x7f,0x00,
    0xf8,0xff,0x00,0xff,0x7f,0x00,0xf8,0xff,0x00,0xff,0xff,0x00,
    0xf8,0xff,0x00,0xfe,0xff,0x01,0xf8,0xff,0x00,0xfc,0xff,0x03,
    0xf8,0xff,0x00,0xf8,0xff,0x03,0xf8,0xff,0x00,0xf8,0xff,0x07,
    0xf8,0xff,0x00,0xf0,0xff,0x0f,0xf8,0xff,0x00,0xe0,0xff,0x1f,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
])


def decode_logo():
    """XBM is LSB-first; convert to a PIL 'L' image once at startup."""
    img = Image.new("L", (48, 48), 0)
    px = img.load()
    for y in range(48):
        for x in range(48):
            if KODE_LOGO_BYTES[y * 6 + (x >> 3)] & (1 << (x & 7)):
                px[x, y] = 255
    return img


# ----- Status file (first-boot + wizard URL display) ------------------
# The status file is a tiny text file at /run/kode-os/oled-status.
# Format: up to three lines (title, subtitle, footer). Empty lines or
# missing lines are simply omitted on render. The file lives in /run
# (tmpfs) so it's wiped at reboot and never accumulates stale state.
# Helper: scripts/oled-status (or kode-os-status) writes it atomically.
_STATUS_FILE = "/run/kode-os/oled-status"

def _read_status_file():
    """Return dict {title,subtitle,footer} or None if no status set."""
    try:
        with open(_STATUS_FILE, "r") as f:
            lines = f.read().splitlines()
    except (FileNotFoundError, PermissionError, OSError):
        return None
    if not lines:
        return None
    return {
        "title":    lines[0].strip() if len(lines) > 0 else "",
        "subtitle": lines[1].strip() if len(lines) > 1 else "",
        "footer":   lines[2].strip() if len(lines) > 2 else "",
    }


# ============================================================================
# FONTS
# ============================================================================
_FONT_DIR = "/usr/share/fonts/truetype/dejavu"

def _font(name, size):
    try:
        return ImageFont.truetype(f"{_FONT_DIR}/{name}.ttf", size)
    except OSError:
        return ImageFont.load_default()

FONT_HERO   = _font("DejaVuSans-Bold",      24)   # splash hero (KODE NAS)
FONT_NUM    = _font("DejaVuSans-Bold",      26)   # primary hero readouts
FONT_NUM_S  = _font("DejaVuSans-Bold",      20)   # used when the value is wide (IP)
FONT_BIG    = _font("DejaVuSans-Bold",      14)   # secondary text
FONT_LABEL  = _font("DejaVuSans",           11)   # proportional labels
FONT_SMALL  = _font("DejaVuSansMono",       11)   # mono text
FONT_TINY   = _font("DejaVuSansMono-Bold",   9)   # section caps, footnotes


def text_w(draw, text, font):
    l, t, r, b = draw.textbbox((0, 0), text, font=font)
    return r - l


# ============================================================================
# STATS
# ============================================================================
def get_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except OSError:
        return "0.0.0.0"
    finally:
        s.close()

def get_disk_info(path=NAS_ROOT):
    total, used, free = shutil.disk_usage(path)
    total_gb = max(1, total // (1024 ** 3))
    free_gb  = free  // (1024 ** 3)
    pct_used = int(used * 100 / total)
    return free_gb, total_gb, pct_used

def get_mem_info():
    m = psutil.virtual_memory()
    return int(m.percent), m.used / (1024 ** 3), m.total / (1024 ** 3)

def get_mdns_name():
    """hostname with `.local` appended so the user sees the mDNS name."""
    h = socket.gethostname()
    return h if h.endswith(".local") else f"{h}.local"

def get_cpu_temp_c():
    for p in ("/sys/class/thermal/thermal_zone0/temp",
              "/sys/class/hwmon/hwmon0/temp1_input"):
        try:
            return int(Path(p).read_text().strip()) // 1000
        except (FileNotFoundError, ValueError):
            continue
    return 0

def get_uptime_days():
    return int((time.time() - psutil.boot_time()) / 86400)

def get_app_count():
    try:
        r = subprocess.run(["docker", "ps", "--format", "{{.Names}}"],
                           capture_output=True, text=True, timeout=2)
        return sum(1 for n in r.stdout.strip().split("\n")
                   if n and not n.startswith("casaos-"))
    except (subprocess.SubprocessError, FileNotFoundError):
        return 0


# ============================================================================
# UI
# ============================================================================
class NASDisplay:
    def __init__(self, oled):
        self.oled  = oled
        self.logo  = decode_logo()
        self.state = "LOADING"
        self.state_enter = time.monotonic()
        self.has_first_data = False
        self.current_screen     = 0
        self.last_screen_change = time.monotonic()
        self.locked = False
        self.stats = {
            "ip": "0.0.0.0", "host": "", "up": "---",
            "disk_free": "0GB", "disk_total": "0GB", "disk_pct": 0,
            "cpu_pct": 0, "temp": 0,
            "mem_pct": 0, "mem_used": 0.0, "mem_total": 0.0,
        }
        self.last_stats = 0
        psutil.cpu_percent(interval=None)  # prime baseline

    # ---- data ----
    def update_stats(self):
        now = time.monotonic()
        if now - self.last_stats < STATS_INTERVAL and self.last_stats:
            return
        self.last_stats = now
        free_gb, total_gb, dpct = get_disk_info()
        mpct, mused, mtotal      = get_mem_info()
        self.stats = {
            "ip":         get_ip(),
            "host":       get_mdns_name(),
            "up":         f"{get_uptime_days()}d",
            "disk_free":  f"{free_gb}GB",
            "disk_total": f"{total_gb}GB",
            "disk_pct":   dpct,
            "cpu_pct":    int(psutil.cpu_percent(interval=None)),
            "temp":       get_cpu_temp_c(),
            "mem_pct":    mpct,
            "mem_used":   mused,
            "mem_total":  mtotal,
        }
        self.has_first_data = True

    # ---- input ----
    def short_press(self):
        if self.state == "NORMAL" and not self.locked:
            self.advance_screen()

    def long_press(self):
        if self.state == "NORMAL":
            self.locked = not self.locked
            self.last_screen_change = time.monotonic()

    def advance_screen(self):
        self.current_screen = (self.current_screen + 1) % NUM_SCREENS
        self.last_screen_change = time.monotonic()

    # ---- tick ----
    def tick(self):
        self.update_stats()
        now = time.monotonic()
        if (self.state == "LOADING" and self.has_first_data and
                now - self.state_enter > LOADING_MIN_SEC):
            self.state = "SPLASH"
            self.state_enter = now
        elif (self.state == "SPLASH" and
              now - self.state_enter > SPLASH_DURATION):
            self.state = "NORMAL"
            self.last_screen_change = now
        if (self.state == "NORMAL" and not self.locked and
                now - self.last_screen_change > AUTO_ROTATE_SEC):
            self.advance_screen()

    # ---- drawing helpers ----
    def _progress(self, draw, x, y, w, h, pct):
        """Outlined progress bar with a 2-px inset bright fill."""
        pct = max(0, min(100, int(pct)))
        draw.rectangle((x, y, x + w - 1, y + h - 1), outline=110)
        if pct > 0:
            fill_w = max(2, ((w - 4) * pct) // 100)
            draw.rectangle(
                (x + 2, y + 2, x + 1 + fill_w, y + h - 3), fill=255,
            )

    def _lock_icon(self, draw, x, y):
        # 7×9 padlock glyph
        draw.rectangle((x, y + 4, x + 6, y + 8), fill=220)
        draw.line((x + 1, y + 4, x + 1, y + 1), fill=220)
        draw.line((x + 5, y + 4, x + 5, y + 1), fill=220)
        draw.line((x + 1, y + 1, x + 5, y + 1), fill=220)
        draw.point((x + 3, y + 6), fill=0)

    def _section_cap(self, draw, title, sub=""):
        """Top section bar: SECTION label · right-aligned subtitle · link dot."""
        draw.text((MARGIN_X, MARGIN_Y_TOP), title,
                  fill=190, font=FONT_TINY)
        # link indicator: filled when we have an IP, hollow otherwise
        cx0, cy0 = 247, 4
        if self.stats["ip"] != "0.0.0.0":
            draw.ellipse((cx0, cy0, cx0 + 4, cy0 + 4), fill=255)
        else:
            draw.ellipse((cx0, cy0, cx0 + 4, cy0 + 4), outline=120)
        if sub:
            sw = text_w(draw, sub, FONT_TINY)
            draw.text((243 - sw, MARGIN_Y_TOP), sub,
                      fill=130, font=FONT_TINY)

    # ---- drawing ----
    def render(self):
        img  = Image.new("L", (256, 64), 0)
        draw = ImageDraw.Draw(img)
        # Status override — first-boot setup + wizard URL display land
        # here. The status file is set by `kode-os-status` (helper) or
        # written directly by first-boot.sh / install.sh during setup.
        # While the file exists everything else (LOADING / SPLASH /
        # NORMAL rotation) is suppressed.
        status = _read_status_file()
        if status is not None:
            self._draw_status(draw, status)
            self.oled.display(img)
            return
        if self.state == "LOADING":
            self._draw_loading(draw, img)
        elif self.state == "SPLASH":
            self._draw_splash(draw, img)
        else:
            screens = (self._draw_network, self._draw_storage,
                       self._draw_cpu,     self._draw_memory)
            screens[self.current_screen](draw)
            self._draw_footer(draw)
        self.oled.display(img)

    def _draw_status(self, draw, status):
        """Three-line status card. Used during first-boot setup + wizard
        URL display. Status dict keys: title, subtitle, footer (any
        absent → omitted)."""
        title    = status.get("title",    "")
        subtitle = status.get("subtitle", "")
        footer   = status.get("footer",   "")
        # Centred title at the top. Use FONT_BIG (14pt bold) so even
        # longer titles like "INSTALLING" fit at 256px wide.
        if title:
            tw = text_w(draw, title, FONT_BIG)
            draw.text(((256 - tw) // 2, 4), title, fill=255, font=FONT_BIG)
        # Subtitle — main message. Larger font, centred.
        if subtitle:
            sw = text_w(draw, subtitle, FONT_NUM_S)
            x = max(0, (256 - sw) // 2)
            draw.text((x, 22), subtitle, fill=255, font=FONT_NUM_S)
        # Footer — small hint text at the bottom, dim.
        if footer:
            fw = text_w(draw, footer, FONT_TINY)
            x = max(0, (256 - fw) // 2)
            draw.text((x, 50), footer, fill=160, font=FONT_TINY)

    def _draw_loading(self, draw, img):
        img.paste(self.logo, (12, 8))
        draw.text((78, 14), "Booting", fill=255, font=FONT_BIG)
        draw.text((78, 32), "KODE NAS · pebble v1",
                  fill=150, font=FONT_TINY)
        # comet-trail sweep bar (indeterminate progress)
        bx, by, bw, bh = 78, 46, 168, 5
        draw.rectangle((bx, by, bx + bw - 1, by + bh - 1), outline=80)
        period = 1.6
        phase = (time.monotonic() % period) / period
        direction = 1 if phase < 0.5 else -1
        pos = phase * 2 if phase < 0.5 else (1 - phase) * 2
        center = bx + 2 + int((bw - 4) * pos)
        for dx in range(12):
            px = center - direction * dx
            if bx + 1 <= px <= bx + bw - 2:
                fade = max(0, 255 - dx * 24)
                draw.line((px, by + 1, px, by + bh - 2), fill=fade)

    def _draw_splash(self, draw, img):
        img.paste(self.logo, (12, 8))
        draw.text((78, 10), COMPANY_NAME, fill=255, font=FONT_HERO)
        draw.text((80, 44), PRODUCT_NAME, fill=160, font=FONT_LABEL)

    def _draw_footer(self, draw):
        if self.locked:
            self._lock_icon(draw, MARGIN_X, 52)
        cy = 59
        cx0 = 249 - (NUM_SCREENS - 1) * 7
        for i in range(NUM_SCREENS):
            cx = cx0 + i * 7
            if i == self.current_screen:
                draw.ellipse((cx - 2, cy - 2, cx + 2, cy + 2), fill=255)
            else:
                draw.ellipse((cx - 2, cy - 2, cx + 2, cy + 2), outline=90)

    def _draw_network(self, draw):
        s = self.stats
        self._section_cap(draw, "NETWORK")
        # hero IP — uses the narrower NUM_S font so the dotted-quad fits with room
        draw.text((MARGIN_X, 14), s["ip"], fill=255, font=FONT_NUM_S)
        # subtitle: hostname · uptime (shifted right when the lock badge is up)
        sub_x = MARGIN_X + (14 if self.locked else 0)
        sub = f"{s['host']}   ·   up {s['up']}"
        draw.text((sub_x, 44), sub, fill=150, font=FONT_LABEL)

    def _draw_storage(self, draw):
        s = self.stats
        self._section_cap(draw, "STORAGE", f"{s['disk_pct']}% used")
        draw.text((MARGIN_X, 14), s["disk_free"],
                  fill=255, font=FONT_NUM)
        nw = text_w(draw, s["disk_free"], FONT_NUM)
        draw.text((MARGIN_X + nw + 8, 30), "free",
                  fill=160, font=FONT_LABEL)
        of_text = f"of {s['disk_total']}"
        ow = text_w(draw, of_text, FONT_LABEL)
        draw.text((251 - ow, 30), of_text, fill=160, font=FONT_LABEL)
        self._progress(draw, MARGIN_X, 46, 248, 7, s["disk_pct"])

    def _draw_cpu(self, draw):
        s = self.stats
        self._section_cap(draw, "CPU", f"{s['temp']}°C")
        draw.text((MARGIN_X, 14), f"{s['cpu_pct']}%",
                  fill=255, font=FONT_NUM)
        self._progress(draw, MARGIN_X, 46, 248, 7, s["cpu_pct"])

    def _draw_memory(self, draw):
        s = self.stats
        sub = f"{s['mem_used']:.1f} / {s['mem_total']:.1f} GB"
        self._section_cap(draw, "MEMORY", sub)
        draw.text((MARGIN_X, 14), f"{s['mem_pct']}%",
                  fill=255, font=FONT_NUM)
        self._progress(draw, MARGIN_X, 46, 248, 7, s["mem_pct"])


# ============================================================================
# MAIN
# ============================================================================
def main():
    oled = SH1122(spi_bus=SPI_BUS, spi_device=SPI_DEV,
                  dc_pin=DC_PIN, rst_pin=RST_PIN, spi_hz=SPI_HZ)
    ui = NASDisplay(oled)

    button = None
    if BUTTON_PIN is not None:
        button = Button(BUTTON_PIN, pull_up=True, bounce_time=0.05,
                        hold_time=LONG_PRESS_SEC)
        # gpiozero fires when_held after hold_time and when_released after;
        # track which fired to suppress short-press on long-press release.
        held = {"flag": False}
        def on_held():
            held["flag"] = True
            ui.long_press()
        def on_release():
            if not held["flag"]:
                ui.short_press()
            held["flag"] = False
        button.when_held    = on_held
        button.when_released = on_release

    frame_period = 1.0 / REDRAW_HZ
    try:
        while True:
            t0 = time.monotonic()
            ui.tick()
            ui.render()
            dt = time.monotonic() - t0
            if dt < frame_period:
                time.sleep(frame_period - dt)
    except KeyboardInterrupt:
        pass
    finally:
        oled.clear()
        oled.cleanup()
        if button is not None:
            button.close()


if __name__ == "__main__":
    main()


# ============================================================================
# RUN ON BOOT (systemd)
# ============================================================================
# Save as /etc/systemd/system/kode-nas-display.service:
#
#   [Unit]
#   Description=KODE NAS pebble display
#   After=network-online.target docker.service
#
#   [Service]
#   Type=simple
#   User=kode
#   ExecStart=/usr/bin/python3 /home/kode/kode_nas_display.py
#   Restart=on-failure
#   RestartSec=5
#
#   [Install]
#   WantedBy=multi-user.target
#
# Then:
#   sudo systemctl daemon-reload
#   sudo systemctl enable --now kode-nas-display.service
