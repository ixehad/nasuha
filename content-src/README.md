# content-src

Everything in this folder goes into the app through `tools/build_content.py`, unchanged. Read `CONTENT-POLICY.md` before adding anything.

| Path | Contents | Source |
|---|---|---|
| `tanzil/` | `quran-uthmani.xml`, `quran-data.xml` | `tools/fetch_sources.py --agree-tanzil-terms` |
| `quranenc/` | `english_saheeh.json`, `bengali_zakaria.json`, optional Al-Mukhtasar | `tools/fetch_sources.py --quranenc` |
| `meta/revelation_order_cairo1924.csv` | `surah,order` | 1924 Cairo mushaf chronology |
| `sets/*.yaml` | Curated ayah sets, one per file | Written by hand |
| `sample/*.yaml` | Sample sets. First line: `# SAMPLE – replace from source` | Written by hand |
| `tafsir/*.yaml` | Tafsir Ibn Kathir and Tafsir as-Sa'di excerpts | Written by hand |
| `topic_order.yaml` | `{topic: [set ids]}`: the reading order within each topic | Written by hand |

Sets not listed in `topic_order.yaml` follow in mushaf order.

## Ayah set format

```yaml
id: duha-93-3
topics: [hope, why]
ayah: "93:3"
context: { before: ["93:1", "93:2"], after: ["93:4", "93:5"] }
story:                      # optional; leave out if there is no authentic report
  steps:
    - { text: "...", lang: en }       # copied from the source, unchanged
  one_line: null            # only if the source gives one
  refs:
    - { book: "Sahih al-Bukhari", number: "4950", numbering: "sunnah.com", grade: "sahih" }
when:                       # optional
  place: makkah             # makkah or madinah
  order: 11
  period_text: "Year 1–2 of prophethood"
  age_min: 40
  age_max: 41
  approx: true
  scholars_differ: true
  refs: [ { book: "Tafsir Ibn Kathir", location: "93:1–3" } ]
tafsir_refs: [ { book: "Al-Mukhtasar fi Tafsir", ayah: "93:3" } ]
```

## Tafsir excerpt format

```yaml
- { book: "Tafsir Ibn Kathir", ayah: "93:3", lang: en, text: "...", location: "edition, volume, page" }
```

## The build fails when

- a story or `when` block has no refs
- a book is not on the allowlist (`tools/sources.py`, which mirrors `CONTENT-POLICY.md`)
- a hadith or asbab report has no grade, or a grade other than sahih or hasan
- a hadith ref has no number in sunnah.com numbering
- an ayah or context key does not exist, or a context ayah is on the wrong side
- a set has no context ayahs
- an age or period is not marked `approx: true`
- a revelation order differs from the 1924 Cairo chronology
- a sample file is missing its first-line marker, or `--release` is used while samples are present
