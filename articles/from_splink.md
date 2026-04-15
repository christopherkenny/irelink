# Translating from Splink

`irelink` is a translation of the Python
[splink](https://github.com/moj-analytical-services/splink) library into
idiomatic R. This vignette maps splink’s API to `irelink` so that users
familiar with splink can get started quickly.

## Design differences

Splink uses an object-oriented design centred on a `Linker` class.
`irelink` instead uses a functional pipeline style that is natural in R.
The `Linker` object’s namespaced methods (`linker.training.*`,
`linker.inference.*`, etc.) become standalone functions that accept and
return an `il_model` object.

Splink bundles comparison levels into high-level “Comparison” classes
(e.g., `JaroWinklerAtThresholds`). In `irelink`, the `cl_*()` functions
serve the same role and can be passed directly to
[`il_compare()`](http://christophertkenny.com/irelink/reference/il_compare.md).

## Core workflow

[TABLE]

## Comparison levels

Comparison levels are the building blocks for scoring how similar two
records are on a given field. Each `cl_*()` function corresponds to a
splink comparison level class.

| splink (Python)                      | irelink (R)                                                                                            |
|--------------------------------------|--------------------------------------------------------------------------------------------------------|
| `ExactMatchLevel`                    | [`cl_exact()`](http://christophertkenny.com/irelink/reference/cl_exact.md)                             |
| `LevenshteinLevel`                   | [`cl_levenshtein()`](http://christophertkenny.com/irelink/reference/cl_levenshtein.md)                 |
| `DamerauLevenshteinLevel`            | [`cl_damerau_levenshtein()`](http://christophertkenny.com/irelink/reference/cl_damerau_levenshtein.md) |
| `JaroLevel`                          | [`cl_jaro()`](http://christophertkenny.com/irelink/reference/cl_jaro.md)                               |
| `JaroWinklerLevel`                   | [`cl_jaro_winkler()`](http://christophertkenny.com/irelink/reference/cl_jaro_winkler.md)               |
| `JaccardLevel`                       | [`cl_jaccard()`](http://christophertkenny.com/irelink/reference/cl_jaccard.md)                         |
| `CosineSimilarityLevel`              | [`cl_cosine()`](http://christophertkenny.com/irelink/reference/cl_cosine.md)                           |
| `AbsoluteDifferenceLevel`            | [`cl_numeric_diff()`](http://christophertkenny.com/irelink/reference/cl_numeric_diff.md)               |
| `PercentageDifferenceLevel`          | [`cl_pct_diff()`](http://christophertkenny.com/irelink/reference/cl_pct_diff.md)                       |
| `AbsoluteTimeDifferenceAtThresholds` | [`cl_date_diff()`](http://christophertkenny.com/irelink/reference/cl_date_diff.md)                     |
| `DistanceInKMLevel`                  | [`cl_distance_km()`](http://christophertkenny.com/irelink/reference/cl_distance_km.md)                 |
| `ArrayIntersectLevel`                | [`cl_array_intersect()`](http://christophertkenny.com/irelink/reference/cl_array_intersect.md)         |
| `CustomLevel`                        | [`cl_custom()`](http://christophertkenny.com/irelink/reference/cl_custom.md)                           |
| `NullLevel`                          | [`cl_null()`](http://christophertkenny.com/irelink/reference/cl_null.md)                               |
| `ElseLevel`                          | [`cl_else()`](http://christophertkenny.com/irelink/reference/cl_else.md)                               |
| `And`                                | [`cl_and()`](http://christophertkenny.com/irelink/reference/cl_and.md)                                 |
| `Or`                                 | [`cl_or()`](http://christophertkenny.com/irelink/reference/cl_or.md)                                   |
| `Not`                                | [`cl_not()`](http://christophertkenny.com/irelink/reference/cl_not.md)                                 |

## Domain-specific comparisons

Splink provides high-level comparison classes that compose multiple
levels for common field types. In `irelink`, these are helper functions
that return a pre-configured set of levels.

| splink (Python)             | irelink (R)                                                                                      |
|-----------------------------|--------------------------------------------------------------------------------------------------|
| `NameComparison`            | [`cl_name()`](http://christophertkenny.com/irelink/reference/cl_name.md)                         |
| `ForenameSurnameComparison` | [`cl_forename_surname()`](http://christophertkenny.com/irelink/reference/cl_forename_surname.md) |
| `DateOfBirthComparison`     | [`cl_dob()`](http://christophertkenny.com/irelink/reference/cl_dob.md)                           |
| `EmailComparison`           | [`cl_email()`](http://christophertkenny.com/irelink/reference/cl_email.md)                       |
| `PostcodeComparison`        | [`cl_postcode()`](http://christophertkenny.com/irelink/reference/cl_postcode.md)                 |

## Model inspection

[TABLE]

## Evaluation

[TABLE]

## Data profiling

| splink (Python)                                        | irelink (R)                |
|--------------------------------------------------------|----------------------------|
| `linker.profile_columns(...)`                          | `il_profile(df, ...)`      |
| `linker.count_num_comparisons_from_blocking_rule(...)` | `il_count_pairs(df, ...)`  |
| *completeness profiling*                               | `il_completeness(df, ...)` |

## Persistence

| splink (Python)                       | irelink (R)            |
|---------------------------------------|------------------------|
| `linker.misc.save_model_to_json(...)` | `il_save(model, path)` |
| `load_model_from_json(...)`           | `il_load(path)`        |
| *no direct equivalent*                | `il_cleanup(model)`    |

## Blocking rules

In splink, blocking rules are created with
[`block_on()`](http://christophertkenny.com/irelink/reference/block_on.md).
`irelink` uses the same function name. The difference is where they
appear: splink passes them into `SettingsCreator`, while `irelink` adds
them to a spec with
[`il_block_on()`](http://christophertkenny.com/irelink/reference/il_block_on.md)
or passes them directly to training functions.

``` r
# irelink — blocking in the spec
spec <- il_spec() |>
  il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
  il_block_on(surname)

# irelink — blocking in EM training
model <- il_estimate_em(model, block_on(surname))
```

## Example: side-by-side deduplication

Below is a minimal deduplication in both splink and `irelink`.

**splink (Python):**

``` python
from splink import Linker, SettingsCreator, DuckDBAPI, block_on, splink_datasets
import splink.comparison_library as cl

df = splink_datasets.fake_1000
db_api = DuckDBAPI()

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

linker = Linker(df, settings, db_api)
linker.training.estimate_u_using_random_sampling(max_pairs=1e6)
linker.training.estimate_parameters_using_expectation_maximisation(
    block_on("surname")
)

pairwise = linker.inference.predict(threshold_match_weight=0.5)
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

## Example: finding matches against new records

**splink (Python):**

``` python
new_records = pd.DataFrame([{
    "first_name": "Jhon", "surname": "Smith", "dob": "1990-01-15"
}])
results = linker.inference.find_matches_to_new_records(
    new_records, blocking_rules=[], match_weight_threshold=-10
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
