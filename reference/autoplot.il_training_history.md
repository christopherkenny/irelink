# Plot EM Training History

Draws parameter estimates across EM iterations, faceted by comparison,
from data produced by
[`il_training_history()`](http://christophertkenny.com/irelink/reference/il_training_history.md).

## Usage

``` r
# S3 method for class 'il_training_history'
autoplot(object, ...)
```

## Arguments

- object:

  An `il_training_history` tibble.

- ...:

  Additional arguments (currently unused).

## Value

A
[`ggplot2::ggplot()`](https://ggplot2.tidyverse.org/reference/ggplot.html)
object.
