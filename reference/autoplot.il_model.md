# Quick Match-Weights Plot for a Model

Produces a ready-made match-weights chart from a trained model. This is
a convenience wrapper; for full control, extract data with
[`il_weights()`](http://christophertkenny.com/irelink/reference/il_weights.md)
and build a custom
[`ggplot2::ggplot()`](https://ggplot2.tidyverse.org/reference/ggplot.html).

## Usage

``` r
# S3 method for class 'il_model'
autoplot(object, ...)
```

## Arguments

- object:

  A trained `il_model` object.

- ...:

  Additional arguments (currently unused).

## Value

A `ggplot` object.
