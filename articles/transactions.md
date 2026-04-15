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
#> Comparisons memo overlap with the blocking rule and will not be updated.
#> Comparisons amount overlap with the blocking rule and will not be updated.
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
#>     prior: 2.206239e-05
#>     comparisons: # A tibble: 14 × 4
#>      comparisons:    comparison       gamma_level        m       u
#>      comparisons:    <chr>                  <int>    <dbl>   <dbl>
#>      comparisons:  1 amount                     0 0.0177   0.875  
#>      comparisons:  2 amount                     1 0.00171  0.0873 
#>      comparisons:  3 amount                     2 0.230    0.0266 
#>      comparisons:  4 amount                     3 0.313    0.00743
#>      comparisons:  5 amount                     4 0.438    0.00376
#>      comparisons:  6 memo                       0 0.00543  0.856  
#>      comparisons:  7 memo                       1 0.143    0.111  
#>      comparisons:  8 memo                       2 0.274    0.0279 
#>      comparisons:  9 memo                       3 0.577    0.00486
#>      comparisons: 10 transaction_date           0 0.000999 0.719  
#>      comparisons: 11 transaction_date           1 0.0402   0.168  
#>      comparisons: 12 transaction_date           2 0.0899   0.0600 
#>      comparisons: 13 transaction_date           3 0.473    0.0313 
#>      comparisons: 14 transaction_date           4 0.396    0.0211
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
#> # A tibble: 113,557 × 7
#>    unique_id_l unique_id_r match_weight match_probability gamma_amount
#>  *       <dbl>       <dbl>        <dbl>             <dbl>        <int>
#>  1        1835        1835        11.7            0.0681             4
#>  2        1297        1297        11.7            0.0681             4
#>  3         281         281        11.7            0.0681             4
#>  4        2008       21187         7.94           0.00538            2
#>  5        1242        7224         7.94           0.00538            2
#>  6        3534        3534         8.10           0.00600            4
#>  7        3632        3632         7.94           0.00538            2
#>  8        3093        3073         7.94           0.00538            2
#>  9        4732        4730         7.94           0.00538            2
#> 10        5907       22331         7.94           0.00538            2
#> # ℹ 113,547 more rows
#> # ℹ 2 more variables: gamma_memo <int>, gamma_transaction_date <int>
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
#> # A tibble: 101 × 16
#>    threshold    tp      fp    fn     tn fn_blocking_miss precision recall     f1
#>        <dbl> <int>   <int> <int>  <int>            <int>     <dbl>  <dbl>  <dbl>
#>  1  3.80e-12 45326 1276239     0      0                0    0.0343      1 0.0663
#>  2  3.94e-12 45326 1234376     0  41863                0    0.0354      1 0.0684
#>  3  6.53e-10 45326 1207339     0  68900                0    0.0362      1 0.0698
#>  4  6.77e-10 45326 1171563     0 104676                0    0.0372      1 0.0718
#>  5  7.67e-10 45326 1165716     0 110523                0    0.0374      1 0.0722
#>  6  7.94e-10 45326 1121031     0 155208                0    0.0389      1 0.0748
#>  7  1.68e- 9 45326 1106345     0 169894                0    0.0394      1 0.0757
#>  8  4.10e- 9 45326 1084205     0 192034                0    0.0401      1 0.0772
#>  9  4.25e- 9 45326 1067948     0 208291                0    0.0407      1 0.0782
#> 10  5.89e- 9 45326 1065868     0 210371                0    0.0408      1 0.0784
#> # ℹ 91 more rows
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
#> # A tibble: 586 × 6
#>    unique_id_l unique_id_r match_weight match_probability true_label error_type 
#>          <dbl>       <dbl>        <dbl>             <dbl> <lgl>      <chr>      
#>  1       27106       29919         16.2             0.625 FALSE      false_posi…
#>  2         319       44080         17.7             0.822 FALSE      false_posi…
#>  3        1873       28525         18.0             0.852 FALSE      false_posi…
#>  4        1336       15748         17.7             0.822 FALSE      false_posi…
#>  5        1159       16844         17.7             0.822 FALSE      false_posi…
#>  6         382        7770         17.7             0.822 FALSE      false_posi…
#>  7        1932        5109         17.7             0.822 FALSE      false_posi…
#>  8        2195       18950         17.7             0.822 FALSE      false_posi…
#>  9        4039       34405         18.0             0.852 FALSE      false_posi…
#> 10        2881       16960         18.0             0.852 FALSE      false_posi…
#> # ℹ 576 more rows
```

``` r
errors[errors$error_type == 'false_negative', ]
#> # A tibble: 29,183 × 6
#>    unique_id_l unique_id_r match_weight match_probability true_label error_type 
#>          <dbl>       <dbl>        <dbl>             <dbl> <lgl>      <chr>      
#>  1        4800        4800        11.5            0.0582  TRUE       false_nega…
#>  2        4959        4959        10.7            0.0365  TRUE       false_nega…
#>  3        5733        5733        12.6            0.121   TRUE       false_nega…
#>  4        5367        5367        12.6            0.121   TRUE       false_nega…
#>  5        5810        5810        10.2            0.0257  TRUE       false_nega…
#>  6        5545        5545        10.3            0.0275  TRUE       false_nega…
#>  7        5979        5979        10.2            0.0257  TRUE       false_nega…
#>  8        4845        4845         6.34           0.00178 TRUE       false_nega…
#>  9        4943        4943        10.7            0.0365  TRUE       false_nega…
#> 10        4927        4927        10.7            0.0365  TRUE       false_nega…
#> # ℹ 29,173 more rows
```

## Cleanup

``` r
il_cleanup(model)
DBI::dbDisconnect(con, shutdown = TRUE)
```
