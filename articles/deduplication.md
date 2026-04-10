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
il_profile(df[, c('first_name', 'surname', 'city')], con = con, top_n = 5)
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

## Choose blocking rules

[`il_suggest_blocking()`](http://christophertkenny.com/irelink/reference/il_suggest_blocking.md)
enumerates columns and ranks them as blocking keys. A good blocking key
has high `n_distinct` (narrow blocks, fewer pairs) and high `coverage`
(few missing values):

``` r
il_suggest_blocking(df, con = con)
#> # A tibble: 6 × 6
#>   rule       n_distinct coverage n_pairs pct_of_cartesian score
#>   <chr>           <int>    <dbl>   <int>            <dbl> <dbl>
#> 1 dob               394    1        1850            0.370 0.996
#> 2 cluster           181    1        2975            0.596 0.994
#> 3 surname           317    0.923    3278            0.656 0.917
#> 4 first_name        326    0.9      2372            0.475 0.896
#> 5 email             336    0.888    1603            0.321 0.885
#> 6 city              174    0.891   36905            7.39  0.825
```

The spec below uses `first_name`, `surname`, and `city`, which rank
among the top columns here.

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
#>     comparisons: # A tibble: 23 × 4
#>      comparisons:    comparison gamma_level      m       u
#>      comparisons:    <chr>            <int>  <dbl>   <dbl>
#>      comparisons:  1 first_name           0 0.427  0.973  
#>      comparisons:  2 first_name           1 0.0941 0.0155 
#>      comparisons:  3 first_name           2 0.0246 0.00175
#>      comparisons:  4 first_name           3 0.0800 0.00277
#>      comparisons:  5 first_name           4 0.374  0.0066 
#>      comparisons:  6 surname              0 0.394  0.972  
#>      comparisons:  7 surname              1 0.0833 0.0143 
#>      comparisons:  8 surname              2 0.0248 0.00181
#>      comparisons:  9 surname              3 0.0644 0.00239
#>      comparisons: 10 surname              4 0.433  0.009  
#>      comparisons: # ℹ 13 more rows
#>     history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996443316414163, 0.000996443316414163, 0.000996443316414163, 0.000996443316414163, 0.996014226734343   , 0.148387942023087   , 0.0953117929668502  , 0.0492821500723642  , 0.0837337901645062  , 0.623284324773192   , 0.000998423361051632, 0.000998423361051632, 0.26050476919536    , 0.095921154035526   , 0.0204736414915559  , 0.621103588555454   , 0.481454868506995   , 0.518545131493005   , 0.140184868213704   , 0.000999108450884963, 0.242034114375948   , 0.0504316113292991  , 0.566350297630164   
#>      history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996403212733598, 0.000996403212733598, 0.000996403212733598, 0.000996403212733598, 0.996014387149066   , 0.188807917090314   , 0.0994770998927128  , 0.0477564808075785  , 0.0828336204211484  , 0.581124881788246   , 0.000998433919777757, 0.000998433919777757, 0.283546453582961   , 0.100627990277207   , 0.0240811972242742  , 0.589747491076002   , 0.510959672065702   , 0.489040327934298   , 0.195024002673552   , 0.000999098370957505, 0.232939847438266   , 0.0459046937799618  , 0.525132357737263   
#>      history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996398040645921, 0.000996398040645921, 0.000996398040645921, 0.000996398040645921, 0.996014407837416   , 0.19889185021004    , 0.0985883687141584  , 0.0471653928708093  , 0.0817934953119816  , 0.573560892893011   , 0.000998561492954045, 0.000998561492954045, 0.287648863435223   , 0.100201816464231   , 0.0250752148301712  , 0.585076982284466   , 0.515834675538102   , 0.484165324461898   , 0.20565812154891    , 0.000999097070926113, 0.229857782860116   , 0.0452922107014109  , 0.518192787818637   
#>      history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996396981136857, 0.000996396981136857, 0.000996396981136857, 0.000996396981136857, 0.996014412075453   , 0.201026866698489   , 0.0983615038550135  , 0.0470399645287451  , 0.0815738730739735  , 0.571997791843779   , 0.00099858687322573 , 0.00099858687322573 , 0.288634960787964   , 0.100068281395061   , 0.0253025630813851  , 0.583997020989138   , 0.516918793627841   , 0.483081206372159   , 0.207840814503695   , 0.000999096804611698, 0.229224789990316   , 0.0451667453499898  , 0.516768553351388   
#>      history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996396758140122, 0.000996396758140122, 0.000996396758140122, 0.000996396758140122, 0.99601441296744    , 0.201477542116527   , 0.0983128797054911  , 0.0470135007662142  , 0.0815275509119815  , 0.571668526499787   , 0.000998592123982704, 0.000998592123982704, 0.288851755641969   , 0.100038105117331   , 0.0253509594818409  , 0.583761995510894   , 0.517150980262298   , 0.482849019737702   , 0.208300330469781   , 0.000999096748559981, 0.229091531899939   , 0.0451403371015423  , 0.516468703780178   
#>      history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996396710973106, 0.000996396710973106, 0.000996396710973106, 0.000996396710973106, 0.996014413156108   , 0.201572903364958   , 0.0983025721467197  , 0.0470079016249631  , 0.0815177494886984  , 0.571598873374661   , 0.00099859323150276 , 0.00099859323150276 , 0.288898106984949   , 0.100031627247352   , 0.0253611659662928  , 0.5837119133384     , 0.517200267674059   , 0.482799732325941   , 0.208397530727199   , 0.000999096736704235, 0.229063344186994   , 0.0451347512996903  , 0.516405277049413   
#>      history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996396700987089, 0.000996396700987089, 0.000996396700987089, 0.000996396700987089, 0.996014413196052   , 0.201593094174141   , 0.098300389137268   , 0.0470067161478418  , 0.081515674183134   , 0.571584126357615   , 0.000998593465873819, 0.000998593465873819, 0.288907946954819   , 0.100030251505587   , 0.0253633211807124  , 0.583701293427134   , 0.517210710614457   , 0.482789289385543   , 0.208418109849613   , 0.000999096734194182, 0.229057376304077   , 0.0451335686917968  , 0.516391848420319   
#>      history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996396698872516, 0.000996396698872516, 0.000996396698872516, 0.000996396698872516, 0.99601441320451    , 0.20159736969073    , 0.0982999268560574  , 0.0470064651183     , 0.0815152347193347  , 0.571581003615578   , 0.000998593515499322, 0.000998593515499322, 0.288910032101319   , 0.10002996000119    , 0.0253637769708877  , 0.583699043895605   , 0.517212922313712   , 0.482787077686288   , 0.20842246755814    , 0.00099909673366267 , 0.229056112579971   , 0.0451333182704526  , 0.516389004857774   
#>      history: 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.149478615861667   , 0.111228944896065   , 0.0346620586532581  , 0.114445793119946   , 0.590184587469065   , 0.162865481973047   , 0.10227624874953    , 0.0361655458501288  , 0.0837937775934432  , 0.61489894583385    , 0.000995424546387192, 0.000995424546387192, 0.000995424546387192, 0.000995424546387192, 0.000995424546387192, 0.995022877268064   , 0.449721435271034   , 0.550278564728966   , 0.145574478740968   , 0.000999097658647697, 0.232071081933186   , 0.0455466425986496  , 0.575808699068549   
#>      history: 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.386096238279998   , 0.100360375121852   , 0.0264026061398806  , 0.0858088702913078  , 0.401331910166962   , 0.351981926430214   , 0.088777304632291   , 0.0265248767506576  , 0.0685259594035561  , 0.464189932783281   , 0.000995298331316335, 0.000995298331316335, 0.000995298331316335, 0.000995298331316335, 0.000995298331316335, 0.995023508343418   , 0.421659804820485   , 0.578340195179515   , 0.141150926327582   , 0.000999067140128897, 0.229363805040474   , 0.0425649920524698  , 0.585921209439346   
#>      history: 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.423771263795262   , 0.0946856790057909  , 0.024738763582836   , 0.0805031665003835  , 0.376301127115728   , 0.390329724360503   , 0.0838269422689075  , 0.0249322062061442  , 0.0647704593406035  , 0.436140667823842   , 0.000995280713482019, 0.000995280713482019, 0.000995280713482019, 0.000995280713482019, 0.000995280713482019, 0.99502359643259    , 0.441844802287814   , 0.558155197712186   , 0.14239522888861    , 0.000999062879709073, 0.227348347487916   , 0.0422841321658655  , 0.586973228577899   
#>      history: 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.426901823249152   , 0.0941502872809628  , 0.024591866527244   , 0.0800578102486787  , 0.374298212693963   , 0.393747858685557   , 0.0833356601863365  , 0.0247932069805729  , 0.0644221612581852  , 0.433701112889349   , 0.00099527917666378 , 0.00099527917666378 , 0.00099527917666378 , 0.00099527917666378 , 0.00099527917666378 , 0.995023604116681   , 0.44397978889481    , 0.55602021110519    , 0.143201745872694   , 0.000999062508063704, 0.226957404827376   , 0.0422335711653592  , 0.586608215626508   
#>      history: 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.427155657327199   , 0.0941089030822625  , 0.0245800361437564  , 0.0800204961121007  , 0.374134907334682   , 0.394032672412313   , 0.0832986914645654  , 0.0247825720193891  , 0.0643936529247507  , 0.433492411178982   , 0.000995279036682536, 0.000995279036682536, 0.000995279036682536, 0.000995279036682536, 0.000995279036682536, 0.995023604816587   , 0.444153766191097   , 0.555846233808903   , 0.143349673699104   , 0.000999062474212304, 0.226904340596891   , 0.042225622271998   , 0.586521300957795   
#>      history: 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.427177509947807   , 0.0941058777602747  , 0.0245790579630734  , 0.0800171263445996  , 0.374120427984245   , 0.394057461379767   , 0.0832962553570833  , 0.0247817583107202  , 0.0643912562125485  , 0.433473268739881   , 0.000995279022988659, 0.000995279022988659, 0.000995279022988659, 0.000995279022988659, 0.000995279022988659, 0.995023604885057   , 0.444167884055033   , 0.555832115944967   , 0.143371175537339   , 0.00099906247090074 , 0.226897580749809   , 0.0422245162303031  , 0.586507665011647   
#>      history: 9                  , 9                  , 9                  , 9                  , 9                  , 9                  , 9                  , 9                  , 9                  , 9                  , 9                  , 9                  , 9                  , 9                  , 9                  , 9                  , 9                  , 9                  , 9                  , 9                  , 9                  , 9                  , 9                  , 7                  , 7                  , 7                  , 7                  , 7                  , 7                  , 7                  , 7                  , 7                  , 7                  , 7                  , 7                  , 7                  , 7                  , 7                  , 7                  , 7                  , 7                  , 7                  , 7                  , 7                  , 7                  , 7                  , first_name         , first_name         , first_name         , first_name         , first_name         , surname            , surname            , surname            , surname            , surname            , dob                , dob                , dob                , dob                , dob                , dob                , city               , city               , email              , email              , email              , email              , email              , 0                  , 1                  , 2                  , 3                  , 4                  , 0                  , 1                  , 2                  , 3                  , 4                  , 0                  , 1                  , 2                  , 3                  , 4                  , 5                  , 0                  , 1                  , 0                  , 1                  , 2                  , 3                  , 4                  , 0.427179519338723  , 0.0941056617213442 , 0.0245789726750338 , 0.080016799841137  , 0.374119046423762  , 0.394059752430941  , 0.0832961192510846 , 0.0247816943704357 , 0.0643910433076208 , 0.433471390639918  , 0.00099527902156546, 0.00099527902156546, 0.00099527902156546, 0.00099527902156546, 0.00099527902156546, 0.995023604892173  , 0.444169072791258  , 0.555830927208742  , 0.143374040320615  , 0.00099906247055657, 0.226896738652579  , 0.0422243715270723 , 0.586505787029177
```

The match weights chart shows the discriminative power of each
comparison:

``` r
autoplot(model)
```

![](deduplication_files/figure-html/weights-plot-1.png)

The parameter chart shows the raw m and u probabilities:

``` r
autoplot(model, type = 'parameters')
```

![](deduplication_files/figure-html/params-plot-1.png)

## Save and reuse the model

Once you are satisfied with the parameters, save the model to a JSON
file. The file stores the spec, trained parameters, and all metadata
needed to re-apply the model without retraining:

``` r
path <- tempfile(fileext = '.rds')
il_save(model, path)
```

Load and attach the saved model to the same or different data with
[`il_load()`](http://christophertkenny.com/irelink/reference/il_load.md)
and
[`il_attach()`](http://christophertkenny.com/irelink/reference/il_attach.md):

``` r
con2 <- DBI::dbConnect(duckdb::duckdb())
loaded <- il_load(path)
model2 <- il_attach(loaded, fake_1000, con = con2)
head(predict(model2, threshold = 0.85))
#> # A tibble: 6 × 10
#>   unique_id_l unique_id_r match_weight match_probability gamma_first_name
#>         <int>       <int>        <dbl>             <dbl>            <int>
#> 1           0           3         16.8             0.999                4
#> 2           1           3         11.5             0.956                4
#> 3           2           3         11.5             0.956                4
#> 4           8          11         11.5             0.956                4
#> 5          33          36         25.5             1.000                4
#> 6          38          42         23.7             1.000                4
#> # ℹ 5 more variables: gamma_surname <int>, gamma_dob <int>, gamma_city <int>,
#> #   gamma_email <int>, tf_adj_city <dbl>
DBI::dbDisconnect(con2, shutdown = TRUE)
```

This pattern supports the common production workflow: train once on a
representative sample, save the model, and re-apply as new data arrives.

## Predict and cluster

Score all candidate pairs and apply a probability threshold:

``` r
predictions <- predict(model, threshold = 0.5)
nrow(predictions)
#> [1] 1905
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
#> 1 48        cluster_44 
#> 2 442       cluster_440
#> 3 737       cluster_736
#> 4 887       cluster_886
#> 5 904       cluster_900
#> 6 965       cluster_960
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
#> # A tibble: 299 × 8
#>      threshold    tp    fp    fn    tn precision recall    f1
#>          <dbl> <int> <int> <int> <int>     <dbl>  <dbl> <dbl>
#>  1 0            2031  1145     0     0     0.639  1     0.780
#>  2 0.000000147  2031  1145     0     0     0.639  1     0.780
#>  3 0.000000284  1676   558   355   587     0.750  0.825 0.786
#>  4 0.000000636  1461   392   570   753     0.788  0.719 0.752
#>  5 0.00000203   1457   392   574   753     0.788  0.717 0.751
#>  6 0.00000211   1450   361   581   784     0.801  0.714 0.755
#>  7 0.00000220   1448   360   583   785     0.801  0.713 0.754
#>  8 0.00000242   1423   243   608   902     0.854  0.701 0.770
#>  9 0.00000392   1384   177   647   968     0.887  0.681 0.771
#> 10 0.00000407   1384   152   647   993     0.901  0.681 0.776
#> # ℹ 289 more rows
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
#> 1           0           1         8.41             0.717 TRUE       false_negat…
#> 2           0           2         8.41             0.717 TRUE       false_negat…
#> 3           4           6         9.64             0.856 FALSE      false_posit…
#> 4           4          10        13.7              0.990 FALSE      false_posit…
#> 5           5           6         9.64             0.856 FALSE      false_posit…
#> 6           5           7        11.4              0.953 FALSE      false_posit…
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
