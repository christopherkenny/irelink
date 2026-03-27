# Changelog

## irelink 0.0.0.9000

- Initial development version translating splink to R.
- Core pipeline:
  [`il_spec()`](http://christophertkenny.com/irelink/reference/il_spec.md),
  [`il_model()`](http://christophertkenny.com/irelink/reference/il_model.md),
  [`predict()`](https://rdrr.io/r/stats/predict.html),
  [`il_cluster()`](http://christophertkenny.com/irelink/reference/il_cluster.md).
- Comparison levels: exact, fuzzy string, numeric, date, and geographic.
- EM-based parameter estimation and deterministic linkage.
- SQL backends via DBI (RSQLite, DuckDB, PostgreSQL).
