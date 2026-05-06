# Term Frequency Adjustment Chart

Visualizes the distribution of term frequencies for a column in the
model. Shows how individual values shift the match weight via the TF
adjustment (rare values boost the weight; common values penalize it).

## Usage

``` r
il_tf_chart(model, col, n_most_freq = 10L, n_least_freq = 5L)
```

## Arguments

- model:

  A trained `il_model` object with `term_frequency = TRUE` enabled for
  at least one comparison column.

- col:

  A character string naming the column to plot.

- n_most_freq:

  Number of most-frequent values to label. Default 10.

- n_least_freq:

  Number of least-frequent values to label. Default 5.

## Value

A `ggplot` object.

## Examples

``` r
if (FALSE) { # \dontrun{
model <- il_model(fake_1000, spec = spec, con = con)
il_tf_chart(model, 'first_name')
} # }
```
