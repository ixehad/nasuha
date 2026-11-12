#!/usr/bin/env python3
"""Download the approved sources into content-src/. Nothing here edits text.

    python3 tools/fetch_sources.py --agree-tanzil-terms     # Tanzil text + metadata
    python3 tools/fetch_sources.py --quranenc               # QuranEnc translations
    python3 tools/fetch_sources.py --quranenc --mukhtasar   # + Al-Mukhtasar tafsir

Tanzil: Arabic text only (never its translations). Its terms (CC BY 3.0, text
unchanged, credit kept) must be accepted by the maintainer, hence the flag.
QuranEnc: the ayah's Arabic in QuranEnc responses is dropped; Arabic comes from Tanzil.
"""

import argparse
import json
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "content-src"
UA = {"User-Agent": "content-fetch/1.0"}

TANZIL_TEXT = ("https://tanzil.net/pub/download/index.php?"
               "marks=true&sajdah=true&tatweel=true&quranType=uthmani&outType=xml&agree=true")
# No "rub" option: Tanzil then leaves out the rub el hizb sign, which marks a page division, not part of an ayah.
TANZIL_META = "https://tanzil.net/res/text/metadata/quran-data.xml"
QURANENC_LIST = "https://quranenc.com/api/v1/translations/list"
QURANENC_INDEX = "https://quranenc.com/en/home"
QURANENC_SURA = "https://quranenc.com/api/v1/translation/sura/{key}/{sura}"

TRANSLATIONS = {"english_saheeh": "en", "bengali_zakaria": "bn"}
MUKHTASAR = {"arabic_mokhtasar": "ar", "english_mokhtasar": "en", "bengali_mokhtasar": "bn"}


def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
        return r.read()


def fetch_tanzil():
    out = SRC / "tanzil"
    out.mkdir(parents=True, exist_ok=True)
    (out / "quran-uthmani.xml").write_bytes(get(TANZIL_TEXT))
    (out / "quran-data.xml").write_bytes(get(TANZIL_META))
    print("Tanzil text and metadata saved to", out)


def page_text(url):
    """A web page as plain text."""
    html = urllib.request.urlopen(
        urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"}), timeout=60).read().decode("utf-8", "replace")
    title = re.search(r"<title>(.*?)</title>", html, re.S)
    body = re.sub(r"<script.*?</script>|<style.*?</style>", "", html, flags=re.S)
    body = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", body))
    return (title.group(1).strip() if title else ""), body


def site_info(key):
    """Title, version and date of a translation that the API serves but leaves out of its list.

    They are read from QuranEnc's own pages: the title from the translation's page, and the
    version and date from the index, where each entry reads "22/05/2021 - V1.1.1 <title>".
    """
    try:
        title, _ = page_text(f"https://quranenc.com/en/browse/{key}")
    except urllib.error.HTTPError:
        return None
    title = title.replace(" - Encyclopedia of the Noble Quran", "").strip()
    _, index = page_text(QURANENC_INDEX)
    found = re.search(r"(\d\d/\d\d/\d{4}) - V(\d+(?:\.\d+)+) " + re.escape(title), index) if title else None
    if not found:
        return None
    return {"title": title, "version": found.group(2), "last_update": found.group(1)}


def fetch_quranenc(keys, kind):
    catalogue = {t["key"]: t for t in json.loads(get(QURANENC_LIST))["translations"]}
    out = SRC / "quranenc"
    out.mkdir(parents=True, exist_ok=True)
    for key, lang in keys.items():
        info = catalogue.get(key) or site_info(key)
        if not info:
            if kind == "tafsir":
                # Not published on QuranEnc in this language: leave it out.
                print(f"{key}: not published on QuranEnc, skipped")
                continue
            sys.exit(f"QuranEnc has no translation {key!r}, or its version could not be read")
        ayahs = []
        for sura in range(1, 115):
            for a in json.loads(get(QURANENC_SURA.format(key=key, sura=sura)))["result"]:
                ayahs.append({"sura": int(a["sura"]), "aya": int(a["aya"]),
                              "translation": a["translation"], "footnotes": a.get("footnotes") or ""})
            time.sleep(0.2)
        doc = {"key": key, "language": lang, "title": info.get("title", key), "version": str(info["version"]),
               "last_update": str(info.get("last_update", "")), "kind": kind,
               "source_url": f"https://quranenc.com/en/browse/{key}", "ayahs": ayahs}
        if kind == "tafsir":
            doc["book"] = "Al-Mukhtasar fi Tafsir al-Qur'an"
        (out / f"{key}.json").write_text(json.dumps(doc, ensure_ascii=False, indent=1), encoding="utf-8")
        print(f"{key} v{doc['version']}: {len(ayahs)} ayahs")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--agree-tanzil-terms", action="store_true")
    ap.add_argument("--quranenc", action="store_true")
    ap.add_argument("--mukhtasar", action="store_true")
    a = ap.parse_args()
    if not (a.agree_tanzil_terms or a.quranenc):
        ap.print_help()
        return
    if a.agree_tanzil_terms:
        fetch_tanzil()
    if a.quranenc:
        fetch_quranenc(TRANSLATIONS, "translation")
        if a.mukhtasar:
            fetch_quranenc(MUKHTASAR, "tafsir")


if __name__ == "__main__":
    main()
