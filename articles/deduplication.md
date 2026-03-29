# Deduplication with Evaluation

This vignette walks through a complete deduplication workflow on the
`fake_1000` dataset, including model training, prediction, clustering,
and evaluation against ground-truth labels. The dataset is the primary
demo data from the Python
[splink](https://github.com/moj-analytical-services/splink) library. It
contains 1,000 records representing 181 unique people, each with varying
numbers of duplicate entries corrupted with typos, missing values, and
other realistic data-quality issues.

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

## Explore the data

``` r
df <- fake_1000
head(df)
#> # A tibble: 6 × 7
#>   unique_id first_name surname dob        city   email                   cluster
#>       <int> <chr>      <chr>   <chr>      <chr>  <chr>                     <int>
#> 1         0 Julia      NA      2015-10-29 London hannah88@powers.com           0
#> 2         1 Julia      Taylor  2015-07-31 London hannah88@powers.com           0
#> 3         2 Julia      Taylor  2016-01-27 London hannah88@powers.com           0
#> 4         3 Julia      Taylor  2015-10-29 NA     hannah88opowersc@m            0
#> 5         4 oNah       Watson  2008-03-23 Bolton matthew78@ballard-mcdo…       1
#> 6         5 Noah       Watson  2008-03-23 Bolton matthew78@ballard-mcdo…       1
```

The `cluster` column is the ground truth: records sharing the same
cluster value refer to the same person. There are 181 unique entities
across 1000 records. Note that missing values appear as `NA`, reflecting
real-world data-quality challenges.

Before building a model, profile the data to understand its completeness
and value distributions:

``` r
con <- DBI::dbConnect(duckdb::duckdb())
comp <- il_completeness(df, con = con)
comp
#> # A tibble: 7 × 5
#>   table   column     n_total n_non_null pct_non_null
#>   <chr>   <chr>        <int>      <int>        <dbl>
#> 1 table_1 unique_id     1000       1000        100  
#> 2 table_1 first_name    1000        900         90  
#> 3 table_1 surname       1000        923         92.3
#> 4 table_1 dob           1000       1000        100  
#> 5 table_1 city          1000        891         89.1
#> 6 table_1 email         1000        888         88.8
#> 7 table_1 cluster       1000       1000        100
```

``` r
autoplot(comp)
```

![](deduplication_files/figure-html/completeness-plot-1.png)

Check column value distributions to inform blocking and comparison
choices:

``` r
il_profile(df[, c("first_name", "surname", "city")], con = con, top_n = 5)
#> # A tibble: 15 × 3
#>    column     value          n
#>    <chr>      <chr>      <dbl>
#>  1 first_name NA           100
#>  2 first_name George        22
#>  3 first_name Harry         18
#>  4 first_name Ivy           18
#>  5 first_name Noah          17
#>  6 surname    NA            77
#>  7 surname    Taylor        41
#>  8 surname    Jones         30
#>  9 surname    Brown         26
#> 10 surname    Thomas        18
#> 11 city       London       257
#> 12 city       NA           109
#> 13 city       Birmingham    36
#> 14 city       Leeds         33
#> 15 city       Sheffield     31
```

## Define the specification

Choose comparisons and blocking rules. Names use Jaro-Winkler
similarity, dates of birth use the
[`cl_dob()`](http://christophertkenny.com/irelink/reference/cl_dob.md)
helper, and city uses exact matching with term-frequency adjustments:

``` r
spec <- il_spec() |>
  il_compare(first_name, cl_name()) |>
  il_compare(surname, cl_name()) |>
  il_compare(dob, cl_dob()) |>
  il_compare(city, cl_exact(term_frequency = TRUE)) |>
  il_compare(email, cl_email()) |>
  il_block_on(first_name) |>
  il_block_on(surname) |>
  il_block_on(city)

spec
#> Linkage Specification
#>   Comparisons (5):
#>     first_name : levels
#>     surname : levels
#>     dob : levels
#>     city : exact
#>     email : levels
#>   Blocking rules (3, OR-ed):
#>     1. first_name
#>     2. surname
#>     3. city
```

Estimate how many pairs each blocking rule generates:

``` r
il_count_pairs(
  df,
  block_on(first_name),
  block_on(surname),
  block_on(city),
  con = con
)
#> # A tibble: 3 × 4
#>   rule       n_pairs cumulative_pairs pct_of_cartesian
#>   <chr>        <int>            <int>            <dbl>
#> 1 first_name    2372             2372            0.475
#> 2 surname       3278             5042            1.01 
#> 3 city         36905            40793            8.17
```

## Train the model

``` r
model <- il_model(df, spec = spec, con = con)
```

Estimate the prior match probability using deterministic rules:

``` r
model <- il_estimate_prior(
  model,
  block_on(first_name, surname),
  block_on(email),
  recall = 0.6
)
```

Estimate u-probabilities from random pairs and m-probabilities via EM:

``` r
model <- il_estimate_u(model, max_pairs = 1e5)
model <- il_estimate_em(model, block_on(first_name))
model <- il_estimate_em(model, block_on(dob))
```

## Inspect the trained model

``` r
summary(model)
#> irelink Model
#>   Status: Trained
#>   Link type: dedupe
#>   Records: 1000
#>   Comparisons: 5
#>   Blocking rules: 3
#> 
#>   Parameters:
#>     prior: 0.007377377
#>     comparisons: # A tibble: 10 × 4
#>      comparisons:    comparison level          m       u
#>      comparisons:    <chr>      <chr>      <dbl>   <dbl>
#>      comparisons:  1 first_name match     0.407  0.00656
#>      comparisons:  2 first_name non_match 0.593  0.993  
#>      comparisons:  3 surname    match     0.471  0.00896
#>      comparisons:  4 surname    non_match 0.529  0.991  
#>      comparisons:  5 dob        match     0.99   0.0083 
#>      comparisons:  6 dob        non_match 0.0100 0.992  
#>      comparisons:  7 city       match     0.567  0.0761 
#>      comparisons:  8 city       non_match 0.433  0.924  
#>      comparisons:  9 email      match     0.645  0.00757
#>      comparisons: 10 email      non_match 0.355  0.992  
#>     history: 1                , 1                , 1                , 1                , 1                , 1                , 1                , 1                , 1                , 1                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.688794563934857, 0.702204346896972, 0.575285399556329, 0.63461233565817 
#>      history: 1                , 1                , 1                , 1                , 1                , 2                , 2                , 2                , 2                , 2                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.60249565059373 , 0.613358050025908, 0.503340744398104, 0.537224867041708
#>      history: 1                , 1                , 1                , 1                , 1                , 3                , 3                , 3                , 3                , 3                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.570223473028713, 0.579785048787886, 0.493516919724104, 0.507220945769267
#>      history: 1                , 1                , 1                , 1                , 1                , 4                , 4                , 4                , 4                , 4                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.558148022379478, 0.567371171933823, 0.490335655126447, 0.496380646441316
#>      history: 1                , 1                , 1                , 1                , 1                , 5                , 5                , 5                , 5                , 5                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.553633446960775, 0.562744036025565, 0.489023257469352, 0.492342459896648
#>      history: 1                , 1                , 1                , 1                , 1                , 6                , 6                , 6                , 6                , 6                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.551938055494514, 0.561007594187449, 0.488491807213626, 0.490826350359095
#>      history: 1                , 1                , 1                , 1                , 1                , 7                , 7                , 7                , 7                , 7                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.551299418885021, 0.560353613105766, 0.488283776180028, 0.490255202383101
#>      history: 1                , 1                , 1                , 1                , 1                , 8                , 8                , 8                , 8                , 8                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.551058482682045, 0.560106900444557, 0.488203917327052, 0.490039712294152
#>      history: 1                , 1                , 1                , 1                , 1                , 9                , 9                , 9                , 9                , 9                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.550967523602667, 0.560013761980509, 0.488173544201617, 0.489958356661055
#>      history: 1                , 1                , 1                , 1                , 1                , 10               , 10               , 10               , 10               , 10               , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.550933174580213, 0.559978590104912, 0.488162039218918, 0.4899276336672  
#>      history: 1                , 1                , 1                , 1                , 1                , 11               , 11               , 11               , 11               , 11               , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.550920201793702, 0.55996530656383 , 0.488157688716879, 0.489916030255593
#>      history: 1                , 1                , 1                , 1                , 1                , 12               , 12               , 12               , 12               , 12               , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.55091530206207 , 0.559960289464262, 0.488156044761826, 0.489911647713682
#>      history: 13               , 13               , 13               , 13               , 13               , 1                , 1                , 1                , 1                , 1                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.616583095047707, 0.610294863920806, 0.99             , 0.580077196646517, 0.659169511439044
#>      history: 13               , 13               , 13               , 13               , 13               , 2                , 2                , 2                , 2                , 2                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.425414546180922, 0.490269243560779, 0.99             , 0.563382263232613, 0.662206034074495
#>      history: 13               , 13               , 13               , 13               , 13               , 3                , 3                , 3                , 3                , 3                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.409237599961505, 0.473908472934097, 0.99             , 0.565548491841021, 0.649039534644306
#>      history: 13               , 13               , 13               , 13               , 13               , 4                , 4                , 4                , 4                , 4                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.407328528720447, 0.471669527376766, 0.99             , 0.566572884779454, 0.646101605995718
#>      history: 13               , 13               , 13               , 13               , 13               , 5                , 5                , 5                , 5                , 5                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.407029631721722, 0.471308673453163, 0.99             , 0.566787749022802, 0.645570690558412
#>      history: 13               , 13               , 13               , 13               , 13               , 6                , 6                , 6                , 6                , 6                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.406978955387948, 0.471247327738196, 0.99             , 0.566827149683675, 0.645478046546681
#>      history: 13               , 13               , 13               , 13               , 13               , 7                , 7                , 7                , 7                , 7                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.406970209646018, 0.471236746086705, 0.99             , 0.566834106129341, 0.645461972292352
#>      history: 13               , 13               , 13               , 13               , 13               , 8                , 8                , 8                , 8                , 8                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.406968694583198, 0.471234913770447, 0.99             , 0.566835319656933, 0.64545918524119
```

The match weights chart shows the discriminative power of each
comparison:

``` r
autoplot(model)
```

![](deduplication_files/figure-html/weights-plot-1.png)

The parameter chart shows the raw m and u probabilities:

``` r
autoplot(model, type = "parameters")
```

![](deduplication_files/figure-html/params-plot-1.png)

## Predict and cluster

Score all candidate pairs and apply a probability threshold:

``` r
predictions <- predict(model, threshold = 0.5)
nrow(predictions)
#> [1] 1601
```

View the match-weight distribution:

``` r
autoplot(predictions)
```

![](deduplication_files/figure-html/histogram-1.png)

Inspect how individual pairs are scored with a waterfall chart:

``` r
autoplot(predictions, which = 1)
```

![](deduplication_files/figure-html/waterfall-1.png)

Resolve pairwise links into entity clusters:

``` r
clusters <- il_cluster(predictions, threshold = 0.85)
head(clusters)
#> # A tibble: 6 × 2
#>   unique_id cluster_id 
#>   <chr>     <chr>      
#> 1 77        cluster_74 
#> 2 486       cluster_479
#> 3 862       cluster_861
#> 4 970       cluster_967
#> 5 41        cluster_38 
#> 6 225       cluster_220
```

## Evaluate against ground truth

The `cluster` column in the original data provides ground-truth entity
labels. Convert these to pairwise labels for evaluation:

``` r
# Use the bundled clerical labels from splink
labels_raw <- fake_1000_labels

# Rename to match irelink's evaluation convention
labels <- data.frame(
  unique_id_l = labels_raw$unique_id_l,
  unique_id_r = labels_raw$unique_id_r,
  is_match = as.integer(labels_raw$clerical_match_score)
)

nrow(labels)
#> [1] 3176
sum(labels$is_match)
#> [1] 2031
```

### Accuracy metrics

``` r
acc <- il_accuracy(model, labels = labels)
acc
#> # A tibble: 34 × 8
#>     threshold    tp    fp    fn    tn precision recall    f1
#>         <dbl> <int> <int> <int> <int>     <dbl>  <dbl> <dbl>
#>  1 0           2031  1145     0     0     0.639  1     0.780
#>  2 0.00000400  2031  1145     0     0     0.639  1     0.780
#>  3 0.0000635   1351   241   680   904     0.849  0.665 0.746
#>  4 0.000394    1239    49   792  1096     0.962  0.610 0.747
#>  5 0.000415    1228    48   803  1097     0.962  0.605 0.743
#>  6 0.000953    1206    46   825  1099     0.963  0.594 0.735
#>  7 0.00622     1154    45   877  1100     0.962  0.568 0.715
#>  8 0.00656     1136    37   895  1108     0.968  0.559 0.709
#>  9 0.0149      1116    37   915  1108     0.968  0.549 0.701
#> 10 0.0393      1020    35  1011  1110     0.967  0.502 0.661
#> # ℹ 24 more rows
```

``` r
autoplot(acc)
```

![](deduplication_files/figure-html/accuracy-plot-1.png)

### ROC curve

``` r
roc <- il_roc(model, labels = labels)
autoplot(roc)
```

![](deduplication_files/figure-html/roc-1.png)

### Precision–recall curve

``` r
pr <- il_precision_recall(model, labels = labels)
autoplot(pr)
```

![](deduplication_files/figure-html/pr-1.png)

### Error inspection

Examine false positives and false negatives at a specific threshold:

``` r
errors <- il_errors(model, labels = labels, threshold = 0.85)
head(errors)
#> # A tibble: 6 × 6
#>   unique_id_l unique_id_r match_weight match_probability true_label error_type  
#>         <int>       <int>        <dbl>             <dbl> <lgl>      <chr>       
#> 1           0           1         7.73            0.612  TRUE       false_negat…
#> 2           0           2         7.73            0.612  TRUE       false_negat…
#> 3           0           3         9.37            0.831  TRUE       false_negat…
#> 4           1           3         2.46            0.0393 TRUE       false_negat…
#> 5           2           3         2.46            0.0393 TRUE       false_negat…
#> 6           4           6        10.6             0.919  FALSE      false_posit…
```

### Unlinkables

How many records cannot be linked at each threshold?

``` r
unlink <- il_unlinkables(model)
autoplot(unlink)
```

![](deduplication_files/figure-html/unlinkables-1.png)

## Cleanup

``` r
il_cleanup(model)
DBI::dbDisconnect(con, shutdown = TRUE)
```
