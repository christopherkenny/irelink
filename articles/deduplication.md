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
#>  3 first_name Ivy           18
#>  4 first_name Harry         18
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
#>      comparisons:  1 first_name match     0.407  0.00654
#>      comparisons:  2 first_name non_match 0.593  0.993  
#>      comparisons:  3 surname    match     0.472  0.0092 
#>      comparisons:  4 surname    non_match 0.528  0.991  
#>      comparisons:  5 dob        match     0.99   0.00841
#>      comparisons:  6 dob        non_match 0.0100 0.992  
#>      comparisons:  7 city       match     0.567  0.0758 
#>      comparisons:  8 city       non_match 0.433  0.924  
#>      comparisons:  9 email      match     0.646  0.00773
#>      comparisons: 10 email      non_match 0.354  0.992  
#>     history: 1                , 1                , 1                , 1                , 1                , 1                , 1                , 1                , 1                , 1                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.688878522021389, 0.702477529738747, 0.575486546866265, 0.634804808048251
#>      history: 1                , 1                , 1                , 1                , 1                , 2                , 2                , 2                , 2                , 2                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.602409626032722, 0.613462402835627, 0.503677901750663, 0.537264934811617
#>      history: 1                , 1                , 1                , 1                , 1                , 3                , 3                , 3                , 3                , 3                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.570000424194529, 0.579683501243358, 0.493769861472126, 0.50709540389842 
#>      history: 1                , 1                , 1                , 1                , 1                , 4                , 4                , 4                , 4                , 4                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.557839350085637, 0.567167112075256, 0.490541138950979, 0.496170524165817
#>      history: 1                , 1                , 1                , 1                , 1                , 5                , 5                , 5                , 5                , 5                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.553282185742943, 0.562492050880478, 0.489204548302825, 0.492092036552799
#>      history: 1                , 1                , 1                , 1                , 1                , 6                , 6                , 6                , 6                , 6                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.551567018309377, 0.560733853439244, 0.488661867646175, 0.490557460443103
#>      history: 1                , 1                , 1                , 1                , 1                , 7                , 7                , 7                , 7                , 7                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.550919505818044, 0.560070226997226, 0.488448927021914, 0.489978082157253
#>      history: 1                , 1                , 1                , 1                , 1                , 8                , 8                , 8                , 8                , 8                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.550674678813829, 0.559819320983681, 0.488366993248377, 0.489759001638451
#>      history: 1                , 1                , 1                , 1                , 1                , 9                , 9                , 9                , 9                , 9                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.550582044935535, 0.559724388518247, 0.488335759821946, 0.489676106161701
#>      history: 1                , 1                , 1                , 1                , 1                , 10               , 10               , 10               , 10               , 10               , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.550546985361606, 0.559688459152525, 0.488323902235605, 0.489644731767507
#>      history: 1                , 1                , 1                , 1                , 1                , 11               , 11               , 11               , 11               , 11               , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.550533714628765, 0.559674859204902, 0.488319408322427, 0.489632855855379
#>      history: 1                , 1                , 1                , 1                , 1                , 12               , 12               , 12               , 12               , 12               , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.550528691159736, 0.559669711117815, 0.488317706369171, 0.48962836036375 
#>      history: 13               , 13               , 13               , 13               , 13               , 1                , 1                , 1                , 1                , 1                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.618942533225895, 0.611259022635203, 0.99             , 0.579581879404491, 0.658880266060669
#>      history: 13               , 13               , 13               , 13               , 13               , 2                , 2                , 2                , 2                , 2                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.426180669990362, 0.490839128394235, 0.99             , 0.563786993127874, 0.662584852370534
#>      history: 13               , 13               , 13               , 13               , 13               , 3                , 3                , 3                , 3                , 3                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.409707881711122, 0.474244346735785, 0.99             , 0.565805921507397, 0.649493982933095
#>      history: 13               , 13               , 13               , 13               , 13               , 4                , 4                , 4                , 4                , 4                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.407774598882664, 0.471984132285118, 0.99             , 0.566819259275584, 0.646546814750525
#>      history: 13               , 13               , 13               , 13               , 13               , 5                , 5                , 5                , 5                , 5                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.407473160633662, 0.471621124863297, 0.99             , 0.567034103781592, 0.646012387017813
#>      history: 13               , 13               , 13               , 13               , 13               , 6                , 6                , 6                , 6                , 6                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.40742209941201 , 0.47155946113311 , 0.99             , 0.567073677032444, 0.645918970745979
#>      history: 13               , 13               , 13               , 13               , 13               , 7                , 7                , 7                , 7                , 7                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.407413283496477, 0.471548820142922, 0.99             , 0.567080680363175, 0.645902743300998
#>      history: 13               , 13               , 13               , 13               , 13               , 8                , 8                , 8                , 8                , 8                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.407411754986224, 0.47154697601897 , 0.99             , 0.567081903942889, 0.645899926736146
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
#> 1 915       cluster_911
#> 2 299       cluster_296
#> 3 40        cluster_38 
#> 4 824       cluster_823
#> 5 842       cluster_838
#> 6 540       cluster_536
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
#>  2 0.00000399  2031  1145     0     0     0.639  1     0.780
#>  3 0.0000636   1351   241   680   904     0.849  0.665 0.746
#>  4 0.000383    1239    49   792  1096     0.962  0.610 0.747
#>  5 0.000416    1228    48   803  1097     0.962  0.605 0.743
#>  6 0.000932    1206    46   825  1099     0.963  0.594 0.735
#>  7 0.00608     1154    45   877  1100     0.962  0.568 0.715
#>  8 0.00660     1136    37   895  1108     0.968  0.559 0.709
#>  9 0.0147      1116    37   915  1108     0.968  0.549 0.701
#> 10 0.0385      1020    35  1011  1110     0.967  0.502 0.661
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
#> 1           0           1         7.71            0.609  TRUE       false_negat…
#> 2           0           2         7.71            0.609  TRUE       false_negat…
#> 3           0           3         9.35            0.829  TRUE       false_negat…
#> 4           1           3         2.43            0.0385 TRUE       false_negat…
#> 5           2           3         2.43            0.0385 TRUE       false_negat…
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
