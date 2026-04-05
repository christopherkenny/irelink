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
#>     comparisons: # A tibble: 23 × 4
#>      comparisons:    comparison gamma_level      m       u
#>      comparisons:    <chr>            <int>  <dbl>   <dbl>
#>      comparisons:  1 first_name           0 0.427  0.973  
#>      comparisons:  2 first_name           1 0.0942 0.0153 
#>      comparisons:  3 first_name           2 0.0246 0.00172
#>      comparisons:  4 first_name           3 0.0800 0.00285
#>      comparisons:  5 first_name           4 0.374  0.00667
#>      comparisons:  6 surname              0 0.394  0.973  
#>      comparisons:  7 surname              1 0.0834 0.0136 
#>      comparisons:  8 surname              2 0.0248 0.0017 
#>      comparisons:  9 surname              3 0.0644 0.00245
#>      comparisons: 10 surname              4 0.434  0.00914
#>      comparisons: # ℹ 13 more rows
#>     history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996443523796031, 0.000996443523796031, 0.000996443523796031, 0.000996443523796031, 0.996014225904816   , 0.148164115169302   , 0.09546074901194    , 0.0493458913330389  , 0.083657825444055   , 0.623371419041664   , 0.000998422755753137, 0.000998422755753137, 0.260193751911058   , 0.096194667272539   , 0.0204042637432975  , 0.621210471561599   , 0.481486821292808   , 0.518513178707192   , 0.140024077684465   , 0.00099910850300813 , 0.241963862666657   , 0.0504558073486583  , 0.566557143797211   
#>      history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996403395486407, 0.000996403395486407, 0.000996403395486407, 0.000996403395486407, 0.996014386418055   , 0.188423990808304   , 0.0995569460974695  , 0.0477830721044697  , 0.0828634244503757  , 0.581372566539381   , 0.000998433746262956, 0.000998433746262956, 0.283330544600118   , 0.100774772119874   , 0.0240178896060592  , 0.589879926181423   , 0.510814894220438   , 0.489185105779562   , 0.194661482582727   , 0.000999098416893198, 0.233045885464725   , 0.0459263126906602  , 0.525367220844994   
#>      history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996398299120822, 0.000996398299120822, 0.000996398299120822, 0.000996398299120822, 0.996014406803517   , 0.198350139695925   , 0.0986785852628516  , 0.047199927022075   , 0.0818429465972467  , 0.573928401421902   , 0.000998560801080543, 0.000998560801080543, 0.287309529271758   , 0.100358611756792   , 0.024999512959076   , 0.585335224410212   , 0.515581796867125   , 0.484418203132875   , 0.205134417696514   , 0.000999097135895376, 0.230010467602131   , 0.0453228068332228  , 0.518533210732237   
#>      history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996397268290649, 0.000996397268290649, 0.000996397268290649, 0.000996397268290649, 0.996014410926837   , 0.20042596593499    , 0.0984577451276122  , 0.0470778115579849  , 0.0816297528843454  , 0.572408724495068   , 0.000998585685580521, 0.000998585685580521, 0.288253249292827   , 0.100229387656663   , 0.0252224917553532  , 0.584297699923995   , 0.516628991191829   , 0.483371008808171   , 0.207257109614214   , 0.000999096876789692, 0.229394830669822   , 0.0452007411593458  , 0.517148221679828   
#>      history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996397054016539, 0.000996397054016539, 0.000996397054016539, 0.000996397054016539, 0.996014411783934   , 0.20085872050173    , 0.0984110118422801  , 0.0470523674743706  , 0.0815853397011403  , 0.572092560480479   , 0.000998590765673895, 0.000998590765673895, 0.288458139385508   , 0.100200521568961   , 0.0252695530092538  , 0.58407460450493    , 0.516850522426651   , 0.483149477573349   , 0.207698460410226   , 0.000999096822930489, 0.229266831496979   , 0.0451753666362169  , 0.516860244633648   
#>      history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996397009252417, 0.000996397009252417, 0.000996397009252417, 0.000996397009252417, 0.99601441196299    , 0.200949161891715   , 0.0984012276870635  , 0.0470470504218502  , 0.0815760579290404  , 0.572026502070331   , 0.000998591823798396, 0.000998591823798396, 0.288501397808736   , 0.100194400191217   , 0.0252793737984372  , 0.584027644554014   , 0.516896968920111   , 0.483103031079889   , 0.207790668916442   , 0.00099909681167873 , 0.229240089548295   , 0.0451700655566441  , 0.516800079166941   
#>      history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.0009963969998916  , 0.0009963969998916  , 0.0009963969998916  , 0.0009963969998916  , 0.996014412000434   , 0.200968075660466   , 0.0983991810145353  , 0.0470459385066101  , 0.0815741168116998  , 0.572012688006689   , 0.000998592044953528, 0.000998592044953528, 0.288510467255832   , 0.100193116103402   , 0.025281423638615   , 0.584017808912244   , 0.516906688890342   , 0.483093311109658   , 0.207809951272898   , 0.000999096809325827, 0.229234497345293   , 0.045168957021788   , 0.516787497550695   
#>      history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996396997933763, 0.000996396997933763, 0.000996396997933763, 0.000996396997933763, 0.996014412008265   , 0.200972031561775   , 0.098398752928033   , 0.0470457059460617  , 0.0815737108129641  , 0.572009798751167   , 0.000998592091204882, 0.000998592091204882, 0.288512365419563   , 0.100192847360702   , 0.0252818519443113  , 0.584015751093013   , 0.516908722177594   , 0.483091277822406   , 0.207813984233537   , 0.000999096808833712, 0.229233327718388   , 0.0451687251689093  , 0.516784866070332   
#>      history: 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.1483706887738     , 0.111429217818714   , 0.0347232162043766  , 0.114385328591217   , 0.591091548611893   , 0.162338591001175   , 0.102717029060714   , 0.0362609702793288  , 0.0836750203881885  , 0.615008389270594   , 0.000995425257331191, 0.000995425257331191, 0.000995425257331191, 0.000995425257331191, 0.000995425257331191, 0.995022873713344   , 0.449456278761577   , 0.550543721238423   , 0.145585480138351   , 0.000999097830535709, 0.232210155524357   , 0.0455957365920808  , 0.575609529914675   
#>      history: 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.384942859243163   , 0.100580600407537   , 0.0264603447819654  , 0.0859527195935813  , 0.402063475973752   , 0.350762927251787   , 0.0890321775437639  , 0.0265983744636584  , 0.0686072857247144  , 0.464999235016076   , 0.000995298894827364, 0.000995298894827364, 0.000995298894827364, 0.000995298894827364, 0.000995298894827364, 0.995023505525863   , 0.421130441770877   , 0.578869558229123   , 0.14116536834803    , 0.000999067276397647, 0.229480711610515   , 0.0426016864637832  , 0.585753166301274   
#>      history: 9                  , 9                  , 9                  , 9                  , 9                  , 9                  , 9                  , 9                  , 9                  , 9                  , 9                  , 9                  , 9                  , 9                  , 9                  , 9                  , 9                  , 9                  , 9                  , 9                  , 9                  , 9                  , 9                  , 3                  , 3                  , 3                  , 3                  , 3                  , 3                  , 3                  , 3                  , 3                  , 3                  , 3                  , 3                  , 3                  , 3                  , 3                  , 3                  , 3                  , 3                  , 3                  , 3                  , 3                  , 3                  , 3                  , first_name         , first_name         , first_name         , first_name         , first_name         , surname            , surname            , surname            , surname            , surname            , dob                , dob                , dob                , dob                , dob                , dob                , city               , city               , email              , email              , email              , email              , email              , 0                  , 1                  , 2                  , 3                  , 4                  , 0                  , 1                  , 2                  , 3                  , 4                  , 0                  , 1                  , 2                  , 3                  , 4                  , 5                  , 0                  , 1                  , 0                  , 1                  , 2                  , 3                  , 4                  , 0.423291005777717  , 0.094799061019714  , 0.024768005269377  , 0.0805539104911073 , 0.376588017442085  , 0.389760470630797  , 0.0839946319489435 , 0.0249800273159525 , 0.0647962805555044 , 0.436468589548803  , 0.00099528096560076, 0.00099528096560076, 0.00099528096560076, 0.00099528096560076, 0.00099528096560076, 0.995023595171996  , 0.441532132253488  , 0.558467867746512  , 0.142261352356464  , 0.00099906294067831, 0.227441720859159  , 0.0423071345466731 , 0.586990729297025  
#>      history: 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.426532653884728   , 0.0942452729957086  , 0.0246162133397712  , 0.080092506355628   , 0.374513353424164   , 0.393295782063721   , 0.0834882459334441  , 0.0248367265720077  , 0.064435225906234   , 0.433944019524593   , 0.000995279378511641, 0.000995279378511641, 0.000995279378511641, 0.000995279378511641, 0.000995279378511641, 0.995023603107442   , 0.44375825984233    , 0.55624174015767    , 0.143043799164478   , 0.000999062556876177, 0.227044031262081   , 0.0422547139867117  , 0.586658393029853   
#>      history: 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.426798761527704   , 0.0942016356323123  , 0.0246038049506646  , 0.080053435436033   , 0.374342362453286   , 0.393593808276888   , 0.0834493658030401  , 0.0248255783303993  , 0.064405264513239   , 0.433725983076434   , 0.000995279232904892, 0.000995279232904892, 0.000995279232904892, 0.000995279232904892, 0.000995279232904892, 0.995023603835476   , 0.443943515538041   , 0.556056484461959   , 0.143189545553894   , 0.000999062521664383, 0.226990159491772   , 0.0422466051586987  , 0.586574627273971   
#>      history: 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.426821839531266   , 0.0941983707274048  , 0.0246027662578123  , 0.0800498927181369  , 0.37432713076538    , 0.39361991854587    , 0.0834467211112343  , 0.0248247101087019  , 0.0644027291807646  , 0.433705921053429   , 0.000995279218636346, 0.000995279218636346, 0.000995279218636346, 0.000995279218636346, 0.000995279218636346, 0.995023603906818   , 0.443958798276785   , 0.556041201723215   , 0.143210904528427   , 0.000999062518213848, 0.226983308610808   , 0.0422454842961509  , 0.5865612400464     
#>      history: 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.426823965771471   , 0.0941981309082332  , 0.024602674966248   , 0.080049549890498   , 0.37432567846355    , 0.393622334691278   , 0.0834465641186067  , 0.0248246407431121  , 0.0644025040419123  , 0.433703956405091   , 0.000995279217156527, 0.000995279217156527, 0.000995279217156527, 0.000995279217156527, 0.000995279217156527, 0.995023603914218   , 0.443960100564467   , 0.556039899435533   , 0.143213765118491   , 0.000999062517855986, 0.226982456035586   , 0.0422453380075297  , 0.586559378320537
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
#> [1] 1903
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
#> 1 66        cluster_63 
#> 2 172       cluster_172
#> 3 484       cluster_479
#> 4 588       cluster_581
#> 5 780       cluster_778
#> 6 881       cluster_879
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
#>  2 0.000000146  2031  1145     0     0     0.639  1     0.780
#>  3 0.000000284  1676   558   355   587     0.750  0.825 0.786
#>  4 0.000000634  1461   392   570   753     0.788  0.719 0.752
#>  5 0.00000206   1457   392   574   753     0.788  0.717 0.751
#>  6 0.00000218   1450   361   581   784     0.801  0.714 0.755
#>  7 0.00000222   1425   244   606   901     0.854  0.702 0.770
#>  8 0.00000236   1423   243   608   902     0.854  0.701 0.770
#>  9 0.00000399   1384   177   647   968     0.887  0.681 0.771
#> 10 0.00000422   1384   152   647   993     0.901  0.681 0.776
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
#> 1           0           1         8.32             0.704 TRUE       false_negat…
#> 2           0           2         8.32             0.704 TRUE       false_negat…
#> 3           4           6         9.59             0.852 FALSE      false_posit…
#> 4           4          10        13.6              0.989 FALSE      false_posit…
#> 5           5           6         9.59             0.852 FALSE      false_posit…
#> 6           5           7        11.3              0.949 FALSE      false_posit…
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
