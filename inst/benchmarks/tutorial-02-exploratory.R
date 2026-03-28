# Tutorial 02 — Exploratory Analysis
# Translation of splink docs/demos/tutorials/02_Exploratory_analysis.ipynb
# Covers: data loading, completeness profiling, column value distributions

library(irelink)
library(duckdb)
library(DBI)

# Load sample data
df <- fake_1000
head(df)

con <- dbConnect(duckdb())

# Completeness chart (splink: completeness_chart)
il_completeness(df, con = con)

# Profile columns (splink: profile_columns)
# Top 10 most frequent values per column
il_profile(df, first_name, surname, city, con = con, top_n = 10)

# Bottom 5 least frequent values (useful for spotting typos)
il_profile(df, first_name, surname, con = con, bottom_n = 5)

# Combined top + bottom view
il_profile(df, city, con = con, top_n = 10, bottom_n = 5)

dbDisconnect(con, shutdown = TRUE)
