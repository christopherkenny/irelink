# Plot Column Value Profiles

Draws a faceted bar chart of value frequencies per column, from data
produced by
[`il_profile()`](http://christophertkenny.com/irelink/reference/il_profile.md).

## Usage

``` r
# S3 method for class 'il_profile'
autoplot(object, ...)
```

## Arguments

- object:

  An `il_profile` tibble.

- ...:

  Additional arguments (currently unused).

## Value

A
[`ggplot2::ggplot()`](https://ggplot2.tidyverse.org/reference/ggplot.html)
object.
