"""Couchboard screensaver: shows the board rendered by the couchboard service.

The service on prometheus renders the chosen layout (picked at
http://192.168.1.42:8790/) to a 1920x1080 PNG once a minute, with a slow pixel
orbit built in. This shows that image full screen and swaps in each new one.

Stale guard: every image carries X-Rendered-At. If the service is unreachable or
the newest image is older than STALE_AFTER, the board is hidden and a plain dim
clock drawn by Kodi takes over (moving each minute), so the TV never shows a
frozen time. The board comes back as soon as fresh renders do.
"""
import os
import random
import time
import urllib.request
from datetime import datetime

import xbmc
import xbmcaddon
import xbmcgui
import xbmcvfs

URL = "http://192.168.1.42:8790/tv.png"
STALE_AFTER = 180  # seconds

ADDON = xbmcaddon.Addon()
BLACK = os.path.join(ADDON.getAddonInfo("path"), "resources", "black.png")
CACHE = xbmcvfs.translatePath(ADDON.getAddonInfo("profile"))


def fetch(slot):
    """Download the current render into one of two files.

    Returns its path, or None when the service is down or the render is stale.
    """
    path = os.path.join(CACHE, f"board-{slot}.png")
    try:
        with urllib.request.urlopen(URL, timeout=8) as r:
            rendered = float(r.headers.get("X-Rendered-At") or 0)
            body = r.read()
    except Exception as e:
        xbmc.log(f"couchboard: fetch failed: {e!r}", xbmc.LOGWARNING)
        return None
    if time.time() - rendered > STALE_AFTER:
        xbmc.log(f"couchboard: render is {int(time.time() - rendered)} s old", xbmc.LOGWARNING)
        return None
    with open(path, "wb") as f:
        f.write(body)
    return path


class Monitor(xbmc.Monitor):
    def __init__(self):
        super().__init__()
        self.done = False

    def onScreensaverDeactivated(self):
        self.done = True


class Fallback:
    """Dim clock + date, moved to a random spot each minute."""

    def __init__(self, win, w, h):
        self.w, self.h = w, h
        self.time = xbmcgui.ControlLabel(0, 0, 600, 160, "", "font_weather_currenttemp", "FF4A515E")
        self.date = xbmcgui.ControlLabel(0, 0, 600, 50, "", "font_title", "FF3A404A")
        win.addControl(self.time)
        win.addControl(self.date)
        self.show(False)

    def show(self, visible):
        self.time.setVisible(visible)
        self.date.setVisible(visible)

    def tick(self):
        now = datetime.now()
        x = random.randint(40, max(40, self.w - 640))
        y = random.randint(40, max(40, self.h - 260))
        self.time.setPosition(x, y)
        self.date.setPosition(x + 6, y + 150)
        self.time.setLabel(now.strftime("%H:%M"))
        self.date.setLabel(now.strftime("%a %b %d"))


def main():
    os.makedirs(CACHE, exist_ok=True)
    monitor = Monitor()
    win = xbmcgui.WindowDialog()
    w, h = win.getWidth(), win.getHeight()
    win.addControl(xbmcgui.ControlImage(0, 0, w, h, BLACK))
    board = xbmcgui.ControlImage(0, 0, w, h, "", aspectRatio=2)  # 2 = keep aspect, fit
    win.addControl(board)
    fallback = Fallback(win, w, h)

    slot = 0

    def refresh():
        nonlocal slot
        slot ^= 1  # alternate files so Kodi never reads a half-written image
        path = fetch(slot)
        if path:
            board.setImage(path, False)
            board.setVisible(True)
            fallback.show(False)
        else:
            board.setVisible(False)
            fallback.tick()
            fallback.show(True)

    refresh()
    win.show()

    # Check once a second so a button press closes it right away; refresh a few
    # seconds after each minute turns (the service renders ~0.5 s past the minute).
    minute = int(time.time() // 60)
    while not monitor.done and not monitor.waitForAbort(1):
        if time.time() % 60 >= 3 and int(time.time() // 60) != minute:
            minute = int(time.time() // 60)
            refresh()

    win.close()
    del win


if __name__ == "__main__":
    main()
