# Build the synthetic Taguette-shaped SQLite fixture shipped under
# inst/extdata/example_project.sqlite3.
#
# The fixture is a fully fabricated dataset — a small "book club discussion"
# corpus with two documents, seven tags, and a mix of ASCII and Japanese tag
# paths so downstream normalisation and split code paths get exercised.
#
# Regenerate via:
#   Rscript data-raw/build_example_sqlite.R

library(DBI)
library(RSQLite)

out_path <- "inst/extdata/example_project.sqlite3"
if (file.exists(out_path)) file.remove(out_path)
dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
con <- dbConnect(SQLite(), dbname = out_path)
on.exit(dbDisconnect(con), add = TRUE)

# ---- Schema (subset of the Taguette schema used by the pipeline) ----
dbExecute(con, "CREATE TABLE users (
  login TEXT PRIMARY KEY,
  created TEXT NOT NULL,
  hashed_password TEXT,
  disabled INTEGER NOT NULL,
  password_set_date TEXT,
  language TEXT,
  email TEXT,
  email_sent TEXT
)")
dbExecute(con, "CREATE TABLE projects (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  description TEXT NOT NULL,
  created TEXT NOT NULL
)")
dbExecute(con, "CREATE TABLE project_members (
  project_id INTEGER NOT NULL,
  user_login TEXT NOT NULL,
  privileges TEXT NOT NULL,
  PRIMARY KEY (project_id, user_login)
)")
dbExecute(con, "CREATE TABLE documents (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  description TEXT NOT NULL,
  filename TEXT NOT NULL,
  created TEXT NOT NULL,
  project_id INTEGER NOT NULL,
  text_direction TEXT NOT NULL,
  contents TEXT NOT NULL
)")
dbExecute(con, "CREATE TABLE tags (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  project_id INTEGER NOT NULL,
  path TEXT NOT NULL,
  description TEXT NOT NULL
)")
dbExecute(con, "CREATE TABLE highlights (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  document_id INTEGER NOT NULL,
  start_offset INTEGER NOT NULL,
  end_offset INTEGER NOT NULL,
  snippet TEXT NOT NULL
)")
dbExecute(con, "CREATE TABLE highlight_tags (
  highlight_id INTEGER NOT NULL,
  tag_id INTEGER NOT NULL,
  PRIMARY KEY (highlight_id, tag_id)
)")

# ---- Fabricated content: a "book club discussion" corpus ----
now <- "2026-01-01 00:00:00"

dbWriteTable(con, "users", data.frame(
  login = "demo",
  created = now, hashed_password = NA_character_,
  disabled = 0L, password_set_date = NA_character_,
  language = "en", email = "demo@example.invalid",
  email_sent = NA_character_,
  stringsAsFactors = FALSE
), append = TRUE)

dbWriteTable(con, "projects", data.frame(
  id = 1L, name = "Book Club Discussion (Example)",
  description = "Synthetic fixture for tagmodr; not derived from any real project.",
  created = now, stringsAsFactors = FALSE
), append = TRUE)

dbWriteTable(con, "project_members", data.frame(
  project_id = 1L, user_login = "demo", privileges = "ADMIN",
  stringsAsFactors = FALSE
), append = TRUE)

doc1 <- paste(
  "The narrator's grief was measured in small daily rituals.",
  "She kept the kitchen chair pushed in.",
  "Each morning she boiled water she did not drink.",
  sep = " "
)
doc2 <- paste(
  "彼は静かな部屋で本を閉じた。",
  "夕方の光が窓辺に落ちた。",
  "The final chapter left the ending open.",
  sep = " "
)
dbWriteTable(con, "documents", data.frame(
  id = 1:2,
  name = c("Chapter 1 excerpt", "Chapter 12 excerpt"),
  description = c("Opening chapter, first-person narration.",
                  "Closing chapter, mixed narration."),
  filename = c("ch01.txt", "ch12.txt"),
  created = now,
  project_id = 1L,
  text_direction = "LEFT_TO_RIGHT",
  contents = c(doc1, doc2),
  stringsAsFactors = FALSE
), append = TRUE)

# Seven tags — mix of ASCII and Japanese-segment paths (with the canonical
# "\\ " separator between segments) so normalise/split code paths are exercised.
tags <- data.frame(
  id = 1:7,
  project_id = 1L,
  # Taguette stores segment separator as two backslashes + space ("\\ ").
  # In R source below, four backslashes = the literal "\\" (two backslashes)
  # written to the SQLite. The Japanese pair is intentionally left WITHOUT
  # the trailing space so the B1 normaliser has something to correct in the
  # vignette.
  path = c(
    "Character\\\\ Grief",
    "Character\\\\ Grief\\\\ Rituals",
    "Setting\\\\ Domestic",
    "Style\\\\ Sentence Length",
    "Style\\\\ Voice",
    "登場人物\\\\内面",
    "場面\\\\夕景"
  ),
  description = "",
  stringsAsFactors = FALSE
)
dbWriteTable(con, "tags", tags, append = TRUE)

# Ten highlights across two documents.
hl <- data.frame(
  id = 1:10,
  document_id = c(1L, 1L, 1L, 1L, 1L, 2L, 2L, 2L, 2L, 2L),
  start_offset = c(0L, 55L, 92L, 130L, 92L, 0L, 22L, 40L, 22L, 40L),
  end_offset = c(50L, 90L, 128L, 160L, 128L, 20L, 38L, 90L, 38L, 90L),
  snippet = c(
    "The narrator's grief was measured in small daily",
    "She kept the kitchen chair pushed in",
    "Each morning she boiled water she did not drink",
    "boiled water she did not drink",
    "Each morning she boiled water",
    "彼は静かな部屋で本を閉じた",
    "夕方の光が窓辺に落ちた",
    "The final chapter left the ending open",
    "夕方の光が窓辺に落ちた",
    "The final chapter left the ending open"
  ),
  stringsAsFactors = FALSE
)
dbWriteTable(con, "highlights", hl, append = TRUE)

# highlight_tags — the join. Some highlights get multiple tags to exercise
# merge/unlink scenarios in the vignette.
ht <- data.frame(
  highlight_id = c(1L, 1L, 2L, 3L, 3L, 4L, 5L, 6L, 7L, 8L, 9L, 10L),
  tag_id       = c(1L, 5L, 2L, 2L, 3L, 4L, 3L, 6L, 7L, 5L, 7L, 5L),
  stringsAsFactors = FALSE
)
dbWriteTable(con, "highlight_tags", ht, append = TRUE)

message(sprintf(
  "Wrote %s (%d tags, %d highlights, %d highlight_tags rows).",
  out_path, nrow(tags), nrow(hl), nrow(ht)
))
