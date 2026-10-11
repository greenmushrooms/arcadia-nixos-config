"""Couchboard doorbell: a background Kodi service.

Keeps a long poll open to the couchboard service (/activity/wait answers the moment
the Reolink NVR reports a ring, person, package, vehicle or animal). On a new event:

- a ring plays a half-volume chime first;
- if nothing is playing, Kodi plays the live doorbell stream (go2rtc RTSP relay)
  full screen, stopped 30 s after the activity ends (Back/Stop end it earlier);
- if something is playing, a picture-in-picture card top-right shows the doorbell
  picture refreshed every 1.5 s instead, so the movie isn't interrupted.
"""
import json
import os
import re
import subprocess
import time
import urllib.request
from datetime import datetime

import xbmc
import xbmcaddon
import xbmcgui
import xbmcvfs

BASE = "http://192.168.1.42:8790"
# go2rtc relay of the doorbell's light stream: kept connected by the Hub and a keyframe
# every second, so it starts fastest ("doorbell_hd" is sharper but slower to start).
STREAM = "rtsp://192.168.1.42:8554/doorbell"
QUIET_CLOSE = 30   # seconds after the activity ends
FRESH = 90         # only react to events newer than this
WAIT = 10          # long-poll window; short enough for a quick Kodi shutdown

ADDON = xbmcaddon.Addon()
BLACK = os.path.join(ADDON.getAddonInfo("path"), "resources", "black.png")
CHIME = os.path.join(ADDON.getAddonInfo("path"), "resources", "chime.wav")
CHIME_KINDS = {"doorbell"}   # ring only; a chime for every passer-by would get old fast
CACHE = xbmcvfs.translatePath(ADDON.getAddonInfo("profile"))
CHILDREN = []


def get_json(path, timeout=5):
    with urllib.request.urlopen(BASE + path, timeout=timeout) as r:
        return json.load(r)


def download(path, dest):
    with urllib.request.urlopen(BASE + path, timeout=8) as r, open(dest, "wb") as f:
        f.write(r.read())
    return dest


def chime():
    """Ding-dong at half volume through PipeWire, alongside whatever is playing."""
    try:
        CHILDREN.append(subprocess.Popen(["pw-play", "--volume", "0.5", CHIME],
                                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
    except OSError as e:
        xbmc.log(f"couchboard chime: {e!r}", xbmc.LOGWARNING)


def reap():
    CHILDREN[:] = [p for p in CHILDREN if p.poll() is None]


def plain(label):
    """Kodi's skin fonts have no emoji: "🔔 Doorbell" -> "Doorbell"."""
    return re.sub(r"[\U00010000-\U0010FFFF☀-➿️]", "", label).strip()


class Popup(xbmcgui.WindowDialog):
    """Top-right card: label + doorbell picture. Any button closes it."""

    def __init__(self, label, at):
        super().__init__()
        w, h = self.getWidth(), self.getHeight()
        cw, ch = int(w * 0.36), int(h * 0.46)
        x, y = w - cw - int(w * 0.025), int(h * 0.04)
        self.addControl(xbmcgui.ControlImage(x - 6, y - 6, cw + 12, ch + 12, BLACK, colorDiffuse="0xE6000000"))
        self.addControl(xbmcgui.ControlLabel(x + 14, y + 6, cw - 28, 50, label, "font_title", "FFFFD166"))
        self.addControl(xbmcgui.ControlLabel(x + 14, y + 6, cw - 28, 50, at, "font_title", "FFDFE5EC", alignment=1))
        self.picture = xbmcgui.ControlImage(x + 8, y + 60, cw - 16, ch - 68, "", aspectRatio=2)
        self.addControl(self.picture)
        self.closed = False

    def onAction(self, action):
        self.closed = True
        self.close()


class Doorbell:
    def __init__(self):
        self.player = xbmc.Player()
        self.popup = None
        self.streaming = False
        self.quiet_since = 0.0
        self.slot, self.last_frame = 0, 0.0

    def busy(self):
        return self.popup is not None or self.streaming

    def ours(self):
        try:
            return self.player.isPlaying() and self.player.getPlayingFile().startswith(STREAM)
        except RuntimeError:
            return False

    def on_event(self, ev):
        label = plain(ev["label"])
        at = datetime.fromisoformat(ev["at"]).strftime("%H:%M")
        if ev.get("kind") in CHIME_KINDS:
            chime()
        self.quiet_since = 0.0
        if self.ours():
            return                                   # already showing the door
        if not self.player.isPlaying():
            self.player.play(STREAM, xbmcgui.ListItem(f"{label} · {at}"))   # full screen, live
            self.streaming = True
            return
        if self.popup:
            self.popup.close()
        self.popup = Popup(label, at)
        self.popup.show()
        self.last_frame = 0.0

    def tick(self, active):
        """Called every 1.5 s while something is up."""
        self.quiet_since = 0.0 if active else (self.quiet_since or time.time())
        quiet_long = bool(self.quiet_since) and time.time() - self.quiet_since > QUIET_CLOSE
        if self.streaming:
            if not self.ours():
                self.streaming = False               # ended with Back/Stop
            elif quiet_long:
                self.player.stop()
                self.streaming = False
        if self.popup:
            if self.popup.closed or quiet_long:
                if not self.popup.closed:
                    self.popup.close()
                self.popup = None
            elif time.time() - self.last_frame > 1.5:
                self.slot ^= 1   # alternate files so Kodi never reads a half-written frame
                try:
                    self.popup.picture.setImage(download("/activity/live.jpg",
                                                         os.path.join(CACHE, f"live-{self.slot}.jpg")), False)
                except Exception:
                    pass
                self.last_frame = time.time()


def main():
    os.makedirs(CACHE, exist_ok=True)
    monitor = xbmc.Monitor()
    door = Doorbell()
    seen = None

    while not monitor.abortRequested():
        reap()
        try:
            if door.busy():
                a = get_json("/activity.json")
            else:   # first call only learns the latest id; after that, wait for news
                a = get_json(f"/activity/wait?after={seen or ''}&timeout={0 if seen is None else WAIT}",
                             timeout=WAIT + 5)
            newest = a["events"][0] if a["events"] else None
            if seen is None:
                seen = newest["id"] if newest else ""
            elif newest and newest["id"] != seen:
                seen = newest["id"]
                age = time.time() - datetime.fromisoformat(newest["at"]).timestamp()
                if age < FRESH:
                    door.on_event(newest)
            if door.busy():
                door.tick(bool(a["active"]))
        except Exception as e:
            xbmc.log(f"couchboard doorbell: {e!r}", xbmc.LOGWARNING)
            if monitor.waitForAbort(3):
                break
            continue
        if door.busy() and monitor.waitForAbort(1.5):
            break
    if door.popup:
        door.popup.close()


if __name__ == "__main__":
    main()
