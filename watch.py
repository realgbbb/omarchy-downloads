#!/usr/bin/env python3
"""Stream JSON snapshots of a downloads folder, one line per change.

The Omarchy shell starts this once and reads stdout line by line. Every line is
a complete snapshot, so the panel never has to reconcile deltas:

    {"ok": true, "dir": "...", "total": 137, "files": [ ... ]}

Changes are picked up through inotify, which is why a finished download lights
the bar icon the instant it lands instead of on the next poll tick. If inotify
is unavailable (an exotic filesystem, a hardened kernel, fd exhaustion) the
watcher silently degrades to a 2 second poll — the shell can't tell the
difference apart from the latency.

Usage: watch.py [folder] [limit] [--once]
"""

import ctypes
import ctypes.util
import json
import os
import select
import sys
import time

# Suffixes browsers and download managers use for a file that is still being
# written. These are listed but never counted as an "arrival" — the arrival is
# the rename to the final name, which is the moment worth animating.
# Deliberately excludes .tmp/.temp: plenty of tools leave those behind for
# good, and a permanently lit "downloading" indicator is worse than a missed
# one.
PARTIAL_SUFFIXES = (
    ".crdownload", ".part", ".partial", ".download", ".opdownload",
    ".aria2", ".!ut",
)

# inotify event bits (linux/inotify.h)
IN_MODIFY = 0x00000002
IN_ATTRIB = 0x00000004
IN_CLOSE_WRITE = 0x00000008
IN_MOVED_FROM = 0x00000040
IN_MOVED_TO = 0x00000080
IN_CREATE = 0x00000100
IN_DELETE = 0x00000200
IN_DELETE_SELF = 0x00000400
IN_MOVE_SELF = 0x00000800
WATCH_MASK = (IN_MODIFY | IN_ATTRIB | IN_CLOSE_WRITE | IN_MOVED_FROM
              | IN_MOVED_TO | IN_CREATE | IN_DELETE | IN_DELETE_SELF
              | IN_MOVE_SELF)

# A burst of events (a browser writing a 2GB file) collapses into one snapshot.
DEBOUNCE_SEC = 0.35
# Re-check even when nothing fired, so a folder that gets replaced wholesale or
# a watch that dies quietly still recovers.
HEARTBEAT_SEC = 30.0
POLL_SEC = 2.0


def resolve_folder(requested):
    """Requested path, else the XDG download dir, else ~/Downloads."""
    if requested:
        return os.path.abspath(os.path.expanduser(requested))

    home = os.path.expanduser("~")
    config = os.environ.get("XDG_CONFIG_HOME") or os.path.join(home, ".config")
    try:
        with open(os.path.join(config, "user-dirs.dirs"), encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line.startswith("XDG_DOWNLOAD_DIR="):
                    continue
                value = line.split("=", 1)[1].strip().strip('"')
                return os.path.abspath(value.replace("$HOME", home))
    except OSError:
        pass
    return os.path.join(home, "Downloads")


def snapshot(folder, limit):
    files = []
    try:
        with os.scandir(folder) as entries:
            for entry in entries:
                if entry.name.startswith("."):
                    continue
                try:
                    stat = entry.stat(follow_symlinks=False)
                except OSError:
                    continue
                lowered = entry.name.lower()
                files.append({
                    "name": entry.name,
                    "path": os.path.join(folder, entry.name),
                    "sizeBytes": int(stat.st_size),
                    "modifiedTs": int(stat.st_mtime),
                    "isDir": entry.is_dir(follow_symlinks=False),
                    "partial": lowered.endswith(PARTIAL_SUFFIXES),
                })
    except OSError as exc:
        return {"ok": False, "dir": folder, "error": str(exc),
                "total": 0, "partials": 0, "files": []}

    files.sort(key=lambda item: (item["modifiedTs"], item["name"]), reverse=True)
    return {
        "ok": True,
        "dir": folder,
        "total": len(files),
        "partials": sum(1 for item in files if item["partial"]),
        "files": files[:limit],
    }


def emit(payload):
    sys.stdout.write(json.dumps(payload, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def open_inotify(folder):
    """Return (fd, libc) or (None, None) when inotify isn't usable."""
    try:
        libc = ctypes.CDLL(ctypes.util.find_library("c"), use_errno=True)
        libc.inotify_init1.argtypes = [ctypes.c_int]
        libc.inotify_init1.restype = ctypes.c_int
        libc.inotify_add_watch.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_uint32]
        libc.inotify_add_watch.restype = ctypes.c_int
    except (OSError, AttributeError, TypeError):
        return None, None

    fd = libc.inotify_init1(0)
    if fd < 0:
        return None, None
    if libc.inotify_add_watch(fd, folder.encode("utf-8"), WATCH_MASK) < 0:
        os.close(fd)
        return None, None
    return fd, libc


def drain(fd):
    """Swallow every queued event; the snapshot is the source of truth."""
    try:
        os.read(fd, 65536)
    except OSError:
        pass


def watch(fd, folder, limit, last):
    while True:
        ready, _, _ = select.select([fd], [], [], HEARTBEAT_SEC)
        if ready:
            drain(fd)
            # Collapse the tail of the burst before taking a reading.
            deadline = time.monotonic() + DEBOUNCE_SEC
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    break
                more, _, _ = select.select([fd], [], [], remaining)
                if not more:
                    break
                drain(fd)

        current = snapshot(folder, limit)
        if current != last:
            emit(current)
            last = current


def poll(folder, limit, last):
    while True:
        time.sleep(POLL_SEC)
        current = snapshot(folder, limit)
        if current != last:
            emit(current)
            last = current


def main():
    args = [a for a in sys.argv[1:] if a != "--once"]
    once = "--once" in sys.argv

    folder = resolve_folder(args[0] if args else "")
    try:
        limit = max(1, min(500, int(args[1])))
    except (IndexError, ValueError):
        limit = 25

    last = snapshot(folder, limit)
    emit(last)
    if once:
        return 0

    fd, _libc = open_inotify(folder)
    try:
        if fd is None:
            poll(folder, limit, last)
        else:
            watch(fd, folder, limit, last)
    except KeyboardInterrupt:
        return 0
    finally:
        if fd is not None:
            os.close(fd)
    return 0


if __name__ == "__main__":
    sys.exit(main())
