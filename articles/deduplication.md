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
#>      comparisons:  1 first_name match     0.408  0.00657
#>      comparisons:  2 first_name non_match 0.592  0.993  
#>      comparisons:  3 surname    match     0.472  0.00902
#>      comparisons:  4 surname    non_match 0.528  0.991  
#>      comparisons:  5 dob        match     0.99   0.00856
#>      comparisons:  6 dob        non_match 0.0100 0.991  
#>      comparisons:  7 city       match     0.567  0.0753 
#>      comparisons:  8 city       non_match 0.433  0.925  
#>      comparisons:  9 email      match     0.646  0.00761
#>      comparisons: 10 email      non_match 0.354  0.992  
#>     history: 1                , 1                , 1                , 1                , 1                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.689051453711433, 0.702118735655665, 0.575538831338967, 0.63489012692642 
#>      history: 2                , 2                , 2                , 2                , 2                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.60260599748597 , 0.613197219895613, 0.503777374534803, 0.537361672545146
#>      history: 3                , 3                , 3                , 3                , 3                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.570217871033046, 0.579602496356788, 0.493947793175027, 0.507240434577147
#>      history: 4                , 4                , 4                , 4                , 4                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.558106566411642, 0.567171977634352, 0.490763208873557, 0.496365910239126
#>      history: 5                , 5                , 5                , 5                , 5                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.553581638535472, 0.56254021344923 , 0.489448670309911, 0.492317834453596
#>      history: 6                , 6                , 6                , 6                , 6                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.551883547060304, 0.560803118272525, 0.488916339527038, 0.490799077606472
#>      history: 7                , 7                , 7                , 7                , 7                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.551244347209636, 0.5601493431239  , 0.488708038780623, 0.490227337265931
#>      history: 8                , 8                , 8                , 8                , 8                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.551003370294822, 0.559902882651446, 0.488628120704665, 0.490011777036992
#>      history: 9                , 9                , 9                , 9                , 9                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.55091246070301 , 0.5598099056089  , 0.488597744643816, 0.489930452878842
#>      history: 10               , 10               , 10               , 10               , 10               , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.55087815484537 , 0.559774819713062, 0.488586246423971, 0.489899763656127
#>      history: 11               , 11               , 11               , 11               , 11               , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.550865207598578, 0.559761578090838, 0.488581901528791, 0.489888181260917
#>      history: 12               , 12               , 12               , 12               , 12               , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.550860320999462, 0.559756580389254, 0.488580260855457, 0.489883809775316
#>      history: 1                , 1                , 1                , 1                , 1                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.618503890921601, 0.611341229314538, 0.99             , 0.579848898771919, 0.659006928165866
#>      history: 2                , 2                , 2                , 2                , 2                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.426234473057252, 0.491137923664342, 0.99             , 0.563800060948339, 0.662925057183104
#>      history: 3                , 3                , 3                , 3                , 3                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.409845348609391, 0.474630956677771, 0.99             , 0.565769348641529, 0.649978328061053
#>      history: 4                , 4                , 4                , 4                , 4                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.407931497813713, 0.472388327205912, 0.99             , 0.566772929716708, 0.647059383781167
#>      history: 5                , 5                , 5                , 5                , 5                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.407633821072473, 0.472028553040464, 0.99             , 0.566985859055401, 0.646529918779534
#>      history: 6                , 6                , 6                , 6                , 6                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.407583437470853, 0.471967470910739, 0.99             , 0.567025075191849, 0.646437377590322
#>      history: 7                , 7                , 7                , 7                , 7                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.407574741521453, 0.471956933748104, 0.99             , 0.567032013806054, 0.646421305367976
#>      history: 8                , 8                , 8                , 8                , 8                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.407573234184949, 0.471955108103936, 0.99             , 0.567033225796025, 0.646418516389244
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
#> 1 0         cluster_1 
#> 2 35        cluster_2 
#> 3 38        cluster_3 
#> 4 41        cluster_3 
#> 5 52        cluster_4 
#> 6 53        cluster_4
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
#> # A tibble: 21 × 8
#>    threshold    tp    fp    fn    tn precision recall    f1
#>        <dbl> <int> <int> <int> <int>     <dbl>  <dbl> <dbl>
#>  1      0     2031  1145     0     0     0.639  1     0.780
#>  2      0.05   916    24  1115  1121     0.974  0.451 0.617
#>  3      0.1    878    23  1153  1122     0.974  0.432 0.599
#>  4      0.15   878    23  1153  1122     0.974  0.432 0.599
#>  5      0.2    878    23  1153  1122     0.974  0.432 0.599
#>  6      0.25   878    23  1153  1122     0.974  0.432 0.599
#>  7      0.3    878    23  1153  1122     0.974  0.432 0.599
#>  8      0.35   878    23  1153  1122     0.974  0.432 0.599
#>  9      0.4    853    20  1178  1125     0.977  0.420 0.587
#> 10      0.45   755    15  1276  1130     0.981  0.372 0.539
#> # ℹ 11 more rows
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
#> 1           0           1         7.74            0.613  TRUE       false_negat…
#> 2           0           2         7.74            0.613  TRUE       false_negat…
#> 3           0           3         9.32            0.826  TRUE       false_negat…
#> 4           1           3         2.45            0.0390 TRUE       false_negat…
#> 5           2           3         2.45            0.0390 TRUE       false_negat…
#> 6           4           6        10.5             0.916  FALSE      false_posit…
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
