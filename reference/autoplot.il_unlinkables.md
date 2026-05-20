# Plot Unlinkables Curve

Draws the proportion of records that cannot be linked at each
match-probability threshold, from data produced by
[`il_unlinkables()`](http://christophertkenny.com/irelink/reference/il_unlinkables.md).

## Usage

``` r
# S3 method for class 'il_unlinkables'
autoplot(object, ...)
```

## Arguments

- object:

  An `il_unlinkables` tibble.

- ...:

  Additional arguments (currently unused).

## Value

A
[`ggplot2::ggplot()`](https://ggplot2.tidyverse.org/reference/ggplot.html)
object.
