-- nasuha.sqlite schema. Built only by tools/build_content.py.
-- Bump SCHEMA_VERSION in build_content.py and ContentStore.swift together.

CREATE TABLE meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE surah (
  number           INTEGER PRIMARY KEY,
  name_ar          TEXT NOT NULL,
  name_translit    TEXT NOT NULL,
  name_en          TEXT NOT NULL,
  place            TEXT CHECK (place IN ('makkah', 'madinah')),
  ayah_count       INTEGER NOT NULL,
  revelation_order INTEGER,            -- 1924 Cairo mushaf chronology
  bismillah        TEXT                -- as Tanzil gives it
);

CREATE TABLE ayah (
  surah  INTEGER NOT NULL REFERENCES surah(number),
  ayah   INTEGER NOT NULL,
  arabic TEXT NOT NULL,                -- Tanzil Uthmani, unchanged
  PRIMARY KEY (surah, ayah)
) WITHOUT ROWID;

CREATE TABLE translation_source (
  key         TEXT PRIMARY KEY,        -- QuranEnc key
  language    TEXT NOT NULL,
  title       TEXT NOT NULL,
  version     TEXT NOT NULL,
  last_update TEXT
);

CREATE TABLE translation (
  source    TEXT NOT NULL REFERENCES translation_source(key),
  surah     INTEGER NOT NULL,
  ayah      INTEGER NOT NULL,
  text      TEXT NOT NULL,
  footnotes TEXT,
  PRIMARY KEY (source, surah, ayah)
) WITHOUT ROWID;

CREATE TABLE ayah_set (
  id                   TEXT PRIMARY KEY,
  surah                INTEGER NOT NULL,
  ayah                 INTEGER NOT NULL,
  is_sample            INTEGER NOT NULL DEFAULT 0,
  has_story            INTEGER NOT NULL DEFAULT 0,
  story_one_line       TEXT,
  story_one_line_lang  TEXT,
  has_when             INTEGER NOT NULL DEFAULT 0,
  when_place           TEXT,
  when_order           INTEGER,
  when_period_text     TEXT,
  when_age_min         INTEGER,
  when_age_max         INTEGER,
  when_approx          INTEGER NOT NULL DEFAULT 1,
  when_scholars_differ INTEGER NOT NULL DEFAULT 0
);

-- position = the curated order of sets inside one topic
CREATE TABLE ayah_set_topic (
  set_id   TEXT NOT NULL REFERENCES ayah_set(id),
  topic    TEXT NOT NULL,
  position INTEGER NOT NULL,
  PRIMARY KEY (topic, position)
);
CREATE INDEX ayah_set_topic_set ON ayah_set_topic(set_id);

CREATE TABLE ayah_set_context (
  set_id   TEXT NOT NULL REFERENCES ayah_set(id),
  role     TEXT NOT NULL CHECK (role IN ('before', 'after')),
  position INTEGER NOT NULL,
  surah    INTEGER NOT NULL,
  ayah     INTEGER NOT NULL,
  PRIMARY KEY (set_id, role, position)
);

CREATE TABLE story_step (
  set_id   TEXT NOT NULL REFERENCES ayah_set(id),
  position INTEGER NOT NULL,
  lang     TEXT NOT NULL,
  text     TEXT NOT NULL,
  PRIMARY KEY (set_id, position)
);

CREATE TABLE source_ref (
  set_id    TEXT NOT NULL REFERENCES ayah_set(id),
  block     TEXT NOT NULL CHECK (block IN ('story', 'when', 'tafsir')),
  position  INTEGER NOT NULL,
  book      TEXT NOT NULL,
  number    TEXT,
  numbering TEXT,
  grade     TEXT,
  location  TEXT,
  ayah      TEXT,
  edition   TEXT,
  page      TEXT,
  PRIMARY KEY (set_id, block, position)
);

-- Al-Mukhtasar comes whole from QuranEnc; Ibn Kathir and as-Sa'di are curated excerpts.
CREATE TABLE tafsir (
  book     TEXT NOT NULL,
  lang     TEXT NOT NULL,
  surah    INTEGER NOT NULL,
  ayah     INTEGER NOT NULL,
  text     TEXT NOT NULL,
  location TEXT,
  PRIMARY KEY (book, lang, surah, ayah)
) WITHOUT ROWID;
