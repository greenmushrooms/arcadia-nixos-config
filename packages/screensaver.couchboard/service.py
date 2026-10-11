"""Couchboard doorbell popup: a background Kodi service.

Polls the couchboard service for doorbell activity (Reolink NVR: ring, person,
package, vehicle, animal). On a new event it shows a picture-in-picture card in the
top-right corner over whatever is on screen (screensaver, menus or a playing
video), with the live doorbell picture refreshed every 1.5 s. It closes 30 s after
the activity ends, or on any button press.
"""
import json
import os
import time
import urllib.request
from datetime import datetime

import xbmc
import xbmcaddon
import xbmcgui
import xbmcvfs

BASE = "http://192.168.1.42:8790"
QUIET_CLOSE = 30   # seconds after the activity ends
FRESH = 90         # only pop for events newer than this

ADDON = xbmcaddon.Addon()
BLACK = os.path.join(ADDON.getAddonInfo("path"), "resources", "black.png")
CACHE = xbmcvfs.translatePath(ADDON.getAddonInfo("profile"))


def get_json(path):
    with urllib.request.urlopen(BASE + path, timeout=5) as r:
        return json.load(r)


def download(path, dest):
    with urllib.request.urlopen(BASE + path, timeout=8) as r, open(dest, "wb") as f:
        f.write(r.read())
    return dest


class Popup(xbmcgui.WindowDialog):
    """Top-right card: label + live picture. Any button closes it."""

    def __init__(self, label, at):
        super().__init__()
        w, h = self.getWidth(), self.getHeight()
        cw, ch = int(w * 0.36), int(h * 0.46)
        x, y = w - cw - int(w * 0.025), int(h * 0.04)
        self.addControl(xbmcgui.ControlImage(x - 6, y - 6, cw + 12, ch + 12, BLACK, colorDiffuse="0xE6000000"))
        self.title = xbmcgui.ControlLabel(x + 14, y + 6, cw - 28, 50, label, "font_title", "FFFFD166")
        self.time = xbmcgui.ControlLabel(x + 14, y + 6, cw - 28, 50, at, "font_title", "FFDFE5EC", alignment=1)
        self.addControl(self.title)
        self.addControl(self.time)
        self.picture = xbmcgui.ControlImage(x + 8, y + 60, cw - 16, ch - 68, "", aspectRatio=2)
        self.addControl(self.picture)
        self.closed = False

    def onAction(self, action):
        self.closed = True
        self.close()


def main():
    os.makedirs(CACHE, exist_ok=True)
    monitor = xbmc.Monitor()
    seen = None
    popup, quiet_since, slot, last_frame = None, 0.0, 0, 0.0

    while not monitor.abortRequested():
        try:
            a = get_json("/activity.json")
            newest = a["events"][0] if a["events"] else None
            if seen is None:                       # don't pop old events at startup
                seen = newest["id"] if newest else ""
            elif newest and newest["id"] != seen:
                seen = newest["id"]
                age = time.time() - datetime.fromisoformat(newest["at"]).timestamp()
                if age < FRESH:
                    if popup:
                        popup.close()
                    at = datetime.fromisoformat(newest["at"]).strftime("%H:%M")
                    popup = Popup(newest["label"], at)
                    try:
                        popup.picture.setImage(download(f"/activity/{newest['id']}.jpg",
                                                        os.path.join(CACHE, "event.jpg")), False)
                    except Exception:
                        pass
                    popup.show()
                    quiet_since, last_frame = 0.0, 0.0
            if popup:
                quiet_since = 0.0 if a["active"] else (quiet_since or time.time())
        except Exception as e:
            xbmc.log(f"couchboard doorbell: {e!r}", xbmc.LOGWARNING)

        if popup:
            if popup.closed or (quiet_since and time.time() - quiet_since > QUIET_CLOSE):
                if not popup.closed:
                    popup.close()
                popup = None
            elif time.time() - last_frame > 1.5:
                slot ^= 1   # alternate files so Kodi never reads a half-written frame
                try:
                    popup.picture.setImage(download("/activity/live.jpg",
                                                    os.path.join(CACHE, f"live-{slot}.jpg")), False)
                except Exception:
                    pass
                last_frame = time.time()

        if monitor.waitForAbort(1.5 if popup else 2):
            break
    if popup:
        popup.close()


if __name__ == "__main__":
    main()
