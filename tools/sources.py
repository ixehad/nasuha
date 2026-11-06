"""The source allowlist from CONTENT-POLICY.md, in a form the build can check.

Every `book` in a curated set must be one of these canonical names (or an alias).
Adding a book here means changing CONTENT-POLICY.md first; tests check that each
canonical name below is named in the policy (the four Sunan are covered by its
"the Sunan with a stated grade" row).
"""

# kind:
#   hadith      needs number, numbering "sunnah.com", and a grade of sahih or hasan
#   asbab       needs a grade of sahih or hasan (checked against as-Sahih al-Musnad)
#   tafsir      needs a location or ayah
#   quran       needs an ayah
#   chronology  revelation order
#   grading     the grading reference for asbab reports
BOOKS = {
    "Sahih al-Bukhari": {"kind": "hadith", "aliases": ["Bukhari"]},
    "Sahih Muslim": {"kind": "hadith", "aliases": ["Muslim"]},
    "Sunan Abi Dawud": {"kind": "hadith", "aliases": [], "policy_row": "the Sunan"},
    "Jami' at-Tirmidhi": {"kind": "hadith", "aliases": [], "policy_row": "the Sunan"},
    "Sunan an-Nasa'i": {"kind": "hadith", "aliases": [], "policy_row": "the Sunan"},
    "Sunan Ibn Majah": {"kind": "hadith", "aliases": [], "policy_row": "the Sunan"},
    "Asbab al-Nuzul (al-Wahidi)": {"kind": "asbab", "aliases": ["al-Wahidi"], "policy_row": "al-Wahidi"},
    "Lubab an-Nuqul (as-Suyuti)": {"kind": "asbab", "aliases": ["Lubab an-Nuqul"], "policy_row": "Lubab an-Nuqul"},
    "as-Sahih al-Musnad min Asbab an-Nuzul": {"kind": "grading", "aliases": []},
    "Al-Mukhtasar fi Tafsir al-Qur'an": {"kind": "tafsir", "aliases": ["Al-Mukhtasar fi Tafsir"]},
    "Tafsir Ibn Kathir": {"kind": "tafsir", "aliases": []},
    "Tafsir as-Sa'di": {"kind": "tafsir", "aliases": []},
    "Qur'an": {"kind": "quran", "aliases": ["Quran"], "policy_row": "Qur'an"},
    "1924 Cairo mushaf chronology": {"kind": "chronology", "aliases": [], "policy_row": "1924 Cairo"},
}

ACCEPTED_GRADES = {"sahih", "hasan", "hasan sahih"}

_ALIAS = {}
for name, info in BOOKS.items():
    _ALIAS[name.lower()] = name
    for a in info["aliases"]:
        _ALIAS[a.lower()] = name


def canonical(book):
    """Canonical book name, or None if the book is not on the allowlist."""
    if not isinstance(book, str):
        return None
    return _ALIAS.get(book.strip().lower())


def kind(book):
    name = canonical(book)
    return BOOKS[name]["kind"] if name else None


def normalise_grade(grade):
    if not isinstance(grade, str):
        return None
    g = grade.strip().lower().replace("ṣ", "s").replace("ḥ", "h").replace("-", " ")
    return " ".join(g.split())
