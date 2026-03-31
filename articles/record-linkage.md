# Record Linkage Across Datasets

This vignette demonstrates linking records across two separate datasets
using the FEBRL (Freely Extensible Biomedical Record Linkage) benchmark
data. Dataset 4a contains 5,000 original records and dataset 4b contains
5,000 duplicates — one for each original — corrupted with typographical
errors, missing values, and transpositions. Ground truth is encoded in
the `rec_id` column: records sharing the same base number (e.g.,
`rec-1070-org` and `rec-1070-dup-0`) refer to the same entity.

## Setup

``` r
library(irelink)
#> 
#> Attaching package: 'irelink'
#> The following object is masked from 'package:base':
#> 
#>     months
library(ggplot2)
```

## Load the data

``` r
df_a <- head(febrl4a, 1000)
df_b <- head(febrl4b, 1000)

nrow(df_a)
#> [1] 1000
nrow(df_b)
#> [1] 1000
```

``` r
head(df_a)
#> # A tibble: 6 × 11
#>   rec_id    given_name surname street_number address_1 address_2 suburb postcode
#>   <chr>     <chr>      <chr>           <int> <chr>     <chr>     <chr>     <int>
#> 1 rec-1070… michaela   neumann             8 stanley … miami     winst…     4223
#> 2 rec-1016… courtney   painter            12 pinkerto… bega fla… richl…     4560
#> 3 rec-4405… charles    green              38 salkausk… kela      dapto      4566
#> 4 rec-1288… vanessa    parr              905 macquoid… broadbri… south…     2135
#> 5 rec-3585… mikayla    mallon…            37 randwick… avalind   hoppe…     4552
#> 6 rec-298-… blake      howie               1 cutlack … belmont … budge…     6017
#> # ℹ 3 more variables: state <chr>, date_of_birth <int>, soc_sec_id <int>
head(df_b)
#> # A tibble: 6 × 11
#>   rec_id    given_name surname street_number address_1 address_2 suburb postcode
#>   <chr>     <chr>      <chr>           <int> <chr>     <chr>     <chr>     <int>
#> 1 rec-561-… elton      NA                  3 light se… pinehill  winde…     3212
#> 2 rec-2642… mitchell   maxon              47 edkins s… lochaoair north…     3355
#> 3 rec-608-… NA         white              72 lambrigg… kelgoola  broad…     3159
#> 4 rec-3239… elk i      menzies             1 lyster p… NA        north…     2585
#> 5 rec-2886… NA         garang…            NA may maxw… springet… fores…     2342
#> 6 rec-4285… sophie     manson             14 elizabet… manorhou… gorok…     3465
#> # ℹ 3 more variables: state <chr>, date_of_birth <int>, soc_sec_id <int>
```

## Explore data quality

Check completeness across both tables. Table B has more missing values
due to the corruption process:

``` r
con <- DBI::dbConnect(duckdb::duckdb())
comp <- il_completeness(df_a, df_b, con = con)
comp
#> # A tibble: 22 × 5
#>    table   column        n_total n_non_null pct_non_null
#>    <chr>   <chr>           <int>      <int>        <dbl>
#>  1 table_1 rec_id           1000       1000        100  
#>  2 table_1 given_name       1000        979         97.9
#>  3 table_1 surname          1000        990         99  
#>  4 table_1 street_number    1000        968         96.8
#>  5 table_1 address_1        1000        980         98  
#>  6 table_1 address_2        1000        918         91.8
#>  7 table_1 suburb           1000        985         98.5
#>  8 table_1 postcode         1000       1000        100  
#>  9 table_1 state            1000        991         99.1
#> 10 table_1 date_of_birth    1000        979         97.9
#> # ℹ 12 more rows
```

``` r
autoplot(comp)
```

![](record-linkage_files/figure-html/completeness-plot-1.png)

## Define the specification

For linking (as opposed to deduplication), set `link_type = "link"` when
creating the model. Comparisons use name similarity, date-of-birth
matching, and postcode exact matching:

``` r
spec <- il_spec() |>
  il_compare(given_name, cl_name()) |>
  il_compare(surname, cl_name()) |>
  il_compare(date_of_birth, cl_exact()) |>
  il_compare(postcode, cl_exact()) |>
  il_block_on(surname) |>
  il_block_on(given_name)

spec
#> Linkage Specification
#>   Comparisons (4):
#>     given_name : levels
#>     surname : levels
#>     date_of_birth : exact
#>     postcode : exact
#>   Blocking rules (2, OR-ed):
#>     1. surname
#>     2. given_name
```

## Train the model

Create a link-type model with both tables:

``` r
model <- il_model(
  df_a, df_b,
  spec = spec,
  con = con,
  link_type = "link"
)

model
#> irelink Model
#>   Status: Untrained
#>   Link type: link
#>   Records: 1000
#>   Records (right): 1000
#>   Comparisons: 4
#>   Blocking rules: 2
```

Estimate prior match probability, u-probabilities, and run EM:

``` r
model <- il_estimate_prior(
  model,
  block_on(given_name, surname),
  block_on(surname, suburb),
  recall = 0.6
)

model <- il_estimate_u(model, max_pairs = 1e5)
model <- il_estimate_em(model, block_on(surname))
model <- il_estimate_em(model, block_on(suburb))
```

## Inspect the model

``` r
autoplot(model)
```

![](record-linkage_files/figure-html/weights-1.png)

``` r
autoplot(model, type = "parameters")
```

![](record-linkage_files/figure-html/params-1.png)

``` r
il_weights(model)
#> # A tibble: 8 × 5
#>   comparison    level     m_prob  u_prob weight
#>   <chr>         <chr>      <dbl>   <dbl>  <dbl>
#> 1 given_name    match     0.604  0.00268   7.82
#> 2 given_name    non_match 0.396  0.997    -1.33
#> 3 surname       match     0.686  0.00325   7.72
#> 4 surname       non_match 0.314  0.997    -1.66
#> 5 date_of_birth match     0.923  0.00015  12.6 
#> 6 date_of_birth non_match 0.0773 1.000    -3.69
#> 7 postcode      match     0.869  0.00099   9.78
#> 8 postcode      non_match 0.131  0.999    -2.93
```

## Predict and cluster

``` r
predictions <- predict(model, threshold = 0.5)
nrow(predictions)
#> [1] 167
```

``` r
autoplot(predictions)
```

![](record-linkage_files/figure-html/hist-1.png)

Cluster the pairs to resolve entities:

``` r
clusters <- il_cluster(predictions, threshold = 0.85)
head(clusters)
#> # A tibble: 6 × 2
#>   unique_id cluster_id 
#>   <chr>     <chr>      
#> 1 185       cluster_185
#> 2 236       cluster_236
#> 3 419       cluster_330
#> 4 448       cluster_448
#> 5 517       cluster_517
#> 6 611       cluster_564
```

## Evaluate against ground truth

The `rec_id` column encodes ground truth. Extract entity IDs and build
pairwise labels:

``` r
# Extract entity number from rec_id (e.g., "rec-1070-org" -> "1070")
entity_a <- sub('^rec-(\\d+)-org$', '\\1', df_a$rec_id)
entity_b <- sub('^rec-(\\d+)-dup-\\d+$', '\\1', df_b$rec_id)

# Build id-entity lookup (unique_id auto-generated by il_model)
ids_a <- data.frame(unique_id = seq_len(nrow(df_a)), entity = entity_a)
ids_b <- data.frame(unique_id = seq_len(nrow(df_b)), entity = entity_b)

# True matches: same entity across tables
positives <- merge(ids_a, ids_b, by = 'entity')
names(positives) <- c('entity', 'unique_id_l', 'unique_id_r')
positives$is_match <- 1L
positives <- positives[, c('unique_id_l', 'unique_id_r', 'is_match')]

# Sample non-matching pairs
set.seed(42)
n_neg <- min(nrow(positives), 2000L)
neg_l <- sample(ids_a$unique_id, n_neg, replace = TRUE)
neg_r <- sample(ids_b$unique_id, n_neg, replace = TRUE)
ent_l <- ids_a$entity[match(neg_l, ids_a$unique_id)]
ent_r <- ids_b$entity[match(neg_r, ids_b$unique_id)]
negatives <- data.frame(
  unique_id_l = neg_l,
  unique_id_r = neg_r,
  is_match = ifelse(ent_l == ent_r, 1L, 0L)
)

labels <- rbind(positives, negatives)
nrow(labels)
#> [1] 384
sum(labels$is_match)
#> [1] 192
```

### Accuracy metrics

``` r
acc <- il_accuracy(model, labels = labels)
autoplot(acc)
```

![](record-linkage_files/figure-html/accuracy-1.png)

### ROC and Precision–Recall

``` r
roc <- il_roc(model, labels = labels)
autoplot(roc)
```

![](record-linkage_files/figure-html/roc-1.png)

``` r
pr <- il_precision_recall(model, labels = labels)
autoplot(pr)
```

![](record-linkage_files/figure-html/pr-1.png)

## Cleanup

``` r
il_cleanup(model)
DBI::dbDisconnect(con, shutdown = TRUE)
```
