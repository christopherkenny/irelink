# Deduplicating 50k Synthetic Records

This vignette reproduces the [Splink “Deduplicate 50k synthetic”
demo](https://moj-analytical-services.github.io/splink/demos/examples/duckdb/deduplicate_50k_synthetic.html)
in `irelink`. The data is based on historical people scraped from
Wikidata and includes duplicate records with realistic errors such as
typos, missing values, and swapped fields. The `cluster` column provides
the ground-truth entity labels used in evaluation.

This vignette requires
[nanoparquet](https://cran.r-project.org/package=nanoparquet) to read
the remote Parquet file and only compiles when the package and the data
URL are both available.

## Load the data

``` r

library(irelink)
#> 
#> Attaching package: 'irelink'
#> The following object is masked from 'package:base':
#> 
#>     months
library(ggplot2)

df
#> # A data frame: 50,578 × 11
#>    unique_id   cluster  full_name     first_and_surname first_name surname dob  
#>    <chr>       <chr>    <chr>         <chr>             <chr>      <chr>   <chr>
#>  1 Q2296770-1  Q2296770 thomas cliff… thomas chudleigh  thomas     chudle… 1630…
#>  2 Q2296770-2  Q2296770 thomas of ch… thomas chudleigh  thomas     chudle… 1630…
#>  3 Q2296770-3  Q2296770 tom 1st baro… tom chudleigh     tom        chudle… 1630…
#>  4 Q2296770-4  Q2296770 thomas 1st c… thomas chudleigh  thomas     chudle… 1630…
#>  5 Q2296770-5  Q2296770 thomas cliff… thomas chudleigh  thomas     chudle… 1630…
#>  6 Q2296770-6  Q2296770 thomas cliff… thomas chudleigh  thomas     chudle… 1630…
#>  7 Q2296770-7  Q2296770 tom baron ch… tom chudleigh     tom        chudle… 1630…
#>  8 Q2296770-8  Q2296770 tom clifford… tom chudleigh     tom        chudle… NA   
#>  9 Q2296770-9  Q2296770 thomas cliff… thomas chudleigh  thomas     chudle… 1630…
#> 10 Q2296770-10 Q2296770 thomas cliff… thomas chudleigh  thomas     chudle… NA   
#> # ℹ 50,568 more rows
#> # ℹ 4 more variables: birth_place <chr>, postcode_fake <chr>, gender <chr>,
#> #   occupation <chr>
```

## Profile the data

Use completeness and value distributions to choose blocking rules and
comparisons:

``` r

con <- DBI::dbConnect(duckdb::duckdb())
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpnDN4FZ/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
```

``` r

df |>
  il_completeness(con = con) |>
  autoplot()
```

![](deduplicate-50k_files/figure-html/completeness-1.png)

``` r

il_profile(df, first_name, surname, dob, birth_place, con = con, top_n = 8)
#> # A tibble: 32 × 3
#>    column     value       n
#>    <chr>      <chr>   <dbl>
#>  1 first_name william  2780
#>  2 first_name john     2736
#>  3 first_name thomas   1448
#>  4 first_name george   1415
#>  5 first_name henry    1306
#>  6 first_name james    1265
#>  7 first_name sir      1262
#>  8 first_name charles  1216
#>  9 surname    NA       4515
#> 10 surname    baronet   615
#> # ℹ 22 more rows
```

## Choose blocking rules

``` r

il_suggest_blocking(df, con = con)
#> # A tibble: 10 × 6
#>    rule              n_distinct coverage   n_pairs pct_of_cartesian score
#>    <chr>                  <int>    <dbl>     <int>            <dbl> <dbl>
#>  1 cluster                 5156    1        303961           0.0238 1.000
#>  2 full_name              25573    0.999     87973           0.0069 0.999
#>  3 first_and_surname      20479    0.999    262393           0.0205 0.998
#>  4 first_name              4413    0.999  16372982           1.28   0.986
#>  5 surname                 6195    0.911    733085           0.0573 0.910
#>  6 birth_place             2373    0.863   4923790           0.385  0.860
#>  7 postcode_fake          12363    0.774    112172           0.0088 0.774
#>  8 dob                     8985    0.774   1549081           0.121  0.774
#>  9 occupation               453    0.5    12573944           0.983  0.495
#> 10 gender                     7    0.778 561648436          43.9    0.436
```

The `cumulative_pairs` column shows the total number of unique pairs
produced so far:

``` r

il_count_pairs(
  df,
  block_on(surname, dob),
  block_on(first_name, dob),
  block_on(first_name, surname),
  block_on(dob, birth_place),
  con = con
)
#> # A tibble: 4 × 4
#>   rule                 n_pairs cumulative_pairs pct_of_cartesian
#>   <chr>                  <dbl>            <dbl>            <dbl>
#> 1 surname & dob          62893            62893           0.0049
#> 2 first_name & dob       67757            92798           0.0073
#> 3 first_name & surname  243656           298602           0.0233
#> 4 dob & birth_place      66657           314273           0.0246
```

## Define the specification

Apply term-frequency adjustment to `birth_place` and `occupation` so
common values such as “London” receive less weight than rare ones:

``` r

spec <- il_spec() |>
  il_compare(first_name, cl_name()) |>
  il_compare(surname, cl_name()) |>
  il_compare(dob, cl_dob()) |>
  il_compare(postcode_fake, cl_postcode()) |>
  il_compare(birth_place, cl_exact(term_frequency = TRUE)) |>
  il_compare(occupation, cl_exact(term_frequency = TRUE)) |>
  il_block_on(first_name ~ il_substr(1, 3), surname ~ il_substr(1, 4)) |>
  il_block_on(surname, dob) |>
  il_block_on(first_name, dob) |>
  il_block_on(postcode_fake, first_name) |>
  il_block_on(postcode_fake, surname) |>
  il_block_on(dob, birth_place) |>
  il_block_on(postcode_fake ~ il_substr(1, 3), dob) |>
  il_block_on(postcode_fake ~ il_substr(1, 3), first_name) |>
  il_block_on(postcode_fake ~ il_substr(1, 3), surname) |>
  il_block_on(
    first_name ~ il_substr(1, 2),
    surname ~ il_substr(1, 2),
    dob ~ il_substr(1, 4)
  )

spec
#> Linkage Specification
#>   Comparisons (6):
#>     first_name : levels
#>     surname : levels
#>     dob : levels
#>     postcode_fake : levels
#>     birth_place : exact
#>     occupation : exact
#>   Blocking rules (10, OR-ed):
#>     1. first_name [il_substr(1,3)], surname [il_substr(1,4)]
#>     2. surname, dob
#>     3. first_name, dob
#>     4. postcode_fake, first_name
#>     5. postcode_fake, surname
#>     6. dob, birth_place
#>     7. postcode_fake [il_substr(1,3)], dob
#>     8. postcode_fake [il_substr(1,3)], first_name
#>     9. postcode_fake [il_substr(1,3)], surname
#>     10. first_name [il_substr(1,2)], surname [il_substr(1,2)], dob [il_substr(1,4)]
```

## Train the model

``` r

model <- df |>
  il_model(spec = spec, con = con) |>
  il_estimate_prior(
    block_on(first_name, surname, dob),
    block_on(dob, postcode_fake),
    recall = 0.6
  ) |>
  il_estimate_u(max_pairs = 5e6) |>
  il_estimate_em(block_on(first_name, surname)) |>
  il_estimate_em(block_on(dob))
#> EM trained: dob, postcode_fake, birth_place, and occupation | skipped (blocked
#> on): first_name and surname
#> EM trained: first_name, surname, postcode_fake, birth_place, and occupation |
#> skipped (blocked on): dob
```

## Inspect the trained model

``` r

summary(model)
#> irelink Model
#>   Status: Trained
#>   Link type: dedupe
#>   Records: 50578
#>   Comparisons: 6
#>   Blocking rules: 10
#> 
#>   Parameters:
#>     prior: 0.0002209564
#>     comparisons: # A tibble: 25 × 4
#>      comparisons:    comparison gamma_level      m        u
#>      comparisons:    <chr>            <int>  <dbl>    <dbl>
#>      comparisons:  1 first_name           0 0.188  0.962   
#>      comparisons:  2 first_name           1 0.122  0.0192  
#>      comparisons:  3 first_name           2 0.0756 0.00389 
#>      comparisons:  4 first_name           3 0.0616 0.00157 
#>      comparisons:  5 first_name           4 0.553  0.0129  
#>      comparisons:  6 surname              0 0.0649 0.981   
#>      comparisons:  7 surname              1 0.0229 0.0176  
#>      comparisons:  8 surname              2 0.0392 0.000485
#>      comparisons:  9 surname              3 0.0937 0.000352
#>      comparisons: 10 surname              4 0.779  0.000678
#>      comparisons: # ℹ 15 more rows
#>     u_estimation: 5000703
#>      u_estimation: FALSE
#>      u_estimation: NULL
#>      u_estimation: NULL
#>      u_estimation: 5000000
#>      u_estimation: 1
```

``` r

autoplot(model)
```

![](deduplicate-50k_files/figure-html/weights-plot-1.png)

``` r

autoplot(model, type = 'parameters')
```

![](deduplicate-50k_files/figure-html/params-plot-1.png)

``` r

autoplot(il_unlinkables(model))
```

![](deduplicate-50k_files/figure-html/unlinkables-1.png)

## Predict

``` r

predictions <- predict(model, threshold = 0.5)
predictions
#> # A tibble: 237,463 × 13
#>    unique_id_l  unique_id_r  gamma_first_name gamma_surname gamma_dob
#>  * <chr>        <chr>                   <int>         <int>     <int>
#>  1 Q16066242-13 Q7527034-7                  4             4        -1
#>  2 Q16066242-11 Q75867928-11                4             4        -1
#>  3 Q16066242-13 Q75867928-11                4             4        -1
#>  4 Q16066242-5  Q75867928-7                 4             4         0
#>  5 Q16066242-6  Q75867928-5                 4             4        -1
#>  6 Q16066242-4  Q75867928-3                 4             4         0
#>  7 Q16066242-4  Q75867928-1                 4             4         0
#>  8 Q16066242-3  Q2248538-12                 4             4        -1
#>  9 Q44279-4     Q44279-7                    4             4         4
#> 10 Q19335644-5  Q19335644-7                 3             4        -1
#> # ℹ 237,453 more rows
#> # ℹ 8 more variables: gamma_postcode_fake <int>, gamma_birth_place <int>,
#> #   gamma_occupation <int>, match_weight <dbl>, tf_adj_birth_place <dbl>,
#> #   tf_adj_occupation <dbl>, total_match_weight <dbl>, match_probability <dbl>
```

``` r

autoplot(predictions)
```

![](deduplicate-50k_files/figure-html/histogram-1.png)

``` r

autoplot(predictions, which = 1)
```

![](deduplicate-50k_files/figure-html/waterfall-1.png)

## Cluster

``` r

clusters <- il_cluster(predictions, threshold = 0.95)
clusters
#> # A tibble: 46,088 × 2
#>    unique_id    cluster_id         
#>    <chr>        <chr>              
#>  1 Q21664937-21 cluster_Q21664937-1
#>  2 Q6227471-12  cluster_Q6227471-1 
#>  3 Q266468-11   cluster_Q266468-1  
#>  4 Q494264-3    cluster_Q494264-1  
#>  5 Q4885744-1   cluster_Q4885744-1 
#>  6 Q442983-12   cluster_Q442983-1  
#>  7 Q48689010-3  cluster_Q48689010-1
#>  8 Q5538920-4   cluster_Q5538920-1 
#>  9 Q97801414-1  cluster_Q97801414-1
#> 10 Q699617-3    cluster_Q699617-1  
#> # ℹ 46,078 more rows
```

## Evaluate against ground truth

``` r

acc <- il_accuracy(model, labels_col = 'cluster')
acc
#> # A tibble: 3,526 × 16
#>     threshold     tp     fp     fn    tn fn_blocking_miss precision recall    f1
#>         <dbl>  <int>  <int>  <int> <int>            <int>     <dbl>  <dbl> <dbl>
#>  1    0       203544 247197 100417     0           100417     0.452  0.670 0.539
#>  2    6.14e-9 203544 247197 100417     0           100417     0.452  0.670 0.539
#>  3    3.51e-8 203544 247157 100417    40           100417     0.452  0.670 0.539
#>  4    5.66e-8 203544 247114 100417    83           100417     0.452  0.670 0.539
#>  5    9.24e-8 203544 246732 100417   465           100417     0.452  0.670 0.540
#>  6    9.28e-8 203544 246731 100417   466           100417     0.452  0.670 0.540
#>  7    1.19e-7 203544 246731 100417   466           100417     0.452  0.670 0.540
#>  8    1.21e-7 203544 246701 100417   496           100417     0.452  0.670 0.540
#>  9    1.99e-7 203544 246652 100417   545           100417     0.452  0.670 0.540
#> 10    3.24e-7 203544 246591 100417   606           100417     0.452  0.670 0.540
#> # ℹ 3,516 more rows
#> # ℹ 7 more variables: f2 <dbl>, f0_5 <dbl>, specificity <dbl>, npv <dbl>,
#> #   accuracy <dbl>, p4 <dbl>, phi <dbl>
```

When you use `labels_col`, the evaluation derives all true duplicate
pairs from the ground-truth cluster column. Some true pairs may never be
generated by the blocking rules. Those pairs count as false negatives at
every threshold. As a result, the maximum recall in the accuracy, ROC,
and precision-recall plots is the blocking recall:

``` r

acc0 <- acc[acc$threshold == min(acc$threshold), ]
acc0$tp / (acc0$tp + acc0$fn)
#> [1] 0.6696385
```

``` r

autoplot(acc)
```

![](deduplicate-50k_files/figure-html/accuracy-plot-1.png)

``` r

autoplot(il_roc(model, labels_col = 'cluster'))
```

![](deduplicate-50k_files/figure-html/roc-1.png)

``` r

autoplot(il_precision_recall(model, labels_col = 'cluster'))
```

![](deduplicate-50k_files/figure-html/pr-1.png)

### Error inspection

``` r

errors <- il_errors(model, labels_col = 'cluster', threshold = 0.999)
errors[errors$error_type == 'false_positive', ]
#> # A tibble: 368 × 6
#>    unique_id_l unique_id_r match_weight match_probability true_label error_type 
#>    <chr>       <chr>              <dbl>             <dbl> <lgl>      <chr>      
#>  1 Q7528045-4  Q7528085-7          26.2             1.000 FALSE      false_posi…
#>  2 Q5583974-11 Q6130041-4          22.4             0.999 FALSE      false_posi…
#>  3 Q3568485-2  Q3568487-1          43.5             1.000 FALSE      false_posi…
#>  4 Q7528045-6  Q7528085-4          28.7             1.000 FALSE      false_posi…
#>  5 Q4088004-3  Q545038-7           24.9             1.000 FALSE      false_posi…
#>  6 Q3568485-9  Q3568487-1          43.5             1.000 FALSE      false_posi…
#>  7 Q5583974-1  Q6130041-6          22.4             0.999 FALSE      false_posi…
#>  8 Q4088004-3  Q545038-1           24.9             1.000 FALSE      false_posi…
#>  9 Q28054162-5 Q6252444-7          23.0             0.999 FALSE      false_posi…
#> 10 Q7528045-3  Q7528085-4          25.5             1.000 FALSE      false_posi…
#> # ℹ 358 more rows
```

Some false negatives occur because the true pair was never generated by
any blocking rule:

``` r

errors <- il_errors(model, labels_col = 'cluster', threshold = 0.5)
errors[errors$error_type == 'false_negative', ]
#> # A tibble: 112,363 × 6
#>    unique_id_l  unique_id_r match_weight match_probability true_label error_type
#>    <chr>        <chr>              <dbl>             <dbl> <lgl>      <chr>     
#>  1 Q903516-14   Q903516-8           8.52            0.0750 TRUE       false_neg…
#>  2 Q16066489-12 Q16066489-…         9.50            0.138  TRUE       false_neg…
#>  3 Q6526304-12  Q6526304-17        10.6             0.260  TRUE       false_neg…
#>  4 Q1508011-10  Q1508011-3         11.2             0.343  TRUE       false_neg…
#>  5 Q5722403-1   Q5722403-17        11.2             0.343  TRUE       false_neg…
#>  6 Q105533881-… Q105533881…        10.2             0.208  TRUE       false_neg…
#>  7 Q6286514-15  Q6286514-9          5.97            0.0137 TRUE       false_neg…
#>  8 Q18527189-1  Q18527189-5        12.0             0.478  TRUE       false_neg…
#>  9 Q16030023-16 Q16030023-…         9.69            0.155  TRUE       false_neg…
#> 10 Q19560783-13 Q19560783-9         7.12            0.0299 TRUE       false_neg…
#> # ℹ 112,353 more rows
```

## Cleanup

``` r

il_cleanup(model)
DBI::dbDisconnect(con, shutdown = TRUE)
```

`il_cleanup(model)` is model-scoped. If an interactive run failed before
you kept the model object, call `il_cleanup_all(con)` to remove all
`irelink` tables from the connection before disconnecting.
