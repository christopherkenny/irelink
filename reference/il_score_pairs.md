# Score Record Pairs with a Trained Model

Scores every pair formed by one record from `records_l` and one record
from `records_r`, without blocking. This is useful for scoring a single
known pair, checking a handful of candidate matches, or clerical review.
For blocked scoring of new records against a model's data, use
[`il_find_matches()`](http://christophertkenny.com/irelink/reference/il_find_matches.md).

## Usage

``` r
il_score_pairs(model, records_l, records_r, con = NULL)
```

## Arguments

- model:

  A trained `il_model` object.

- records_l, records_r:

  Data frames of records to compare. Every record in `records_l` is
  compared with every record in `records_r`. A `unique_id` column is
  added when missing.

- con:

  A DBI connection object from
  [`DBI::dbConnect()`](https://dbi.r-dbi.org/reference/dbConnect.html).
  Defaults to the model's connection, or a temporary DuckDB connection
  when the model has none.

## Value

An `il_compared` tibble with one row per pair, containing `unique_id_l`
and `unique_id_r` (ids within `records_l` and `records_r`),
`match_weight`, `total_match_weight`, `match_probability`, the
comparison levels, and the compared fields.

## Details

Term-frequency adjustments use the model's own term-frequency tables,
which come from its full data, rather than frequencies within the few
records being scored. A model with term-frequency comparisons therefore
needs its data attached, via
[`il_model()`](http://christophertkenny.com/irelink/reference/il_model.md)
or
[`il_attach()`](http://christophertkenny.com/irelink/reference/il_attach.md),
or its tables registered with
[`il_register_tf()`](http://christophertkenny.com/irelink/reference/il_register_tf.md).

## Examples

``` r
con <- DBI::dbConnect(duckdb::duckdb())
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpCyxgpv/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
spec <- il_spec() |>
  il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(surname, cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(dob, cl_exact()) |>
  il_block_on(surname)
model <- il_model(fake_1000, spec = spec, con = con) |>
  il_estimate_u() |>
  il_estimate_em(block_on(dob))
#> EM trained: first_name and surname | skipped (blocked on): dob

il_score_pairs(
  model,
  data.frame(first_name = 'Jon', surname = 'Smith', dob = '1990-01-15'),
  data.frame(
    first_name = c('John', 'Jane'),
    surname = c('Smith', 'Smyth'),
    dob = c('1990-01-15', '1985-06-02')
  )
)
#> # A tibble: 2 × 14
#>   unique_id_l unique_id_r gamma_first_name gamma_surname gamma_dob match_weight
#> *       <int>       <int>            <int>         <int>     <int>        <dbl>
#> 1           1           1                2             2         1        20.8 
#> 2           1           2                1             1         0         3.13
#> # ℹ 8 more variables: total_match_weight <dbl>, match_probability <dbl>,
#> #   first_name_l <chr>, surname_l <chr>, dob_l <chr>, first_name_r <chr>,
#> #   surname_r <chr>, dob_r <chr>
DBI::dbDisconnect(con, shutdown = TRUE)
```
