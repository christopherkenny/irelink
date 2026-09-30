# Translating from Splink

`irelink` translates the Python
[splink](https://github.com/moj-analytical-services/splink) library into
idiomatic R. This vignette maps common Splink 5 patterns to `irelink` so
you can get started quickly.

## Design differences

Splink uses an object-oriented design centered on a `Linker` class.
`irelink` uses a functional pipeline that fits naturally in R. The
`Linker` object’s namespaced methods such as `linker.training.*` and
`linker.inference.*` become standalone functions that accept and return
an `il_model` object.

Splink bundles comparison levels into high-level comparison classes such
as `JaroWinklerAtThresholds`. In `irelink`, the `cl_*()` functions fill
the same role and can be passed directly to
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md).

## Core workflow

[TABLE]

Splink 5 requires registering each input with `db_api.register()` before
building a `Linker`, and the `Linker` no longer takes `db_api`. In
`irelink`,
[`il_model()`](http://christophertkenny.com/irelink/reference/il_model.md)
registers data frames, lazy tables, or table names on the supplied
connection itself.

`irelink` also supports `link_type = "link_and_dedupe"` for two-table
jobs where duplicates may exist within each input table and across the
two tables.

`irelink` scores in-memory inputs and DBI-backed tables, including lazy
DuckDB results. Splink 5’s chunked prediction, DuckDB source pruning,
and Parquet-backed intermediate tables are not available, so very large
workflows should rely on explicit blocking and
`predict(collect = FALSE)`.

## Comparison levels

Comparison levels are the building blocks used to score how similar two
records are on a field. Each `cl_*()` function corresponds to a Splink
comparison level class.

| splink (Python) | irelink (R) |
|----|----|
| `ExactMatchLevel` | [`cl_exact()`](http://christophertkenny.com/irelink/reference/cl_exact.md) |
| `LevenshteinLevel` | [`cl_levenshtein()`](http://christophertkenny.com/irelink/reference/cl_levenshtein.md) |
| `DamerauLevenshteinLevel` | [`cl_damerau_levenshtein()`](http://christophertkenny.com/irelink/reference/cl_damerau_levenshtein.md) |
| `JaroLevel` | [`cl_jaro()`](http://christophertkenny.com/irelink/reference/cl_jaro.md) |
| `JaroWinklerLevel` | [`cl_jaro_winkler()`](http://christophertkenny.com/irelink/reference/cl_jaro_winkler.md) |
| `JaccardLevel` | [`cl_jaccard()`](http://christophertkenny.com/irelink/reference/cl_jaccard.md) |
| `CosineSimilarityLevel` | [`cl_cosine()`](http://christophertkenny.com/irelink/reference/cl_cosine.md) |
| `AbsoluteDifferenceLevel` | [`cl_numeric_diff()`](http://christophertkenny.com/irelink/reference/cl_numeric_diff.md) |
| `PercentageDifferenceLevel` | [`cl_pct_diff()`](http://christophertkenny.com/irelink/reference/cl_pct_diff.md) |
| `AbsoluteTimeDifferenceAtThresholds` | [`cl_date_diff()`](http://christophertkenny.com/irelink/reference/cl_date_diff.md) |
| `DistanceInKMLevel` | [`cl_geo_distance()`](http://christophertkenny.com/irelink/reference/cl_geo_distance.md) |
| `ArrayIntersectLevel` | [`cl_array_intersect()`](http://christophertkenny.com/irelink/reference/cl_array_intersect.md) |
| `CustomLevel` | [`cl_custom()`](http://christophertkenny.com/irelink/reference/cl_custom.md) |
| `NullLevel` | [`cl_null()`](http://christophertkenny.com/irelink/reference/cl_null.md) |
| `ElseLevel` | [`cl_else()`](http://christophertkenny.com/irelink/reference/cl_else.md) |
| `And` | [`cl_and()`](http://christophertkenny.com/irelink/reference/cl_and.md) |
| `Or` | [`cl_or()`](http://christophertkenny.com/irelink/reference/cl_or.md) |
| `Not` | [`cl_not()`](http://christophertkenny.com/irelink/reference/cl_not.md) |

## Domain-specific comparisons

Splink provides high-level comparison classes for common field types. In
`irelink`, these are helper functions that return preconfigured sets of
levels.

| splink (Python) | irelink (R) |
|----|----|
| `NameComparison` | [`cl_name()`](http://christophertkenny.com/irelink/reference/cl_name.md) |
| `ForenameSurnameComparison` | [`cl_forename_surname()`](http://christophertkenny.com/irelink/reference/cl_forename_surname.md) |
| `DateOfBirthComparison` | [`cl_dob()`](http://christophertkenny.com/irelink/reference/cl_dob.md) (Levenshtein for one-character typos) |
| `EmailComparison` | [`cl_email()`](http://christophertkenny.com/irelink/reference/cl_email.md) |
| `PostcodeComparison` | [`cl_postcode()`](http://christophertkenny.com/irelink/reference/cl_postcode.md) |

## Model inspection

[TABLE]

## Evaluation

Splink 5 combines these analyses in
`linker.evaluation.accuracy_analysis_from_labels_column()`, selected
with `output_type`.

[TABLE]

## Data profiling

[TABLE]

Splink 5 estimates blocking comparison counts from a 5% record sample by
default.
[`il_count_pairs()`](http://christophertkenny.com/irelink/reference/il_count_pairs.md)
computes exact counts unless you set `record_sample_proportion` below 1.

## Persistence

[TABLE]

## Blocking rules

In Splink, you create blocking rules with
[`block_on()`](http://christophertkenny.com/irelink/reference/block_on.md),
and `irelink` uses the same function name. The main difference is where
the rules are used: Splink passes them into `SettingsCreator`, while
`irelink` adds them to a spec with
[`il_block_on()`](http://christophertkenny.com/irelink/reference/il_block_on.md)
or passes them directly to training functions.

``` r

# blocking in the spec
spec <- il_spec() |>
  il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
  il_block_on(surname)

# blocking in EM training
model <- il_estimate_em(model, block_on(surname))
```

## Example: side-by-side deduplication

Below is a minimal deduplication example in both Splink and `irelink`.

**splink (Python):**

``` python
from splink import Linker, SettingsCreator, DuckDBAPI, block_on, splink_datasets
import splink.comparison_library as cl

db_api = DuckDBAPI()
df_sdf = db_api.register(splink_datasets.fake_1000, dataset_display_name="fake_1000")

settings = SettingsCreator(
    link_type="dedupe_only",
    comparisons=[
        cl.JaroWinklerAtThresholds("first_name", [0.9, 0.7]),
        cl.JaroWinklerAtThresholds("surname", [0.9, 0.7]),
        cl.ExactMatch("dob"),
    ],
    blocking_rules_to_generate_predictions=[
        block_on("first_name"),
        block_on("surname"),
    ],
)

linker = Linker(df_sdf, settings)
linker.training.estimate_u_using_random_sampling(max_pairs=1e6)
linker.training.estimate_parameters_using_expectation_maximisation(
    block_on("surname")
)

pairwise = linker.inference.predict(threshold_match_probability=0.5)
clusters = linker.clustering.cluster_pairwise_predictions_at_threshold(
    pairwise, 0.95
)
```

**irelink (R):**

``` r

library(irelink)

df <- fake_1000
con <- DBI::dbConnect(duckdb::duckdb())

spec <- il_spec() |>
  il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(surname, cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(dob, cl_exact()) |>
  il_block_on(first_name) |>
  il_block_on(surname)

model <- il_model(df, spec = spec, con = con)
model <- il_estimate_u(model)
model <- il_estimate_em(model, block_on(surname))

pairs <- predict(model, threshold = 0.5)
clusters <- il_cluster(pairs)

il_cleanup(model)
DBI::dbDisconnect(con, shutdown = TRUE)
```

The examples above use probability thresholds because those transfer
cleanly between Splink and `irelink`. In Splink, prediction
`match_weight` includes the prior odds. In `irelink`, `match_weight` is
evidence only, and `total_match_weight` is the prior-inclusive log2
odds. Keep that difference in mind if you translate match-weight
thresholds between the two packages.

## Example: finding matches against new records

**splink (Python):**

``` python
new_sdf = db_api.register(
    [{"unique_id": 1001, "first_name": "Jhon", "surname": "Smith", "dob": "1990-01-15"}],
    dataset_display_name="new_records",
)
results = linker.inference.predict_between(
    df_sdf, new_sdf, threshold_match_probability=0.5
)
```

**irelink (R):**

``` r

new_df <- data.frame(
  first_name = "Jhon",
  surname = "Smith",
  dob = "1990-01-15"
)
results <- il_find_matches(model, new_df, threshold = 0.5)
```

[`il_find_matches()`](http://christophertkenny.com/irelink/reference/il_find_matches.md)
corresponds to `predict_between()`: it scores new records against the
model’s existing data, but not new records against each other. Splink
5’s `predict_within()`, which scores pairs within the new records, has
no `irelink` equivalent yet.
