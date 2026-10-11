#!/usr/bin/env python3
"""Download the GitHub avatar of every person in Resources/pitch/deck.json who has a `github`
handle, into Resources/pitch/faces/<handle>.png (bundled, so the pitch needs no network).
Python 3.9, stdlib only. Run: python3 scripts/fetch_faces.py  (or `make faces`)."""
import json
import os
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
DECK = os.path.join(HERE, "..", "Resources", "pitch", "deck.json")
OUT = os.path.join(HERE, "..", "Resources", "pitch", "faces")

os.makedirs(OUT, exist_ok=True)
with open(DECK) as f:
    deck = json.load(f)
for slide in deck["slides"]:
    for person in slide.get("people") or []:
        handle = person.get("github")
        if not handle:
            print("no handle:", person.get("name"))
            continue
        url = "https://github.com/%s.png?size=240" % handle
        with urllib.request.urlopen(url, timeout=20) as r:
            data = r.read()
        ext = ".jpg" if data[:3] == b"\xff\xd8\xff" else ".png"
        for stale in (".png", ".jpg"):
            if os.path.exists(os.path.join(OUT, handle + stale)):
                os.remove(os.path.join(OUT, handle + stale))
        path = os.path.join(OUT, handle + ext)
        with open(path, "wb") as out:
            out.write(data)
        print("saved", os.path.relpath(path, os.path.join(HERE, "..")))
