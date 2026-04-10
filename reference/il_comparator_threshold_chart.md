# Comparator Score Threshold Chart

Shows the distribution of pairwise similarity scores and highlights
which pairs exceed a given threshold.

## Usage

``` r
il_comparator_threshold_chart(
  .data,
  col_1,
  col_2,
  similarity_threshold = NULL,
  distance_threshold = NULL,
  con = NULL
)
```

## Arguments

- .data:

  A data frame or table name.

- col_1, col_2:

  Column names (unquoted or character).

- similarity_threshold:

  Numeric threshold for similarity metrics (\>= to include). Applies to
  jaro_winkler, jaro, jaccard, cosine.

- distance_threshold:

  Integer threshold for distance metrics (\<= to include). Applies to
  levenshtein.

- con:

  A DBI connection. If `NULL`, uses R-side computation.

## Value

A `ggplot2` object.
