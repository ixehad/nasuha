#!/usr/bin/env python3
"""Build Nasuha/Resources/nasuha.sqlite from content-src/.

This is the only way content gets into the app. It copies source text
unchanged and refuses to build when a curated set breaks CONTENT-POLICY.md.

    python3 tools/build_content.py                 # real sets + samples
    python3 tools/build_content.py --release       # fails if any sample is included
    python3 tools/build_content.py --src DIR --out FILE

Inputs (under --src):
    tanzil/quran-uthmani.xml          Tanzil Uthmani text (Arabic only)        required
    tanzil/quran-data.xml             Tanzil metadata (names, type, counts)    required
    meta/revelation_order_cairo1924.csv   surah,order                          optional
    quranenc/*.json                   QuranEnc translations and Al-Mukhtasar   optional
    tafsir/*.yaml                     curated Ibn Kathir / as-Sa'di excerpts    optional
    sets/*.yaml                       curated ayah sets (maintainer)           optional
    sample/*.yaml                     sample sets, marked "# SAMPLE"           optional
    topic_order.yaml                  {topic: [set ids]} curated order         optional
"""

import argparse
import csv
import datetime as dt
import hashlib
import json
import os
import re
import sqlite3
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

import yaml

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))
import sources  # noqa: E402

SCHEMA_VERSION = 1
SAMPLE_MARKER = "# SAMPLE – replace from source"
TOPIC_IDS = set(json.loads((TOOLS / "topic_ids.json").read_text()))
KEY_RE = re.compile(r"^\s*(\d{1,3})\s*:\s*(\d{1,3})\s*$")


class BuildError(Exception):
    def __init__(self, errors):
        super().__init__("\n".join(errors))
        self.errors = errors


# ---------------------------------------------------------------- readers

def read_tanzil_text(path):
    """{(surah, ayah): text}, {surah: bismillah}, version string."""
    tree = ET.parse(path)
    root = tree.getroot()
    ayahs, bismillah = {}, {}
    for sura in root.iter("sura"):
        s = int(sura.get("index"))
        for aya in sura.iter("aya"):
            a = int(aya.get("index"))
            ayahs[(s, a)] = aya.get("text")
            if aya.get("bismillah") and a == 1:
                bismillah[s] = aya.get("bismillah")
    raw = Path(path).read_text(encoding="utf-8")
    m = re.search(r"Version:?\s*([0-9][0-9.]*)", raw)
    return ayahs, bismillah, (m.group(1) if m else "")


def read_tanzil_meta(path):
    out = {}
    for sura in ET.parse(path).getroot().iter("sura"):
        n = int(sura.get("index"))
        t = (sura.get("type") or "").lower()
        out[n] = {
            "name_ar": sura.get("name"),
            "name_translit": sura.get("tname"),
            "name_en": sura.get("ename"),
            "place": "makkah" if t.startswith("mec") else "madinah" if t.startswith("med") else None,
            "ayah_count": int(sura.get("ayas")),
        }
    return out


def read_chronology(path):
    if not path.exists():
        return {}
    with open(path, newline="", encoding="utf-8") as f:
        return {int(r["surah"]): int(r["order"]) for r in csv.DictReader(f)}


def parse_key(value):
    if not isinstance(value, str):
        return None
    m = KEY_RE.match(value)
    return (int(m.group(1)), int(m.group(2))) if m else None


def load_yaml(path):
    text = path.read_text(encoding="utf-8")
    return text, yaml.safe_load(text)


# ---------------------------------------------------------------- validation

def check_ref(ref, where, errors):
    """Returns a normalised ref dict, appending errors as it goes."""
    if not isinstance(ref, dict):
        errors.append(f"{where}: a ref must be a mapping")
        return None
    book = ref.get("book")
    name = sources.canonical(book)
    if not name:
        errors.append(f"{where}: book {book!r} is not on the allowlist in CONTENT-POLICY.md")
        return None
    k = sources.BOOKS[name]["kind"]
    grade = ref.get("grade")
    if k in ("hadith", "asbab"):
        g = sources.normalise_grade(grade)
        if not g:
            errors.append(f"{where}: {name} ref has no grade")
        elif g not in sources.ACCEPTED_GRADES:
            errors.append(f"{where}: {name} ref is graded {grade!r}; only sahih or hasan are allowed")
    if k == "hadith":
        if not ref.get("number"):
            errors.append(f"{where}: {name} ref has no number")
        if (ref.get("numbering") or "").lower() != "sunnah.com":
            errors.append(f"{where}: {name} ref must use sunnah.com numbering")
    if k == "tafsir" and not (ref.get("location") or ref.get("ayah")):
        errors.append(f"{where}: {name} ref needs a location or ayah")
    if k == "quran" and not parse_key(str(ref.get("ayah") or "").split("–")[0].split("-")[0]):
        errors.append(f"{where}: Qur'an ref needs an ayah like \"93:3\"")
    return {
        "book": name,
        "number": _str(ref.get("number")),
        "numbering": _str(ref.get("numbering")),
        "grade": _str(grade),
        "location": _str(ref.get("location")),
        "ayah": _str(ref.get("ayah")),
        "edition": _str(ref.get("edition")),
        "page": _str(ref.get("page")),
    }


def check_refs(refs, where, errors):
    out = []
    for i, ref in enumerate(refs or []):
        r = check_ref(ref, f"{where} {i + 1}", errors)
        if r:
            out.append(r)
    return out


def _str(v):
    return None if v is None else str(v)


def check_set(data, path, quran, chronology, errors):
    where = f"{path.name}"
    if not isinstance(data, dict):
        errors.append(f"{where}: not a mapping")
        return None
    sid = data.get("id")
    if not sid or not isinstance(sid, str):
        errors.append(f"{where}: missing id")
        return None
    where = f"{path.name} ({sid})"

    key = parse_key(data.get("ayah"))
    if not key:
        errors.append(f"{where}: ayah {data.get('ayah')!r} is not a surah:ayah key")
    elif key not in quran:
        errors.append(f"{where}: ayah {data.get('ayah')} does not exist")

    topics = data.get("topics") or []
    if not topics:
        errors.append(f"{where}: no topics")
    for t in topics:
        if t not in TOPIC_IDS:
            errors.append(f"{where}: unknown topic {t!r}")

    ctx = data.get("context") or {}
    before = ctx.get("before") or []
    after = ctx.get("after") or []
    if not before and not after:
        errors.append(f"{where}: no context ayahs")
    ctx_keys = {"before": [], "after": []}
    for role, items in (("before", before), ("after", after)):
        for raw in items:
            k = parse_key(raw)
            if not k:
                errors.append(f"{where}: context {role} {raw!r} is not a surah:ayah key")
            elif k not in quran:
                errors.append(f"{where}: context ayah {raw} does not exist")
            elif key and (k[0] != key[0] or (k[1] >= key[1] if role == "before" else k[1] <= key[1])):
                errors.append(f"{where}: context {role} {raw} is not {role} {data.get('ayah')} in the same surah")
            else:
                ctx_keys[role].append(k)

    story = None
    if data.get("story") is not None:
        st = data["story"]
        refs = st.get("refs") or []
        if not refs:
            errors.append(f"{where}: story has no refs")
        steps = []
        for i, step in enumerate(st.get("steps") or []):
            if not isinstance(step, dict) or not step.get("text") or not step.get("lang"):
                errors.append(f"{where}: story step {i + 1} needs text and lang")
                continue
            steps.append({"text": step["text"], "lang": step["lang"]})
        if not steps:
            errors.append(f"{where}: story has no steps")
        one_line = st.get("one_line")
        ol_text = ol_lang = None
        if isinstance(one_line, dict):
            ol_text, ol_lang = one_line.get("text"), one_line.get("lang")
        elif isinstance(one_line, str):
            ol_text, ol_lang = one_line, steps[0]["lang"] if steps else None
        story = {
            "steps": steps,
            "one_line": ol_text,
            "one_line_lang": ol_lang,
            "refs": check_refs(refs, f"{where} story ref", errors),
        }

    when = None
    if data.get("when") is not None:
        w = data["when"]
        refs = w.get("refs") or []
        if not refs:
            errors.append(f"{where}: when has no refs")
        place = w.get("place")
        if place not in (None, "makkah", "madinah"):
            errors.append(f"{where}: when.place must be makkah or madinah")
        approx = w.get("approx", True)
        if (w.get("age_min") is not None or w.get("age_max") is not None or w.get("period_text")) and approx is not True:
            errors.append(f"{where}: dates and ages must be marked approx: true")
        order = w.get("order")
        if key and order is not None and chronology.get(key[0]) not in (None, order):
            errors.append(f"{where}: when.order {order} differs from the 1924 Cairo chronology ({chronology[key[0]]})")
        when = {
            "place": place,
            "order": order,
            "period_text": w.get("period_text"),
            "age_min": w.get("age_min"),
            "age_max": w.get("age_max"),
            "approx": True if approx is None else bool(approx),
            "scholars_differ": bool(w.get("scholars_differ", False)),
            "refs": check_refs(refs, f"{where} when ref", errors),
        }

    tafsir_refs = check_refs(data.get("tafsir_refs"), f"{where} tafsir ref", errors)

    return {
        "id": sid,
        "key": key,
        "topics": topics,
        "before": ctx_keys["before"],
        "after": ctx_keys["after"],
        "story": story,
        "when": when,
        "tafsir_refs": tafsir_refs,
    }


# ---------------------------------------------------------------- build

def build(src, out, release=False, include_samples=True):
    src, out = Path(src), Path(out)
    errors = []
    inputs = []

    text_path = src / "tanzil" / "quran-uthmani.xml"
    meta_path = src / "tanzil" / "quran-data.xml"
    for p in (text_path, meta_path):
        if not p.exists():
            errors.append(f"missing {p} (run tools/fetch_sources.py)")
    if errors:
        raise BuildError(errors)
    inputs += [text_path, meta_path]

    quran, bismillah, tanzil_version = read_tanzil_text(text_path)
    surahs = read_tanzil_meta(meta_path)
    chron_path = src / "meta" / "revelation_order_cairo1924.csv"
    chronology = read_chronology(chron_path)
    if chron_path.exists():
        inputs.append(chron_path)

    for n, s in surahs.items():
        have = sum(1 for (sn, _) in quran if sn == n)
        if have != s["ayah_count"]:
            errors.append(f"surah {n}: metadata says {s['ayah_count']} ayahs, text has {have}")

    # Translations and Al-Mukhtasar from QuranEnc
    translations, tafsir_rows = [], []
    for p in sorted((src / "quranenc").glob("*.json")):
        inputs.append(p)
        doc = json.loads(p.read_text(encoding="utf-8"))
        for field in ("key", "language", "title", "version", "ayahs"):
            if not doc.get(field):
                errors.append(f"{p.name}: missing {field}")
        if errors:
            continue
        if doc.get("kind", "translation") == "tafsir":
            book = sources.canonical(doc.get("book"))
            if book != "Al-Mukhtasar fi Tafsir al-Qur'an":
                errors.append(f"{p.name}: QuranEnc tafsir must be Al-Mukhtasar, got {doc.get('book')!r}")
                continue
            for a in doc["ayahs"]:
                tafsir_rows.append((book, doc["language"], int(a["sura"]), int(a["aya"]), a["translation"],
                                    f"QuranEnc {doc['key']} v{doc['version']}"))
        else:
            translations.append(doc)

    for p in sorted((src / "tafsir").glob("*.yaml")):
        inputs.append(p)
        _, items = load_yaml(p)
        for i, item in enumerate(items or []):
            where = f"{p.name} item {i + 1}"
            book = sources.canonical(item.get("book"))
            if not book or sources.BOOKS[book]["kind"] != "tafsir":
                errors.append(f"{where}: book {item.get('book')!r} is not an allowed tafsir")
                continue
            k = parse_key(item.get("ayah"))
            if not k or k not in quran:
                errors.append(f"{where}: ayah {item.get('ayah')!r} does not exist")
                continue
            if not item.get("text") or not item.get("lang") or not item.get("location"):
                errors.append(f"{where}: needs text, lang and location")
                continue
            tafsir_rows.append((book, item["lang"], k[0], k[1], item["text"], str(item["location"])))

    # Curated sets
    set_files = [(p, False) for p in sorted((src / "sets").glob("*.yaml"))]
    if include_samples:
        set_files += [(p, True) for p in sorted((src / "sample").glob("*.yaml"))]
    sets, seen = [], set()
    for p, is_sample in set_files:
        inputs.append(p)
        text, data = load_yaml(p)
        if is_sample and not text.lstrip().startswith(SAMPLE_MARKER):
            errors.append(f"{p.name}: sample files must start with '{SAMPLE_MARKER}'")
        if is_sample and release:
            errors.append(f"{p.name}: sample content can't ship in a release build")
        s = check_set(data, p, quran, chronology, errors)
        if s:
            if s["id"] in seen:
                errors.append(f"{p.name}: duplicate id {s['id']}")
            seen.add(s["id"])
            s["is_sample"] = is_sample
            sets.append(s)

    order_path = src / "topic_order.yaml"
    curated_order = {}
    if order_path.exists():
        inputs.append(order_path)
        _, curated_order = load_yaml(order_path)
        curated_order = curated_order or {}
        by_id = {s["id"]: s for s in sets}
        for topic, ids in curated_order.items():
            for sid in ids or []:
                if sid not in by_id:
                    errors.append(f"topic_order.yaml: {topic}: unknown set {sid}")
                elif topic not in by_id[sid]["topics"]:
                    errors.append(f"topic_order.yaml: set {sid} is not tagged {topic}")

    if errors:
        raise BuildError(errors)

    # Topic positions: curated order first, then mushaf order.
    topic_rows = []
    for topic in sorted(TOPIC_IDS):
        members = [s for s in sets if topic in s["topics"]]
        listed = [sid for sid in (curated_order.get(topic) or [])]
        rest = sorted((s for s in members if s["id"] not in listed), key=lambda s: (s["key"], s["id"]))
        for pos, sid in enumerate(listed + [s["id"] for s in rest]):
            topic_rows.append((sid, topic, pos))

    digest = hashlib.sha256()
    for p in sorted(set(inputs)):
        digest.update(p.name.encode())
        digest.update(p.read_bytes())
    today = dt.date.today()
    content_version = f"{today:%Y.%m.%d}-{digest.hexdigest()[:8]}"

    out.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(suffix=".sqlite", dir=out.parent)
    os.close(fd)
    con = sqlite3.connect(tmp)
    try:
        con.execute("PRAGMA journal_mode = DELETE")
        con.executescript((TOOLS / "schema.sql").read_text())
        meta = {
            "schema_version": str(SCHEMA_VERSION),
            "content_version": content_version,
            "built_at": today.isoformat(),
            "tanzil_version": tanzil_version,
            "tanzil_credit": "Tanzil Quran Text (Uthmani), tanzil.net, CC BY 3.0",
            "has_chronology": "1" if chronology else "0",
            "sample_sets": str(sum(1 for s in sets if s["is_sample"])),
        }
        con.executemany("INSERT INTO meta VALUES (?, ?)", meta.items())
        con.executemany(
            "INSERT INTO surah VALUES (?,?,?,?,?,?,?,?)",
            [(n, s["name_ar"], s["name_translit"], s["name_en"], s["place"], s["ayah_count"],
              chronology.get(n), bismillah.get(n)) for n, s in sorted(surahs.items())])
        con.executemany("INSERT INTO ayah VALUES (?,?,?)",
                        [(s, a, t) for (s, a), t in sorted(quran.items())])
        for doc in translations:
            con.execute("INSERT INTO translation_source VALUES (?,?,?,?,?)",
                        (doc["key"], doc["language"], doc["title"], str(doc["version"]), doc.get("last_update")))
            con.executemany(
                "INSERT INTO translation VALUES (?,?,?,?,?)",
                [(doc["key"], int(a["sura"]), int(a["aya"]), a["translation"], a.get("footnotes") or None)
                 for a in doc["ayahs"]])
        con.executemany("INSERT INTO tafsir VALUES (?,?,?,?,?,?)", tafsir_rows)
        for s in sets:
            st, w = s["story"], s["when"]
            con.execute(
                "INSERT INTO ayah_set VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                (s["id"], s["key"][0], s["key"][1], int(s["is_sample"]),
                 int(st is not None), st and st["one_line"], st and st["one_line_lang"],
                 int(w is not None), w and w["place"], w and w["order"], w and w["period_text"],
                 w and w["age_min"], w and w["age_max"], int(w["approx"]) if w else 1,
                 int(w["scholars_differ"]) if w else 0))
            for role in ("before", "after"):
                con.executemany("INSERT INTO ayah_set_context VALUES (?,?,?,?,?)",
                                [(s["id"], role, i, k[0], k[1]) for i, k in enumerate(s[role])])
            if st:
                con.executemany("INSERT INTO story_step VALUES (?,?,?,?)",
                                [(s["id"], i, x["lang"], x["text"]) for i, x in enumerate(st["steps"])])
            for block, refs in (("story", st and st["refs"]), ("when", w and w["refs"]), ("tafsir", s["tafsir_refs"])):
                con.executemany(
                    "INSERT INTO source_ref VALUES (?,?,?,?,?,?,?,?,?,?,?)",
                    [(s["id"], block, i, r["book"], r["number"], r["numbering"], r["grade"], r["location"],
                      r["ayah"], r["edition"], r["page"]) for i, r in enumerate(refs or [])])
        con.executemany("INSERT INTO ayah_set_topic VALUES (?,?,?)", topic_rows)
        con.commit()
        con.execute("VACUUM")
    finally:
        con.close()
    os.replace(tmp, out)
    return {
        "content_version": content_version,
        "surahs": len(surahs),
        "ayahs": len(quran),
        "translations": [d["key"] for d in translations],
        "sets": len(sets),
        "samples": sum(1 for s in sets if s["is_sample"]),
        "topics_with_sets": sorted({t for (_, t, _) in topic_rows}),
    }


def main(argv=None):
    root = TOOLS.parent
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--src", default=root / "content-src")
    ap.add_argument("--out", default=root / "Nasuha" / "Resources" / "nasuha.sqlite")
    ap.add_argument("--release", action="store_true", help="fail if any sample set is included")
    ap.add_argument("--no-samples", action="store_true", help="leave out content-src/sample/")
    args = ap.parse_args(argv)
    try:
        summary = build(args.src, args.out, release=args.release, include_samples=not args.no_samples)
    except BuildError as e:
        print(f"Build failed with {len(e.errors)} problem(s):", file=sys.stderr)
        for err in e.errors:
            print(f"  - {err}", file=sys.stderr)
        return 1
    print(f"Built {args.out}")
    for k, v in summary.items():
        print(f"  {k}: {v}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
