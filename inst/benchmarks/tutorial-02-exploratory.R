# Tutorial 02 — Exploratory Analysis
# Translation of splink docs/demos/tutorials/02_Exploratory_analysis.ipynb
# -----------------------------------------------------------------------
# Covers: data loading, completeness profiling, column value distributions

library(irelink)
library(duckdb)
library(DBI)

# Load sample data -------------------------------------------------------
df <- il_demo("fake_1000")
head(df)

con <- dbConnect(duckdb())

# Completeness chart (splink: completeness_chart) -------------------------
# irelink returns a tibble; visualise with ggplot2 if desired
completeness <- il_completeness(df, con = con)
print(completeness)

# Profile columns (splink: profile_columns) -------------------------------
# Top 10 most frequent values per column
profile <- il_profile(df, first_name, surname, city, con = con, top_n = 10)
print(profile)

# Bottom 5 least frequent values (useful for spotting typos)
rare <- il_profile(df, first_name, surname, con = con, bottom_n = 5)
print(rare)

# Combined top + bottom view
combined <- il_profile(df, city, con = con, top_n = 10, bottom_n = 5)
print(combined)

dbDisconnect(con, shutdown = TRUE)
