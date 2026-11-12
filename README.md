# Nasuha

A free iOS app, with its source code published, that sends one Qur'an ayah a day on the topics you pick, with the story and time of its revelation, a translation, and the ayahs around it.

No accounts, no analytics, no ads. Everything stays on the phone.

## Layout

| Path | What |
|---|---|
| `project.yml` | XcodeGen spec. The `.xcodeproj` is generated, not committed. |
| `Nasuha/` | The iOS app (SwiftUI, iOS 17+) |
| `Packages/NasuhaCore/` | Content reader (GRDB), SwiftData models, topic catalog, colour tokens. Builds and tests on macOS. |
| `tools/build_content.py` | Builds `Nasuha/Resources/nasuha.sqlite` from `content-src/`. The only way content gets into the app. |
| `content-src/` | Source files. See `content-src/README.md` and `CONTENT-POLICY.md`. |
| `docs/` | Release checklist |

## Build

Needs Xcode 16+ with the iOS platform installed, XcodeGen (`brew install xcodegen`) and Python 3 with PyYAML.

```bash
python3 tools/fetch_sources.py --agree-tanzil-terms --quranenc   # once: approved sources
python3 tools/build_content.py                                   # builds nasuha.sqlite
echo 'DEVELOPMENT_TEAM = YOUR_TEAM_ID' > Config/Signing.local.xcconfig
xcodegen generate
open Nasuha.xcodeproj
```

For a release build use `python3 tools/build_content.py --release`, which fails if any sample set is included.

## Tests

```bash
python3 -m unittest discover -s tools/tests      # content pipeline and validation
cd Packages/NasuhaCore && swift test             # reader, models, palette contrast
```

The Python tests also rebuild `Packages/NasuhaCore/Tests/NasuhaCoreTests/Fixtures/content-fixture.sqlite`, which the Swift tests read. Fixtures hold placeholder strings ("FIXTURE 2:3"), never Qur'an text.

## Content rules

Read `CONTENT-POLICY.md` before adding anything. The build fails when a story or timing block has no refs, a book is not on the allowlist, a hadith or asbab report is not graded sahih or hasan, an ayah key does not exist, or a set has no context ayahs.

## Licence

The code is under the [PolyForm Noncommercial License 1.0.0](LICENSE).

**You may:** use the app and its code for free, study it, change it, and share it, for personal, religious, educational or other non-commercial purposes.

**You may not:** sell the app or a copy of it, publish a paid or ad-supported version, or use the code in a commercial product.

**Name and logo:** "Nasuha" and its logo are not covered by the licence. A copy or changed version must use its own name and logo.

The code is publicly available, but this is not an OSI-approved open-source licence, because those licences cannot forbid selling.

Qur'an text, translations, tafsir and fonts keep their own licences. See `CREDITS.md`.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
