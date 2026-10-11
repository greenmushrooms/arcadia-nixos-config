"""Couchboard screensaver: shows the board rendered by the couchboard service.

The service on prometheus renders the chosen layout (picked at
http://192.168.1.42:8790/) to a 1920x1080 PNG once a minute, with a slow pixel
orbit built in. This just shows that image full screen and swaps in each new
one. If the service is unreachable, the last image stays up.
"""
import os
import time
import urllib.request

import xbmc
import xbmcaddon
import xbmcgui
import xbmcvfs

URL = "http://192.168.1.42:8790/tv.png"

ADDON = xbmcaddon.Addon()
BLACK = os.path.join(ADDON.getAddonInfo("path"), "resources", "black.png")
CACHE = xbmcvfs.translatePath(ADDON.getAddonInfo("profile"))


def fetch(slot):
    """Download the current render into one of two files; return its path or None."""
    path = os.path.join(CACHE, f"board-{slot}.png")
    try:
        with urllib.request.urlopen(URL, timeout=8) as r, open(path, "wb") as f:
            f.write(r.read())
        return path
    except Exception as e:
        xbmc.log(f"couchboard: fetch failed: {e!r}", xbmc.LOGWARNING)
        return None


class Monitor(xbmc.Monitor):
    def __init__(self):
        super().__init__()
        self.done = False

    def onScreensaverDeactivated(self):
        self.done = True


def main():
    os.makedirs(CACHE, exist_ok=True)
    monitor = Monitor()
    win = xbmcgui.WindowDialog()
    w, h = win.getWidth(), win.getHeight()
    win.addControl(xbmcgui.ControlImage(0, 0, w, h, BLACK))
    board = xbmcgui.ControlImage(0, 0, w, h, "", aspectRatio=2)  # 2 = keep aspect, fit
    win.addControl(board)

    slot = 0
    path = fetch(slot)
    if path:
        board.setImage(path, False)
    win.show()

    # Check once a second so a button press closes it right away; fetch a few
    # seconds after each minute turns (the service renders ~0.5 s past the minute).
    minute = int(time.time() // 60)
    while not monitor.done and not monitor.waitForAbort(1):
        if time.time() % 60 >= 3 and int(time.time() // 60) != minute:
            minute = int(time.time() // 60)
            slot ^= 1  # alternate files so Kodi never reads a half-written image
            path = fetch(slot)
            if path:
                board.setImage(path, False)

    win.close()
    del win


if __name__ == "__main__":
    main()
