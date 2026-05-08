# Quick Match-Weights Plot for a Model

Produces a ready-made chart from a trained model. By default draws the
match-weights bar chart. Set `type = "parameters"` for an m / u
probability comparison. For full control, extract data with
[`il_weights()`](http://christophertkenny.com/irelink/reference/il_weights.md)
or
[`il_parameters()`](http://christophertkenny.com/irelink/reference/il_parameters.md)
and build a custom
[`ggplot2::ggplot()`](https://ggplot2.tidyverse.org/reference/ggplot.html).

## Usage

``` r
# S3 method for class 'il_model'
autoplot(object, type = c("weights", "parameters"), ...)
```

## Arguments

- object:

  A trained `il_model` object.

- type:

  One of `"weights"` (default) or `"parameters"`. `"weights"` shows
  log-2 Bayes factors per comparison level. `"parameters"` shows m and u
  probabilities side by side.

- ...:

  Additional arguments (currently unused).

## Value

A `ggplot` object.
