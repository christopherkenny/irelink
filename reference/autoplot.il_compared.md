# Quick Plot for Scored Pairs

Produces a match-weight histogram from scored pairs, or a waterfall
chart for a single pair when `which` is provided. This is a convenience
wrapper around
[`ggplot2::ggplot()`](https://ggplot2.tidyverse.org/reference/ggplot.html).
For full control, build a plot directly from the prediction result or
from
[`il_waterfall()`](http://christophertkenny.com/irelink/reference/il_waterfall.md).

## Usage

``` r
# S3 method for class 'il_compared'
autoplot(object, which = NULL, ...)
```

## Arguments

- object:

  An `il_compared` tibble from
  [`predict.il_model()`](http://christophertkenny.com/irelink/reference/predict.il_model.md).

- which:

  An optional integer index. If provided, produces a waterfall chart for
  that pair. If `NULL` (default), produces a histogram.

- ...:

  Additional arguments (currently unused).

## Value

A
[`ggplot2::ggplot()`](https://ggplot2.tidyverse.org/reference/ggplot.html)
object.
