# Term Frequency Adjustment Chart

Visualizes the distribution of term frequencies for a column in the
model. Shows how individual values shift the match weight via the TF
adjustment. Rare values boost the weight, while common values penalize
it.

## Usage

``` r
il_tf_chart(model, col, n_most_freq = 10L, n_least_freq = 5L)
```

## Arguments

- model:

  An `il_model` object with `term_frequency = TRUE` enabled for at least
  one comparison column.

- col:

  A character string naming the column to plot.

- n_most_freq:

  Number of most-frequent values to label. Default 10.

- n_least_freq:

  Number of least-frequent values to label. Default 5.

## Value

A
[`ggplot2::ggplot()`](https://ggplot2.tidyverse.org/reference/ggplot.html)
object.

## Examples

``` r
con <- DBI::dbConnect(duckdb::duckdb())
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmpye6umx/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
spec <- il_spec() |>
  il_compare(first_name, cl_exact(term_frequency = TRUE))
model <- il_model(fake_20, spec = spec, con = con)
il_tf_chart(model, 'first_name')

il_cleanup(model)
DBI::dbDisconnect(con, shutdown = TRUE)
```
