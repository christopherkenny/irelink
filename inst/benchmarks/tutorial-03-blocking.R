# Tutorial 03 — Blocking
# Translation of splink docs/demos/tutorials/03_Blocking.ipynb
# Covers: blocking rule analysis, counting pairs, largest blocks,
#         cumulative comparison scoring

library(irelink)
library(duckdb)
library(DBI)

df <- fake_1000
con <- dbConnect(duckdb())

# Simple blocking: count pairs per rule (splink: count_comparisons_from_blocking_rule)
il_count_pairs(
  df,
  block_on(first_name),
  block_on(surname),
  block_on(city),
  con = con
)

# Fuzzy blocking with SQL conditions (splink: SQL string rules)
# NOTE: splink allows raw SQL like:
#   "l.first_name = r.first_name and levenshtein(l.surname, r.surname) < 2"
# irelink supports this via the .where argument on block_on():
il_count_pairs(
  df,
  block_on(first_name, .where = "levenshtein(l.surname, r.surname) < 2"),
  con = con
)

# Identify skewed blocking bins (splink: n_largest_blocks)
il_largest_blocks(df, block_on(city), n = 3, con = con)
il_largest_blocks(df, block_on(first_name), n = 5, con = con)

# Cumulative comparisons analysis (splink: cumulative_comparisons_...chart)
# irelink's il_count_pairs returns cumulative_pairs and pct_of_cartesian
il_count_pairs(
  df,
  block_on(first_name),
  block_on(surname),
  block_on(city),
  block_on(email),
  con = con
)

il_cleanup_all(con)
dbDisconnect(con, shutdown = TRUE)
