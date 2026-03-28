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
#>      comparisons:  1 first_name match     0.407  0.00654
#>      comparisons:  2 first_name non_match 0.593  0.993  
#>      comparisons:  3 surname    match     0.472  0.0092 
#>      comparisons:  4 surname    non_match 0.528  0.991  
#>      comparisons:  5 dob        match     0.99   0.00842
#>      comparisons:  6 dob        non_match 0.0100 0.992  
#>      comparisons:  7 city       match     0.567  0.0759 
#>      comparisons:  8 city       non_match 0.433  0.924  
#>      comparisons:  9 email      match     0.646  0.00773
#>      comparisons: 10 email      non_match 0.354  0.992  
#>     history: 1                , 1                , 1                , 1                , 1                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.68889845619071 , 0.702481153757714, 0.575479172084747, 0.634823573987985
#>      history: 2                , 2                , 2                , 2                , 2                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.602447965055443, 0.613487505020557, 0.503655906324776, 0.537298501457858
#>      history: 3                , 3                , 3                , 3                , 3                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.570044993122136, 0.579719809626769, 0.493739591975609, 0.507134552700801
#>      history: 4                , 4                , 4                , 4                , 4                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.557885563555695, 0.567206106657695, 0.490509226537416, 0.496211178767374
#>      history: 5                , 5                , 5                , 5                , 5                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.553328499304437, 0.562531447179625, 0.48917233687889 , 0.492132795622722
#>      history: 6                , 6                , 6                , 6                , 6                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.551613150627752, 0.560773170836725, 0.488629563642141, 0.490598063898659
#>      history: 7                , 7                , 7                , 7                , 7                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.55096548521238 , 0.560109427614213, 0.488416574565131, 0.490018551481105
#>      history: 8                , 8                , 8                , 8                , 8                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.550720568312696, 0.559858444559436, 0.488334613806496, 0.489799391586174
#>      history: 9                , 9                , 9                , 9                , 9                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.550627888277821, 0.559763470502025, 0.488303366354191, 0.489716455216069
#>      history: 10               , 10               , 10               , 10               , 10               , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.550592806638181, 0.559727520685096, 0.48829150193994 , 0.489685061232273
#>      history: 11               , 11               , 11               , 11               , 11               , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.550579525812923, 0.55971391121326 , 0.488287004857125, 0.489673176348014
#>      history: 12               , 12               , 12               , 12               , 12               , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.550574497864749, 0.559708758845839, 0.488285301481281, 0.48966867687057 
#>      history: 1                , 1                , 1                , 1                , 1                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.619098344152552, 0.611352662958895, 0.99             , 0.579500261178656, 0.658864254073922
#>      history: 2                , 2                , 2                , 2                , 2                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.426244139066069, 0.490908763059081, 0.99             , 0.563763466845131, 0.662657077823628
#>      history: 3                , 3                , 3                , 3                , 3                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.409764008078176, 0.474310688108708, 0.99             , 0.565772532580046, 0.649583651369127
#>      history: 4                , 4                , 4                , 4                , 4                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.407831203783658, 0.472051136216501, 0.99             , 0.566784429932555, 0.646638583569403
#>      history: 5                , 5                , 5                , 5                , 5                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.407529940639882, 0.471688318440617, 0.99             , 0.566999073664444, 0.646104430593675
#>      history: 6                , 6                , 6                , 6                , 6                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.407478912630428, 0.471626689972709, 0.99             , 0.567038617176818, 0.64601105414223 
#>      history: 7                , 7                , 7                , 7                , 7                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.407470102312644, 0.471616054892847, 0.99             , 0.567045615911348, 0.645994832702358
#>      history: 8                , 8                , 8                , 8                , 8                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.407468574714597, 0.471614211724967, 0.99             , 0.567046838766548, 0.645992017044796
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
#> 1 33        cluster_1 
#> 2 39        cluster_2 
#> 3 44        cluster_3 
#> 4 45        cluster_3 
#> 5 46        cluster_3 
#> 6 51        cluster_4
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
