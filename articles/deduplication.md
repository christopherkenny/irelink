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
#>      comparisons:  1 first_name match     0.408  0.00669
#>      comparisons:  2 first_name non_match 0.592  0.993  
#>      comparisons:  3 surname    match     0.472  0.00949
#>      comparisons:  4 surname    non_match 0.528  0.991  
#>      comparisons:  5 dob        match     0.99   0.00856
#>      comparisons:  6 dob        non_match 0.0100 0.991  
#>      comparisons:  7 city       match     0.567  0.0764 
#>      comparisons:  8 city       non_match 0.433  0.924  
#>      comparisons:  9 email      match     0.647  0.00773
#>      comparisons: 10 email      non_match 0.353  0.992  
#>     history: 1                , 1                , 1                , 1                , 1                , 1                , 1                , 1                , 1                , 1                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.68926263815444 , 0.703056977442832, 0.575766850637893, 0.635623146458139
#>      history: 1                , 1                , 1                , 1                , 1                , 2                , 2                , 2                , 2                , 2                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.603537896321714, 0.614863974870554, 0.504044511789673, 0.538707186096697
#>      history: 1                , 1                , 1                , 1                , 1                , 3                , 3                , 3                , 3                , 3                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.571749007744947, 0.581633656283793, 0.4941673716006  , 0.508933973783332
#>      history: 1                , 1                , 1                , 1                , 1                , 4                , 4                , 4                , 4                , 4                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.559903394966087, 0.5694176832875  , 0.491058108165683, 0.498258398789928
#>      history: 1                , 1                , 1                , 1                , 1                , 5                , 5                , 5                , 5                , 5                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.555498635631726, 0.564891954193267, 0.489798914373652, 0.494306880168201
#>      history: 1                , 1                , 1                , 1                , 1                , 6                , 6                , 6                , 6                , 6                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.553854559183795, 0.56320421312323 , 0.48929438987065 , 0.492832665558815
#>      history: 1                , 1                , 1                , 1                , 1                , 7                , 7                , 7                , 7                , 7                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.55323920174495 , 0.562572655993588, 0.489098461981755, 0.492280869566536
#>      history: 1                , 1                , 1                , 1                , 1                , 8                , 8                , 8                , 8                , 8                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.553008555753462, 0.562335952867173, 0.48902377999121 , 0.49207403540901 
#>      history: 1                , 1                , 1                , 1                , 1                , 9                , 9                , 9                , 9                , 9                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.55292205118662 , 0.562247178117558, 0.488995567791954, 0.491996458837902
#>      history: 1                , 1                , 1                , 1                , 1                , 10               , 10               , 10               , 10               , 10               , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.552889598705073, 0.562213874136656, 0.488984952399495, 0.491967355230581
#>      history: 1                , 1                , 1                , 1                , 1                , 11               , 11               , 11               , 11               , 11               , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.55287742272656 , 0.562201378698497, 0.488980964806168, 0.491956435647993
#>      history: 1                , 1                , 1                , 1                , 1                , 12               , 12               , 12               , 12               , 12               , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.99             , 0.55287285417468 , 0.562196690283978, 0.488979467914069, 0.491952338495859
#>      history: 13               , 13               , 13               , 13               , 13               , 1                , 1                , 1                , 1                , 1                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.620697628683481, 0.611736452964111, 0.99             , 0.579113290849981, 0.659399902466862
#>      history: 13               , 13               , 13               , 13               , 13               , 2                , 2                , 2                , 2                , 2                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.426869836327769, 0.491491796264957, 0.99             , 0.563937877258735, 0.663650498487993
#>      history: 13               , 13               , 13               , 13               , 13               , 3                , 3                , 3                , 3                , 3                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.410265287821215, 0.474878843747084, 0.99             , 0.565829543225574, 0.650695374151982
#>      history: 13               , 13               , 13               , 13               , 13               , 4                , 4                , 4                , 4                , 4                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.408331696372355, 0.47262238598396 , 0.99             , 0.566824299854366, 0.647756295167109
#>      history: 13               , 13               , 13               , 13               , 13               , 5                , 5                , 5                , 5                , 5                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.408031259498782, 0.472260340649369, 0.99             , 0.567036769431588, 0.647221303759581
#>      history: 13               , 13               , 13               , 13               , 13               , 6                , 6                , 6                , 6                , 6                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.407980355471682, 0.472198791192402, 0.99             , 0.567076051221645, 0.64712756047442 
#>      history: 13               , 13               , 13               , 13               , 13               , 7                , 7                , 7                , 7                , 7                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.407971553768551, 0.472188153620343, 0.99             , 0.567083021265976, 0.647111243414218
#>      history: 13               , 13               , 13               , 13               , 13               , 8                , 8                , 8                , 8                , 8                , first_name       , surname          , dob              , city             , email            , match            , match            , match            , match            , match            , 0.407970024991456, 0.472186306812227, 0.99             , 0.567084241707144, 0.64710840590408
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
#> 1 35        cluster_32 
#> 2 622       cluster_622
#> 3 882       cluster_879
#> 4 413       cluster_413
#> 5 415       cluster_413
#> 6 762       cluster_760
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
#>  2 0.00000397  2031  1145     0     0     0.639  1     0.780
#>  3 0.0000629   1351   241   680   904     0.849  0.665 0.746
#>  4 0.000370    1239    49   792  1096     0.962  0.610 0.747
#>  5 0.000406    1228    48   803  1097     0.962  0.605 0.743
#>  6 0.000933    1206    46   825  1099     0.963  0.594 0.735
#>  7 0.00584     1154    45   877  1100     0.962  0.568 0.715
#>  8 0.00639     1136    37   895  1108     0.968  0.559 0.709
#>  9 0.0146      1116    37   915  1108     0.968  0.549 0.701
#> 10 0.0365      1020    35  1011  1110     0.967  0.502 0.661
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
#> 1           0           1         7.67            0.602  TRUE       false_negat…
#> 2           0           2         7.67            0.602  TRUE       false_negat…
#> 3           0           3         9.29            0.823  TRUE       false_negat…
#> 4           1           3         2.35            0.0365 TRUE       false_negat…
#> 5           2           3         2.35            0.0365 TRUE       false_negat…
#> 6           4           6        10.5             0.915  FALSE      false_posit…
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
