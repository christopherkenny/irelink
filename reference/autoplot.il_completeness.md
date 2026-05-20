# Plot Column Completeness

Draws a grouped bar chart of non-null percentages per column, from data
produced by
[`il_completeness()`](http://christophertkenny.com/irelink/reference/il_completeness.md).

## Usage

``` r
# S3 method for class 'il_completeness'
autoplot(object, ...)
```

## Arguments

- object:

  An `il_completeness` tibble.

- ...:

  Additional arguments (currently unused).

## Value

A
[`ggplot2::ggplot()`](https://ggplot2.tidyverse.org/reference/ggplot.html)
object.
