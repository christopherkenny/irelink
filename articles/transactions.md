# Linking Banking Transactions

This vignette replicates the [Splink “Linking banking transactions”
demo](https://moj-analytical-services.github.io/splink/demos/examples/duckdb/transactions.html)
using `irelink`. It demonstrates two-table linking
(`link_type = "link"`), matching each outgoing payment in the origin
table to its corresponding incoming payment in the destination table.

The data is synthetic and designed to be challenging: amounts differ due
to fees and exchange-rate effects, dates shift by a few days, and memos
are sometimes truncated. Since every origin payment has exactly one
destination counterpart, the prior match probability is `1 / n_origin`.

This vignette requires the
[nanoparquet](https://cran.r-project.org/package=nanoparquet) package to
read the remote Parquet files and will only compile when the package and
data URLs are both available.

## Load the data

``` r

library(irelink)
#> 
#> Attaching package: 'irelink'
#> The following object is masked from 'package:base':
#> 
#>     months
library(ggplot2)

df_origin
#> # A data frame: 45,326 × 5
#>    ground_truth memo            transaction_date  amount unique_id
#>           <dbl> <chr>           <date>             <dbl>     <dbl>
#>  1            0 MATTHIAS C paym 2022-03-28          36.4         0
#>  2            1 M CORVINUS dona 2022-02-14         222.          1
#>  3            2 M C donation BG 2022-05-04         450.          2
#>  4            3 M C BGC         2022-03-03         208.          3
#>  5            4 M CORVINUS  CSH 2022-02-04          79.7         4
#>  6            5 M C  WRE        2022-03-26         835.          5
#>  7            6 M CORVINUS CSH  2022-05-01          66.7         6
#>  8            7 M C 1b097ab5 CH 2022-03-15       26246.          7
#>  9            8 M C  WRE        2022-03-26          92.8         8
#> 10            9 M C payment CHQ 2022-05-04         211.          9
#> # ℹ 45,316 more rows
df_destination
#> # A data frame: 45,326 × 5
#>    ground_truth memo                     transaction_date  amount unique_id
#>           <dbl> <chr>                    <date>             <dbl>     <dbl>
#>  1            0 "MATTHIAS C payment BGC" 2022-03-29          36.4         0
#>  2            1 "M CORVINUS BGC"         2022-02-16         222.          1
#>  3            2 "M C"                    2022-05-05         450.          2
#>  4            3 "M C payment"            2022-03-04         199.          3
#>  5            4 "M CORVINUS "            2022-02-05          79.7         4
#>  6            5 "M C "                   2022-03-27         835.          5
#>  7            6 "M CORVINUS dona"        2022-05-05          66.7         6
#>  8            7 "M C CHQ"                2022-03-27       25908.          7
#>  9            8 "M C  WRE"               2022-03-27          91.9         8
#> 10            9 "M C payment CHQ"        2022-05-17         212.          9
#> # ℹ 45,316 more rows
```

## Profile the data

``` r

con <- DBI::dbConnect(duckdb::duckdb())
```

``` r

il_profile(df_origin, memo, transaction_date, amount, con = con, top_n = 8)
#> # A tibble: 24 × 3
#>    column           value               n
#>    <chr>            <chr>           <dbl>
#>  1 memo             J B payment BGC    27
#>  2 memo             J B donation BG    25
#>  3 memo             J B money BGC      24
#>  4 memo             J B  BGC           21
#>  5 memo             J S money BGC      18
#>  6 memo             J P  BGC           18
#>  7 memo             A B money BGC      18
#>  8 memo             A M donation BG    17
#>  9 transaction_date 19122             696
#> 10 transaction_date 19119             693
#> # ℹ 14 more rows
```

## Choose blocking rules

Because corresponding records differ systematically — amounts change due
to fees, dates shift, memos are truncated — blocking rules must be
generous enough to capture true matches while still reducing the pair
space dramatically. The rules below use SQL expressions via `.where`:

``` r

counts <- il_count_pairs(
  df_origin,
  df_destination,
  # Same year-month, similar memo prefix, amount ratio within 30%
  block_on(
    .where = paste(
      "strftime(l.transaction_date, '%Y%m') = strftime(r.transaction_date, '%Y%m')",
      'AND substr(l.memo, 1, 3) = substr(r.memo, 1, 3)',
      'AND l.amount / r.amount > 0.7 AND l.amount / r.amount < 1.3'
    )
  ),
  # Same but offset by 15 days to catch month boundaries
  block_on(
    .where = paste(
      "strftime(l.transaction_date + 15, '%Y%m') = strftime(r.transaction_date, '%Y%m')",
      'AND substr(l.memo, 1, 3) = substr(r.memo, 1, 3)',
      'AND l.amount / r.amount > 0.7 AND l.amount / r.amount < 1.3'
    )
  ),
  # Memo prefix (first 9 characters)
  block_on(.where = 'substr(l.memo, 1, 9) = substr(r.memo, 1, 9)'),
  # Rounded amount + same week
  block_on(
    .where = paste(
      'round(l.amount / 2, 0) * 2 = round(r.amount / 2, 0) * 2',
      'AND yearweek(r.transaction_date) = yearweek(l.transaction_date)'
    )
  ),
  # Amount offset + week offset
  block_on(
    .where = paste(
      'round(l.amount / 2, 0) * 2 = round((r.amount + 1) / 2, 0) * 2',
      'AND yearweek(r.transaction_date) = yearweek(l.transaction_date + 4)'
    )
  ),
  # Ground-truth "cheat" rule for completeness
  block_on(unique_id),
  con = con,
  link_type = 'link'
)
counts
#> # A tibble: 6 × 4
#>   rule                                 n_pairs cumulative_pairs pct_of_cartesian
#>   <chr>                                  <dbl>            <dbl>            <dbl>
#> 1 strftime(l.transaction_date, '%Y%m'…  301614           301614           0.0147
#> 2 strftime(l.transaction_date + 15, '…  281675           428250           0.0208
#> 3 substr(l.memo, 1, 9) = substr(r.mem…  330510           710190           0.0346
#> 4 round(l.amount / 2, 0) * 2 = round(…  353563          1051372           0.0512
#> 5 round(l.amount / 2, 0) * 2 = round(…  352877          1321538           0.0643
#> 6 unique_id                              45326          1321565           0.0643
```

``` r

autoplot(counts)
```

![](transactions_files/figure-html/count-pairs-plot-1.png)

## Define the specification

The `transaction_date` comparison is one-sided: payments can only
*arrive* after they are *sent*, so the comparison checks
`destination_date - origin_date` is between 0 and *N* days:

``` r

spec <- il_spec() |>
  il_compare(amount, cl_pct_diff(0.01, 0.03, 0.10, 0.30)) |>
  il_compare(memo, cl_levenshtein(2, 6, 10)) |>
  il_compare(
    transaction_date,
    cl_levels(
      cl_null(),
      cl_custom('(r.{col} - l.{col}) BETWEEN 0 AND 1'),
      cl_custom('(r.{col} - l.{col}) BETWEEN 0 AND 4'),
      cl_custom('(r.{col} - l.{col}) BETWEEN 0 AND 10'),
      cl_custom('(r.{col} - l.{col}) BETWEEN 0 AND 30'),
      cl_else()
    )
  ) |>
  il_block_on(
    .where = paste(
      "strftime(l.transaction_date, '%Y%m') = strftime(r.transaction_date, '%Y%m')",
      'AND substr(l.memo, 1, 3) = substr(r.memo, 1, 3)',
      'AND l.amount / r.amount > 0.7 AND l.amount / r.amount < 1.3'
    )
  ) |>
  il_block_on(
    .where = paste(
      "strftime(l.transaction_date + 15, '%Y%m') = strftime(r.transaction_date, '%Y%m')",
      'AND substr(l.memo, 1, 3) = substr(r.memo, 1, 3)',
      'AND l.amount / r.amount > 0.7 AND l.amount / r.amount < 1.3'
    )
  ) |>
  il_block_on(.where = 'substr(l.memo, 1, 9) = substr(r.memo, 1, 9)') |>
  il_block_on(
    .where = paste(
      'round(l.amount / 2, 0) * 2 = round(r.amount / 2, 0) * 2',
      'AND yearweek(r.transaction_date) = yearweek(l.transaction_date)'
    )
  ) |>
  il_block_on(
    .where = paste(
      'round(l.amount / 2, 0) * 2 = round((r.amount + 1) / 2, 0) * 2',
      'AND yearweek(r.transaction_date) = yearweek(l.transaction_date + 4)'
    )
  ) |>
  il_block_on(unique_id)

spec
#> Linkage Specification
#>   Comparisons (3):
#>     amount : pct_diff
#>     memo : levenshtein
#>     transaction_date : levels
#>   Blocking rules (6, OR-ed):
#>     1. WHERE strftime(l.transaction_date, '%Y%m') = strftime(r.transaction_date, '%Y%m') AND substr(l.memo, 1, 3) = substr(r.memo, 1, 3) AND l.amount / r.amount > 0.7 AND l.amount / r.amount < 1.3
#>     2. WHERE strftime(l.transaction_date + 15, '%Y%m') = strftime(r.transaction_date, '%Y%m') AND substr(l.memo, 1, 3) = substr(r.memo, 1, 3) AND l.amount / r.amount > 0.7 AND l.amount / r.amount < 1.3
#>     3. WHERE substr(l.memo, 1, 9) = substr(r.memo, 1, 9)
#>     4. WHERE round(l.amount / 2, 0) * 2 = round(r.amount / 2, 0) * 2 AND yearweek(r.transaction_date) = yearweek(l.transaction_date)
#>     5. WHERE round(l.amount / 2, 0) * 2 = round((r.amount + 1) / 2, 0) * 2 AND yearweek(r.transaction_date) = yearweek(l.transaction_date + 4)
#>     6. unique_id
```

## Train the model

``` r

model <- il_model(
  df_origin,
  df_destination,
  spec = spec,
  con = con,
  link_type = 'link'
)
model$params$prior <- 1 / nrow(df_origin)
model <- il_estimate_u(model, max_pairs = 1e6) |>
  il_estimate_em(block_on(memo)) |>
  il_estimate_em(block_on(amount))
#> EM trained: amount and transaction_date | skipped (blocked on): memo
#> EM trained: memo and transaction_date | skipped (blocked on): amount
```

## Inspect the trained model

``` r

summary(model)
#> irelink Model
#>   Status: Trained
#>   Link type: link
#>   Records: 45326
#>   Records (right): 45326
#>   Comparisons: 3
#>   Blocking rules: 6
#> 
#>   Parameters:
#>     prior: 0.003723228
#>     comparisons: # A tibble: 14 × 4
#>      comparisons:    comparison       gamma_level        m       u
#>      comparisons:    <chr>                  <int>    <dbl>   <dbl>
#>      comparisons:  1 amount                     0 0.001000 0.875  
#>      comparisons:  2 amount                     1 0.001000 0.0873 
#>      comparisons:  3 amount                     2 0.232    0.0266 
#>      comparisons:  4 amount                     3 0.319    0.00743
#>      comparisons:  5 amount                     4 0.447    0.00376
#>      comparisons:  6 memo                       0 0.0500   0.856  
#>      comparisons:  7 memo                       1 0.145    0.111  
#>      comparisons:  8 memo                       2 0.263    0.0279 
#>      comparisons:  9 memo                       3 0.543    0.00486
#>      comparisons: 10 transaction_date           0 0.001000 0.719  
#>      comparisons: 11 transaction_date           1 0.0456   0.168  
#>      comparisons: 12 transaction_date           2 0.0931   0.0600 
#>      comparisons: 13 transaction_date           3 0.468    0.0313 
#>      comparisons: 14 transaction_date           4 0.392    0.0211 
#>     u_estimation: 1e+06
#>      u_estimation: FALSE
#>      u_estimation: NULL
#>      u_estimation: NULL
#>      u_estimation: 1000000
#>      u_estimation: 1
```

``` r

autoplot(model)
```

![](transactions_files/figure-html/weights-plot-1.png)

``` r

autoplot(model, type = 'parameters')
```

![](transactions_files/figure-html/params-plot-1.png)

## Predict

``` r

predictions <- predict(model, threshold = 0.001)
predictions
#> # A tibble: 594,672 × 8
#>    unique_id_l unique_id_r gamma_amount gamma_memo gamma_transaction_date
#>  *       <dbl>       <dbl>        <int>      <int>                  <int>
#>  1           5           8            0          3                      4
#>  2         215         218            1          3                      1
#>  3         354       43914            0          3                      3
#>  4         835         850            0          3                      3
#>  5        1081       16545            0          3                      3
#>  6        1185       17712            1          3                      1
#>  7        1252       44620            4          3                      0
#>  8        1387       30947            2          3                      0
#>  9        1433       10533            0          3                      3
#> 10        1491        1486            0          3                      3
#> # ℹ 594,662 more rows
#> # ℹ 3 more variables: match_weight <dbl>, total_match_weight <dbl>,
#> #   match_probability <dbl>
```

``` r

autoplot(predictions)
```

![](transactions_files/figure-html/histogram-1.png)

``` r

autoplot(predictions, which = 1)
```

![](transactions_files/figure-html/waterfall-1.png)

## Evaluate against ground truth

``` r

acc <- il_accuracy(model, labels_col = 'ground_truth')
acc
#> # A tibble: 102 × 16
#>    threshold    tp      fp    fn     tn fn_blocking_miss precision recall     f1
#>        <dbl> <int>   <int> <int>  <int>            <int>     <dbl>  <dbl>  <dbl>
#>  1  0        45326 1276239     0      0                0    0.0343      1 0.0663
#>  2  3.47e-10 45326 1276239     0      0                0    0.0343      1 0.0663
#>  3  3.47e- 9 45326 1249201     0  27038                0    0.0350      1 0.0677
#>  4  7.69e- 9 45326 1207339     0  68900                0    0.0362      1 0.0698
#>  5  5.58e- 8 45326 1192653     0  83586                0    0.0366      1 0.0706
#>  6  6.76e- 8 45326 1080324     0 195915                0    0.0403      1 0.0774
#>  7  7.71e- 8 45326 1074477     0 201762                0    0.0405      1 0.0778
#>  8  3.87e- 7 45326 1029792     0 246447                0    0.0422      1 0.0809
#>  9  5.59e- 7 45326 1027712     0 248527                0    0.0422      1 0.0811
#> 10  6.64e- 7 45326 1007379     0 268860                0    0.0431      1 0.0826
#> # ℹ 92 more rows
#> # ℹ 7 more variables: f2 <dbl>, f0_5 <dbl>, specificity <dbl>, npv <dbl>,
#> #   accuracy <dbl>, p4 <dbl>, phi <dbl>
```

``` r

autoplot(acc)
```

![](transactions_files/figure-html/accuracy-plot-1.png)

### Error inspection

``` r

errors <- il_errors(model, labels_col = 'ground_truth', threshold = 0.5)
errors[errors$error_type == 'false_positive', ]
#> # A tibble: 43,970 × 6
#>    unique_id_l unique_id_r match_weight match_probability true_label error_type 
#>          <dbl>       <dbl>        <dbl>             <dbl> <lgl>      <chr>      
#>  1       36781        3174        13.8              0.982 FALSE      false_posi…
#>  2       35523        8810        10.6              0.851 FALSE      false_posi…
#>  3       35323       16071         9.70             0.756 FALSE      false_posi…
#>  4       35586        7877        11.5              0.915 FALSE      false_posi…
#>  5       35830        5101        11.5              0.915 FALSE      false_posi…
#>  6       37241       44723         9.29             0.701 FALSE      false_posi…
#>  7       37614       37631         9.70             0.756 FALSE      false_posi…
#>  8       38786       38790        14.1              0.985 FALSE      false_posi…
#>  9       38815       43926         9.70             0.756 FALSE      false_posi…
#> 10       37803       37809        10.0              0.794 FALSE      false_posi…
#> # ℹ 43,960 more rows
```

``` r

errors[errors$error_type == 'false_negative', ]
#> # A tibble: 5,426 × 6
#>    unique_id_l unique_id_r match_weight match_probability true_label error_type 
#>          <dbl>       <dbl>        <dbl>             <dbl> <lgl>      <chr>      
#>  1       37616       37616       -0.337           0.00295 TRUE       false_nega…
#>  2       38602       38602        5.54            0.148   TRUE       false_nega…
#>  3       36937       36937        7.72            0.440   TRUE       false_nega…
#>  4       38533       38533        6.70            0.280   TRUE       false_nega…
#>  5       38754       38754        7.40            0.387   TRUE       false_nega…
#>  6       38861       38861        8.05            0.497   TRUE       false_nega…
#>  7       37250       37250        2.93            0.0277  TRUE       false_nega…
#>  8       38220       38220        3.24            0.0342  TRUE       false_nega…
#>  9       37289       37289        1.96            0.0143  TRUE       false_nega…
#> 10       38093       38093        7.40            0.387   TRUE       false_nega…
#> # ℹ 5,416 more rows
```

## Cleanup

``` r

il_cleanup(model)
DBI::dbDisconnect(con, shutdown = TRUE)
```

`il_cleanup(model)` is model-scoped. If an interactive run failed before
you kept the model object, call `il_cleanup_all(con)` to remove all
`irelink` tables from the connection before disconnecting.
