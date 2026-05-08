# Phonetic Match Chart

Visualizes phonetic coding agreement between two columns. Shows how
Soundex groupings match across pairs.

## Usage

``` r
il_phonetic_chart(.data, col_1, col_2, con = NULL)
```

## Arguments

- .data:

  A data frame or character table name.

- col_1, col_2:

  Column names (unquoted or character).

- con:

  A DBI connection. If provided and DuckDB or PostgreSQL, computes
  Soundex in SQL.

## Value

A `ggplot2` object.
