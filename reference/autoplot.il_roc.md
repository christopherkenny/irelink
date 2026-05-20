# Plot ROC Curve

Draws a receiver operating characteristic curve from the data produced
by
[`il_roc()`](http://christophertkenny.com/irelink/reference/il_roc.md).

## Usage

``` r
# S3 method for class 'il_roc'
autoplot(object, ...)
```

## Arguments

- object:

  An `il_roc` tibble.

- ...:

  Additional arguments (currently unused).

## Value

A
[`ggplot2::ggplot()`](https://ggplot2.tidyverse.org/reference/ggplot.html)
object.
