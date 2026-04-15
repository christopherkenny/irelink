# Deduplicating 50k Synthetic Records

This vignette replicates the [Splink “Deduplicate 50k synthetic”
demo](https://moj-analytical-services.github.io/splink/demos/examples/duckdb/deduplicate_50k_synthetic.html)
using `irelink`. The data is based on historical persons scraped from
Wikidata, with duplicate records introduced alongside a variety of
realistic errors (typos, missing values, swapped fields). The `cluster`
column provides ground-truth entity labels for evaluation.

This vignette requires the
[nanoparquet](https://cran.r-project.org/package=nanoparquet) package to
read the remote Parquet file and will only compile when the package and
data URL are both available.

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

Profile completeness and value distributions to inform blocking and
comparison choices:

``` r
con <- DBI::dbConnect(duckdb::duckdb())
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

The `cumulative_pairs` column shows the total unique pairs across all
rules so far:

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

Term-frequency adjustment is applied to `birth_place` and `occupation`
so common values (e.g., “London”) receive less weight than rare ones:

``` r
spec <- il_spec() |>
  il_compare(first_name, cl_name()) |>
  il_compare(surname, cl_name()) |>
  il_compare(dob, cl_dob()) |>
  il_compare(postcode_fake, cl_postcode()) |>
  il_compare(birth_place, cl_exact(term_frequency = TRUE)) |>
  il_compare(occupation, cl_exact(term_frequency = TRUE)) |>
  il_block_on(surname, dob) |>
  il_block_on(first_name, dob) |>
  il_block_on(first_name, surname) |>
  il_block_on(dob, birth_place)

spec
#> Linkage Specification
#>   Comparisons (6):
#>     first_name : levels
#>     surname : levels
#>     dob : levels
#>     postcode_fake : levels
#>     birth_place : exact
#>     occupation : exact
#>   Blocking rules (4, OR-ed):
#>     1. surname, dob
#>     2. first_name, dob
#>     3. first_name, surname
#>     4. dob, birth_place
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
```

## Inspect the trained model

``` r
summary(model)
#> irelink Model
#>   Status: Trained
#>   Link type: dedupe
#>   Records: 50578
#>   Comparisons: 6
#>   Blocking rules: 4
#> 
#>   Parameters:
#>     prior: 0.0001053953
#>     comparisons: # A tibble: 25 × 4
#>      comparisons:    comparison gamma_level      m        u
#>      comparisons:    <chr>            <int>  <dbl>    <dbl>
#>      comparisons:  1 first_name           0 0.164  0.963   
#>      comparisons:  2 first_name           1 0.123  0.0179  
#>      comparisons:  3 first_name           2 0.0778 0.00287 
#>      comparisons:  4 first_name           3 0.0633 0.00126 
#>      comparisons:  5 first_name           4 0.571  0.0151  
#>      comparisons:  6 surname              0 0.137  0.985   
#>      comparisons:  7 surname              1 0.0200 0.0135  
#>      comparisons:  8 surname              2 0.0363 0.000346
#>      comparisons:  9 surname              3 0.0870 0.000230
#>      comparisons: 10 surname              4 0.719  0.000963
#>      comparisons: # ℹ 15 more rows
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
#> # A tibble: 111,985 × 12
#>    unique_id_l  unique_id_r match_weight match_probability gamma_first_name
#>  * <chr>        <chr>              <dbl>             <dbl>            <int>
#>  1 Q8004274-1   Q8004274-3          44.6             1.000                4
#>  2 Q8004274-2   Q8004274-3          44.6             1.000                4
#>  3 Q18530939-1  Q18530939-9         42.4             1.000                4
#>  4 Q18530939-2  Q18530939-9         41.3             1.000                4
#>  5 Q18530939-3  Q18530939-9         42.4             1.000                4
#>  6 Q18530939-4  Q18530939-9         30.5             1.000                4
#>  7 Q18530939-6  Q18530939-9         41.9             1.000                2
#>  8 Q18530939-10 Q18530939-9         41.3             1.000                4
#>  9 Q3285335-2   Q3285335-3          42.4             1.000                4
#> 10 Q3285335-12  Q3285335-3          28.6             1.000                4
#> # ℹ 111,975 more rows
#> # ℹ 7 more variables: gamma_surname <int>, gamma_dob <int>,
#> #   gamma_postcode_fake <int>, gamma_birth_place <int>, gamma_occupation <int>,
#> #   tf_adj_birth_place <dbl>, tf_adj_occupation <dbl>
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
#> # A tibble: 36,996 × 2
#>    unique_id    cluster_id          
#>    <chr>        <chr>               
#>  1 Q105945843-3 cluster_Q105945843-1
#>  2 Q5496974-5   cluster_Q5496974-1  
#>  3 Q98761863-5  cluster_Q21462932-1 
#>  4 Q989503-3    cluster_Q989503-1   
#>  5 Q8017455-9   cluster_Q8017455-1  
#>  6 Q4800116-6   cluster_Q4800116-1  
#>  7 Q78006821-3  cluster_Q78006821-1 
#>  8 Q5341712-2   cluster_Q5341712-1  
#>  9 Q61123502-2  cluster_Q61123502-1 
#> 10 Q4799228-4   cluster_Q4799228-1  
#> # ℹ 36,986 more rows
```

## Evaluate against ground truth

``` r
acc <- il_accuracy(model, labels_col = 'cluster')
acc
#> # A tibble: 2,020 × 8
#>    threshold     tp     fp    fn    tn precision recall    f1
#>        <dbl>  <int>  <int> <int> <int>     <dbl>  <dbl> <dbl>
#>  1  2.11e-10 303961 178777     0     0     0.630  1     0.773
#>  2  1.37e- 9 298359 178777  5602     0     0.625  0.982 0.764
#>  3  2.25e- 9 298288 178777  5673     0     0.625  0.981 0.764
#>  4  6.75e- 9 298068 178777  5893     0     0.625  0.981 0.763
#>  5  7.79e- 9 296951 178777  7010     0     0.624  0.977 0.762
#>  6  8.54e- 9 294780 178777  9181     0     0.622  0.970 0.758
#>  7  1.07e- 8 293425 178777 10536     0     0.621  0.965 0.756
#>  8  1.45e- 8 293385 178777 10576     0     0.621  0.965 0.756
#>  9  3.36e- 8 293383 178777 10578     0     0.621  0.965 0.756
#> 10  4.37e- 8 292699 178777 11262     0     0.621  0.963 0.755
#> # ℹ 2,010 more rows
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
#> # A tibble: 21 × 6
#>    unique_id_l unique_id_r match_weight match_probability true_label error_type 
#>    <chr>       <chr>              <dbl>             <dbl> <lgl>      <chr>      
#>  1 Q336670-3   Q3784946-2          27.1             1.000 FALSE      false_posi…
#>  2 Q48818396-1 Q48818466-2         27.3             1.000 FALSE      false_posi…
#>  3 Q48818396-2 Q48818466-1         27.3             1.000 FALSE      false_posi…
#>  4 Q336670-3   Q3784946-1          27.1             1.000 FALSE      false_posi…
#>  5 Q3568485-5  Q3568487-2          32.3             1.000 FALSE      false_posi…
#>  6 Q3568485-5  Q3568487-1          32.3             1.000 FALSE      false_posi…
#>  7 Q17627000-3 Q24845632-8         24.3             1.000 FALSE      false_posi…
#>  8 Q17627000-1 Q24845632-8         24.3             1.000 FALSE      false_posi…
#>  9 Q48818396-2 Q48818466-2         27.3             1.000 FALSE      false_posi…
#> 10 Q3568485-3  Q3568487-2          27.3             1.000 FALSE      false_posi…
#> # ℹ 11 more rows
```

Some false negatives will be because the true pair was never generated
by any blocking rule:

``` r
errors <- il_errors(model, labels_col = 'cluster', threshold = 0.5)
errors[errors$error_type == 'false_negative', ]
#> # A tibble: 155,460 × 6
#>    unique_id_l  unique_id_r match_weight match_probability true_label error_type
#>    <chr>        <chr>              <dbl>             <dbl> <lgl>      <chr>     
#>  1 Q485761-8    Q485761-9           12.0             0.298 TRUE       false_neg…
#>  2 Q6180874-11  Q6180874-20         12.0             0.298 TRUE       false_neg…
#>  3 Q6180874-12  Q6180874-20         12.0             0.298 TRUE       false_neg…
#>  4 Q472639-7    Q472639-9           12.0             0.298 TRUE       false_neg…
#>  5 Q1512-14     Q1512-7             12.0             0.298 TRUE       false_neg…
#>  6 Q2474950-10  Q2474950-5          12.0             0.298 TRUE       false_neg…
#>  7 Q1175801-15  Q1175801-9          12.0             0.298 TRUE       false_neg…
#>  8 Q28094247-15 Q28094247-4         12.0             0.298 TRUE       false_neg…
#>  9 Q734889-13   Q734889-6           12.0             0.298 TRUE       false_neg…
#> 10 Q18671640-10 Q18671640-5         12.0             0.298 TRUE       false_neg…
#> # ℹ 155,450 more rows
```

## Cleanup

``` r
il_cleanup(model)
DBI::dbDisconnect(con, shutdown = TRUE)
```
