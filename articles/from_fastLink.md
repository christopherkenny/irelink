# Translating from fastLink

`irelink` implements the same Fellegi-Sunter probabilistic record
linkage framework as [fastLink](https://github.com/kosukeimai/fastLink),
but with a different API design and a SQL backend. This vignette maps
fastLink’s API to `irelink` so that users familiar with fastLink can get
started quickly.

## Design differences

fastLink bundles data preparation, EM estimation, and matching into a
single `fastLink()` call. `irelink` separates these into a pipeline of
composable functions: define a spec, build a model, estimate parameters,
then predict.

fastLink’s Jaro-Winkler comparisons produce three agreement levels
(agree / partially agree / disagree) controlled by `cut.a` and `cut.p`
thresholds. `irelink` uses `cl_jaro_winkler(high, low)` to express the
same two thresholds, giving the same three-level structure.

fastLink’s `getMatches()` assigns a `dedupe.ids` column to flag
duplicates. `irelink` uses
[`il_cluster()`](http://christophertkenny.com/irelink/reference/il_cluster.md)
instead, which assigns a `cluster_id` to each record.

## Core workflow

[TABLE]

## Comparison functions

fastLink compares string fields using Jaro-Winkler (default),
Levenshtein, or Jaro, producing up to three agreement levels. Each maps
to a `cl_*()` function in `irelink`.

| fastLink | irelink |
|----|----|
| JW (default), `cut.a`, `cut.p` | `cl_jaro_winkler(high, low)` |
| `stringdist.method = "jaro"`, `cut.a`, `cut.p` | `cl_jaro(high, low)` |
| `stringdist.method = "lv"`, `cut.a`, `cut.p` | `cl_levenshtein(low, high)` |
| `numeric.match`, `cut.a.num` | `cl_numeric_diff(threshold)` |
| exact agreement on non-string fields | [`cl_exact()`](http://christophertkenny.com/irelink/reference/cl_exact.md) |

Note that Levenshtein thresholds in `irelink` are raw edit distances,
not renormalized similarity scores as in fastLink.
`cl_levenshtein(1, 2)` means “distance ≤ 1 is full agreement, distance ≤
2 is partial agreement.”

## Key parameters

| fastLink parameter | irelink equivalent |
|----|----|
| `cut.a` | first argument to [`cl_jaro_winkler()`](http://christophertkenny.com/irelink/reference/cl_jaro_winkler.md) |
| `cut.p` | second argument to [`cl_jaro_winkler()`](http://christophertkenny.com/irelink/reference/cl_jaro_winkler.md) |
| `cut.a.num` | argument to [`cl_numeric_diff()`](http://christophertkenny.com/irelink/reference/cl_numeric_diff.md) |
| `threshold.match` | `threshold` in [`predict()`](https://rdrr.io/r/stats/predict.html) |
| `dedupe = FALSE` | default; `irelink` never enforces 1-to-1 matching |
| `n.cores` | irelink uses DuckDB parallelism automatically |

## Example: side-by-side deduplication

**fastLink:**

``` r

library(fastLink)

out <- fastLink(
  dfA = records,
  dfB = records,
  varnames = c('first_name', 'surname', 'dob'),
  stringdist.match = c('first_name', 'surname'),
  partial.match = c('first_name', 'surname'),
  cut.a = 0.94,
  cut.p = 0.84,
  threshold.match = 0.90,
  dedupe = FALSE
)

recordsfL <- getMatches(dfA = records, dfB = records, fl.out = out)
length(unique(recordsfL$dedupe.ids))
```

**irelink:**

``` r

library(irelink)

con <- DBI::dbConnect(duckdb::duckdb())

spec <- il_spec() |>
  il_compare(first_name, cl_jaro_winkler(0.94, 0.84)) |>
  il_compare(surname, cl_jaro_winkler(0.94, 0.84)) |>
  il_compare(dob, cl_exact()) |>
  il_block_on(surname) |>
  il_block_on(first_name)

model <- il_model(fake_1000, spec = spec, con = con) |>
  il_estimate_u() |>
  il_estimate_em(block_on(surname)) |>
  il_estimate_em(block_on(first_name)) |>
  il_prior_prevalence(1e-3)

pairs <- predict(model, threshold = 0.90)
clusters <- il_cluster(pairs)
length(unique(clusters$cluster_id))

il_cleanup(model)
DBI::dbDisconnect(con, shutdown = TRUE)
```

The
[`il_prior_prevalence()`](http://christophertkenny.com/irelink/reference/il_prior_prevalence.md)
call replaces the training-driven prior with a population-level
baseline, in the same way as resetting the prior after EM in fastLink
workflows that use a heavily blocked training sample. If your training
data is large and representative, this step is unnecessary.

## Blocking

fastLink’s `blockData()` partitions records into groups and requires
running `fastLink()` separately within each block, then reassembling the
results. In `irelink`, blocking is declared in the spec with
[`il_block_on()`](http://christophertkenny.com/irelink/reference/il_block_on.md)
and applied automatically — no manual loop is needed.

**fastLink:**

``` r

blocks <- blockData(records, records, varnames = 'surname')

results <- list()
for (j in seq_along(blocks)) {
  sub <- records[blocks[[j]]$dfA.inds, ]
  out_b <- fastLink(dfA = sub, dfB = sub, ...)
  sub <- getMatches(dfA = sub, dfB = sub, fl.out = out_b)
  sub$dedupe.ids <- paste0('B', j, '_', sub$dedupe.ids)
  results[[j]] <- sub
}
combined <- do.call('rbind', results)
```

**irelink:**

``` r

spec <- il_spec() |>
  il_compare(first_name, cl_jaro_winkler(0.94, 0.84)) |>
  il_compare(surname, cl_jaro_winkler(0.94, 0.84)) |>
  il_compare(dob, cl_exact()) |>
  il_block_on(surname)
```

fastLink also offers k-means blocking via
`blockData(..., kmeans.block = ..., nclusters = ...)`. `irelink` does
not have a built-in k-means blocking step because data lives in a SQL
backend. For numeric fields,
[`il_block_on()`](http://christophertkenny.com/irelink/reference/il_block_on.md)
with pre-bucketed values is the nearest equivalent.

## Model inspection

fastLink exposes learned parameters through `out$EM$patterns.w` — a
table of agreement patterns and Fellegi-Sunter weights. `irelink`
provides the same information visually.

``` r

autoplot(model)
autoplot(model, type = 'parameters')
```

## Evaluation

fastLink requires constructing a confusion table by hand from
`dedupe.ids` and a ground-truth column. `irelink` provides
[`il_cluster_confusion_matrix()`](http://christophertkenny.com/irelink/reference/il_cluster_confusion_matrix.md)
which does this directly from the model.

**fastLink:**

``` r

recordsfL$dupTrue <- ifelse(duplicated(recordsfL$cluster), 'Duplicated', 'Not duplicated')
recordsfL$dupfL <- ifelse(duplicated(recordsfL$dedupe.ids), 'Duplicated', 'Not duplicated')
confusion <- table('fastLink' = recordsfL$dupfL, 'True' = recordsfL$dupTrue)
```

**irelink:**

``` r

acc <- il_cluster_confusion_matrix(model, labels_col = 'cluster', threshold = 0.90)
```

For a full accuracy or precision-recall curve across all thresholds, use
[`il_accuracy()`](http://christophertkenny.com/irelink/reference/il_accuracy.md)
and
[`il_precision_recall()`](http://christophertkenny.com/irelink/reference/il_precision_recall.md).
