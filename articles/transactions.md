# Linking Banking Transactions

This vignette reproduces the [Splink “Linking banking transactions”
demo](https://moj-analytical-services.github.io/splink/demos/examples/duckdb/transactions.html)
in `irelink`. It demonstrates two-table linkage with
`link_type = "link"` by matching each outgoing payment in the origin
table to the corresponding incoming payment in the destination table.

The data is synthetic and intentionally challenging. Amounts differ
because of fees and exchange-rate effects, dates can shift by a few
days, and memos are sometimes truncated. Because each origin payment has
exactly one destination counterpart, the prior match probability is
`1 / n_origin`.

This vignette requires
[nanoparquet](https://cran.r-project.org/package=nanoparquet) to read
the remote Parquet files, and it only compiles when the package and both
data URLs are available. It also assumes DuckDB because the blocking
rules below use raw `.where` SQL with DuckDB date helpers such as
[`strftime()`](https://rdrr.io/r/base/strptime.html) and `yearweek()`.

## Load the data

``` r

library(irelink)
library(ggplot2)

df_origin
df_destination
```

## Profile the data

``` r

con <- DBI::dbConnect(duckdb::duckdb())
```

``` r

il_profile(df_origin, memo, transaction_date, amount, con = con, top_n = 8)
```

## Choose blocking rules

Because corresponding records differ in predictable ways, the blocking
rules need to be broad enough to retain true matches while still
shrinking the search space. Fees change amounts, dates shift, and memos
are truncated, so the rules below use SQL expressions in `.where` rather
than relying on exact agreement alone:

``` r

counts <- il_count_pairs(
  df_origin,
  df_destination,
  # Same year-month, similar memo prefix, amount ratio within 30%
  block_on(
    .where = paste(
      "strftime(l.transaction_date, '%Y%m') = strftime(r.transaction_date, '%Y%m')",
      'AND substr(l.memo, 1, 3) = substr(r.memo, 1, 3)',
      'AND l.amount / r.amount > 0.7 AND l.amount / r.amount < 1.3'
    )
  ),
  # Same but offset by 15 days to catch month boundaries
  block_on(
    .where = paste(
      "strftime(l.transaction_date + 15, '%Y%m') = strftime(r.transaction_date, '%Y%m')",
      'AND substr(l.memo, 1, 3) = substr(r.memo, 1, 3)',
      'AND l.amount / r.amount > 0.7 AND l.amount / r.amount < 1.3'
    )
  ),
  # Memo prefix (first 9 characters)
  block_on(.where = 'substr(l.memo, 1, 9) = substr(r.memo, 1, 9)'),
  # Rounded amount + same week
  block_on(
    .where = paste(
      'round(l.amount / 2, 0) * 2 = round(r.amount / 2, 0) * 2',
      'AND yearweek(r.transaction_date) = yearweek(l.transaction_date)'
    )
  ),
  # Amount offset + week offset
  block_on(
    .where = paste(
      'round(l.amount / 2, 0) * 2 = round((r.amount + 1) / 2, 0) * 2',
      'AND yearweek(r.transaction_date) = yearweek(l.transaction_date + 4)'
    )
  ),
  # Ground-truth "cheat" rule for completeness
  block_on(unique_id),
  con = con,
  link_type = 'link'
)
counts
```

``` r

autoplot(counts)
```

## Define the specification

The `transaction_date` comparison is one-sided because a payment can
only arrive after it is sent. The comparison therefore checks whether
`destination_date - origin_date` is between 0 and `N` days:

``` r

spec <- il_spec() |>
  il_compare(amount, cl_pct_diff(0.01, 0.03, 0.10, 0.30)) |>
  il_compare(memo, cl_levenshtein(2, 6, 10)) |>
  il_compare(
    transaction_date,
    cl_levels(
      cl_null(),
      cl_custom('(r.{col} - l.{col}) BETWEEN 0 AND 1'),
      cl_custom('(r.{col} - l.{col}) BETWEEN 0 AND 4'),
      cl_custom('(r.{col} - l.{col}) BETWEEN 0 AND 10'),
      cl_custom('(r.{col} - l.{col}) BETWEEN 0 AND 30'),
      cl_else()
    )
  ) |>
  il_block_on(
    .where = paste(
      "strftime(l.transaction_date, '%Y%m') = strftime(r.transaction_date, '%Y%m')",
      'AND substr(l.memo, 1, 3) = substr(r.memo, 1, 3)',
      'AND l.amount / r.amount > 0.7 AND l.amount / r.amount < 1.3'
    )
  ) |>
  il_block_on(
    .where = paste(
      "strftime(l.transaction_date + 15, '%Y%m') = strftime(r.transaction_date, '%Y%m')",
      'AND substr(l.memo, 1, 3) = substr(r.memo, 1, 3)',
      'AND l.amount / r.amount > 0.7 AND l.amount / r.amount < 1.3'
    )
  ) |>
  il_block_on(.where = 'substr(l.memo, 1, 9) = substr(r.memo, 1, 9)') |>
  il_block_on(
    .where = paste(
      'round(l.amount / 2, 0) * 2 = round(r.amount / 2, 0) * 2',
      'AND yearweek(r.transaction_date) = yearweek(l.transaction_date)'
    )
  ) |>
  il_block_on(
    .where = paste(
      'round(l.amount / 2, 0) * 2 = round((r.amount + 1) / 2, 0) * 2',
      'AND yearweek(r.transaction_date) = yearweek(l.transaction_date + 4)'
    )
  ) |>
  il_block_on(unique_id)

spec
```

## Train the model

Because this benchmark is one-to-one, set the prevalence prior directly
with
[`il_prior_prevalence()`](http://christophertkenny.com/irelink/reference/il_prior_prevalence.md)
instead of changing `model$params` by hand:

``` r

model <- il_model(
  df_origin,
  df_destination,
  spec = spec,
  con = con,
  link_type = 'link'
)
model <- il_prior_prevalence(model, 1 / nrow(df_origin))
model <- il_estimate_u(model, max_pairs = 1e6) |>
  il_estimate_em(block_on(memo)) |>
  il_estimate_em(block_on(amount))
```

## Inspect the trained model

``` r

summary(model)
```

``` r

autoplot(model)
```

``` r

autoplot(model, type = 'parameters')
```

## Predict

``` r

predictions <- predict(model, threshold = 0.001)
predictions
```

``` r

autoplot(predictions)
```

``` r

autoplot(predictions, which = 1)
```

## Evaluate against ground truth

``` r

acc <- il_accuracy(model, labels_col = 'ground_truth')
acc
```

``` r

autoplot(acc)
```

### Error inspection

``` r

errors <- il_errors(model, labels_col = 'ground_truth', threshold = 0.5)
errors[errors$error_type == 'false_positive', ]
```

``` r

errors[errors$error_type == 'false_negative', ]
```

## Cleanup

``` r

il_cleanup(model)
DBI::dbDisconnect(con, shutdown = TRUE)
```

`il_cleanup(model)` only removes tables owned by that model. If an
interactive run fails before you keep the model object, call
`il_cleanup_all(con)` to remove all `irelink` tables from the connection
before disconnecting.
