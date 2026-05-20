# Plot Accuracy Metrics Across Thresholds

Draws precision, recall, and F1 against the match-probability threshold.
The data is produced by
[`il_accuracy()`](http://christophertkenny.com/irelink/reference/il_accuracy.md).

## Usage

``` r
# S3 method for class 'il_accuracy'
autoplot(object, ...)
```

## Arguments

- object:

  An `il_accuracy` tibble.

- ...:

  Additional arguments (currently unused).

## Value

A
[`ggplot2::ggplot()`](https://ggplot2.tidyverse.org/reference/ggplot.html)
object.
