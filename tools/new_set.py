#!/usr/bin/env python3
"""Start a curated ayah set: writes content-src/sets/<id>.yaml ready to fill in.

    python3 tools/new_set.py hope 93:3
    python3 tools/new_set.py patience,grief 2:155

The file gets the ayah, the two ayahs before and after it in the same surah,
and the topics. The story and timing blocks are left commented out: fill them
in from the books in CONTENT-POLICY.md, word for word, then remove the "#".
This script never writes religious text.
"""

import argparse
import json
import pathlib
import re
import sys

import build_content

TOOLS = pathlib.Path(__file__).resolve().parent
ROOT = TOOLS.parent

TEMPLATE = """\
id: {id}
topics: [{topics}]
ayah: "{ayah}"
context: {{ before: [{before}], after: [{after}] }}

# The story of its revelation. Leave this block out if there is no report
# graded sahih or hasan. Copy the text from the source unchanged.
# story:
#   steps:
#     - {{ text: "", lang: en }}
#   one_line: null
#   refs:
#     - {{ book: "", number: "", numbering: "sunnah.com", grade: "" }}

# When it was revealed. Leave this block out if the sources do not say.
# when:
#   place: {place}
#   order: {order}
#   period_text: ""
#   age_min:
#   age_max:
#   approx: true
#   scholars_differ: false
#   refs: [ {{ book: "", location: "" }} ]

tafsir_refs: [ {{ book: "Al-Mukhtasar fi Tafsir", ayah: "{ayah}" }} ]
"""


def slug(name):
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("topics", help="one topic id, or several separated by commas")
    parser.add_argument("ayah", help="surah:ayah, for example 93:3")
    parser.add_argument("--src", type=pathlib.Path, default=ROOT / "content-src")
    args = parser.parse_args(argv)

    known = set(json.loads((TOOLS / "topic_ids.json").read_text()))
    topics = [t.strip() for t in args.topics.split(",") if t.strip()]
    unknown = [t for t in topics if t not in known]
    if unknown:
        sys.exit(f"unknown topic: {', '.join(unknown)}\nknown topics: {', '.join(sorted(known))}")

    meta_path = args.src / "tanzil" / "quran-data.xml"
    if not meta_path.exists():
        sys.exit("missing content-src/tanzil/quran-data.xml (run tools/fetch_sources.py)")
    surahs = build_content.read_tanzil_meta(meta_path)

    match = re.fullmatch(r"(\d+):(\d+)", args.ayah)
    if not match:
        sys.exit("the ayah must look like 93:3")
    surah, ayah = int(match.group(1)), int(match.group(2))
    info = surahs.get(surah)
    if not info or not 1 <= ayah <= info["ayah_count"]:
        sys.exit(f"{args.ayah} does not exist")

    before = [f'"{surah}:{n}"' for n in range(max(1, ayah - 2), ayah)]
    after = [f'"{surah}:{n}"' for n in range(ayah + 1, min(info["ayah_count"], ayah + 2) + 1)]
    if not before and not after:
        sys.exit(f"{args.ayah} has no ayahs around it in its surah")

    set_id = f"{slug(info['name_translit'])}-{surah}-{ayah}"
    out = args.src / "sets" / f"{set_id}.yaml"
    if out.exists():
        sys.exit(f"{out} already exists")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(TEMPLATE.format(
        id=set_id, topics=", ".join(topics), ayah=args.ayah,
        before=", ".join(before), after=", ".join(after),
        place=info["place"] or "", order=info["order"] if info["order"] is not None else "",
    ), encoding="utf-8")
    print(f"wrote {out.relative_to(ROOT) if out.is_relative_to(ROOT) else out}")


if __name__ == "__main__":
    main()
