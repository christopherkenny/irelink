# Comparator Score Bar Chart

Visualizes the output of
[`il_string_similarity()`](http://christophertkenny.com/irelink/reference/il_string_similarity.md)
as a horizontal bar chart, making it easy to compare multiple
string-distance metrics at a glance.

## Usage

``` r
# S3 method for class 'il_string_similarity'
autoplot(object, ...)
```

## Arguments

- object:

  An `il_string_similarity` tibble (the return value of
  [`il_string_similarity()`](http://christophertkenny.com/irelink/reference/il_string_similarity.md)).

- ...:

  Additional arguments (currently unused).

## Value

A
[`ggplot2::ggplot()`](https://ggplot2.tidyverse.org/reference/ggplot.html)
object.

## Examples

``` r
ggplot2::autoplot(il_string_similarity('John', 'Jon'))
```
