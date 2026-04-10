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
#>      comparisons:  2 first_name           1 0.0941 0.0157 
#>      comparisons:  3 first_name           2 0.0246 0.00183
#>      comparisons:  4 first_name           3 0.0801 0.00272
#>      comparisons:  5 first_name           4 0.374  0.00676
#>      comparisons:  6 surname              0 0.394  0.972  
#>      comparisons:  7 surname              1 0.0833 0.0144 
#>      comparisons:  8 surname              2 0.0248 0.00186
#>      comparisons:  9 surname              3 0.0644 0.00242
#>      comparisons: 10 surname              4 0.434  0.00947
#>      comparisons: # ℹ 13 more rows
#>     history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996444040531695, 0.000996444040531695, 0.000996444040531695, 0.000996444040531695, 0.996014223837873   , 0.147903763885232   , 0.0953215445092632  , 0.0492873773794528  , 0.0837549408848369  , 0.623732373341215   , 0.000998410156685853, 0.000998410156685853, 0.26032852400352    , 0.0955343402898549  , 0.0205147887359841  , 0.621625526657269   , 0.481176332638046   , 0.518823667361954   , 0.139425390017494   , 0.000999108632883922, 0.242108280536204   , 0.0505157456215758  , 0.566951475191842   
#>      history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996403542436947, 0.000996403542436947, 0.000996403542436947, 0.000996403542436947, 0.996014385830252   , 0.188240684273363   , 0.0995097434600473  , 0.0477883874400338  , 0.082895829019004   , 0.581565355807552   , 0.00099841903893824 , 0.00099841903893824 , 0.283379962684517   , 0.100516111317081   , 0.0241168044947878  , 0.589990283425738   , 0.510778956143159   , 0.489221043856841   , 0.194359121372317   , 0.00099909845382983 , 0.233134306138963   , 0.0459437647529286  , 0.525563709281962   
#>      history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996398375100665, 0.000996398375100665, 0.000996398375100665, 0.000996398375100665, 0.996014406499597   , 0.198279490490172   , 0.0986382145297789  , 0.0472009958187574  , 0.0818599201421655  , 0.574021379019127   , 0.000998540756017449, 0.000998540756017449, 0.287389637456461   , 0.100114835667308   , 0.0251263030412985  , 0.585372142322897   , 0.515584907713546   , 0.484415092286454   , 0.204978658639159   , 0.000999097154993374, 0.230056095447837   , 0.0453318417343959  , 0.518634307023616   
#>      history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996397322372401, 0.000996397322372401, 0.000996397322372401, 0.000996397322372401, 0.996014410710511   , 0.200397145333015   , 0.0984144303936551  , 0.0470767059370508  , 0.0816420160827824  , 0.572469702253496   , 0.000998564935545089, 0.000998564935545089, 0.288348654685118   , 0.0999865697946706  , 0.0253571665049316  , 0.584310479144189   , 0.516650811034187   , 0.483349188965813   , 0.207146659304252   , 0.000999096890383492, 0.229427285772031   , 0.0452071788517657  , 0.517219779181568   
#>      history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996397101893196, 0.000996397101893196, 0.000996397101893196, 0.000996397101893196, 0.996014411592427   , 0.200842040828131   , 0.0983666474367144  , 0.0470506061568045  , 0.0815962771875729  , 0.572144428390778   , 0.000998569913102264, 0.000998569913102264, 0.288558596148896   , 0.0999576362242293  , 0.0254061477269979  , 0.584080480073672   , 0.516878158224022   , 0.483121841775978   , 0.207600837200145   , 0.000999096834964602, 0.229295560075585   , 0.0451810686678358  , 0.516923437221469   
#>      history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996397055484763, 0.000996397055484763, 0.000996397055484763, 0.000996397055484763, 0.996014411778061   , 0.200935724450791   , 0.0983565661272459  , 0.0470451107106076  , 0.0815866460086659  , 0.572075952702689   , 0.000998570957919166, 0.000998570957919166, 0.288603273286295   , 0.0999514512905658  , 0.0254164326665393  , 0.584031700840762   , 0.51692619238538    , 0.48307380761462    , 0.207696442621004   , 0.000999096823299536, 0.22926783160531    , 0.0451755726877139  , 0.516861056262672   
#>      history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.0009963970457069  , 0.0009963970457069  , 0.0009963970457069  , 0.0009963970457069  , 0.996014411817173   , 0.200955464093272   , 0.0983544413441216  , 0.0470439528186311  , 0.0815846166183354  , 0.57206152512564    , 0.000998571177953007, 0.000998571177953007, 0.288612712380151   , 0.0999501439490562  , 0.0254185942765846  , 0.584021407038302   , 0.516936320850764   , 0.483063679149236   , 0.207716586127482   , 0.000999096820841806, 0.229261989365951   , 0.0451744147279035  , 0.516847912957821   
#>      history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996397043646426, 0.000996397043646426, 0.000996397043646426, 0.000996397043646426, 0.996014411825414   , 0.200959623842122   , 0.0983539935707013  , 0.0470437088171324  , 0.0815841889574715  , 0.572058484812572   , 0.000998571224317437, 0.000998571224317437, 0.288614702921046   , 0.0999498682720685  , 0.0254190492283352  , 0.584019237129915   , 0.516938455577273   , 0.483061544422727   , 0.207720830948296   , 0.000999096820323892, 0.229260758234996   , 0.0451741707126172  , 0.516845143283767   
#>      history: 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.147915717441857   , 0.11110997419125    , 0.0346050192261027  , 0.114685837938404   , 0.591683451202387   , 0.162561425202203   , 0.102273978740115   , 0.0362247590464685  , 0.0838387073092799  , 0.615101129701933   , 0.000995425695721934, 0.000995425695721934, 0.000995425695721934, 0.000995425695721934, 0.000995425695721934, 0.99502287152139    , 0.449589839630985   , 0.550410160369015   , 0.145268298077645   , 0.000999097936527247, 0.232242894546124   , 0.0456914938005445  , 0.575798215639159   
#>      history: 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.385212887472585   , 0.100460083419218   , 0.0264278665865359  , 0.0859683562522832  , 0.401930806269379   , 0.351248594566366   , 0.0888677766299026  , 0.026552586497349   , 0.0685964723282141  , 0.464734569978168   , 0.00099529883566194 , 0.00099529883566194 , 0.00099529883566194 , 0.00099529883566194 , 0.00099529883566194 , 0.99502350582169    , 0.421496627955967   , 0.578503372044033   , 0.140719866879953   , 0.000999067262090216, 0.229525617315342   , 0.0427044072235141  , 0.586051041319101   
#>      history: 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.423457324047039   , 0.0946980355157531  , 0.0247391541836793  , 0.0805824515063319  , 0.376523034747197   , 0.390081099971732   , 0.0838460129576224  , 0.0249357475762011  , 0.0648010895259404  , 0.436336049968504   , 0.00099528096194095 , 0.00099528096194095 , 0.00099528096194095 , 0.00099528096194095 , 0.00099528096194095 , 0.995023595190295   , 0.441745950204825   , 0.558254049795175   , 0.141834367155223   , 0.000999062939793267, 0.227514342057214   , 0.0423615798249828  , 0.587290648022788   
#>      history: 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.426643522734825   , 0.094150900697417   , 0.0245889592788085  , 0.0801298432130947  , 0.374486774075855   , 0.393556225368065   , 0.0833434741736889  , 0.0247934893179964  , 0.0644471685648073  , 0.433859642575443   , 0.000995279403208629, 0.000995279403208629, 0.000995279403208629, 0.000995279403208629, 0.000995279403208629, 0.995023602983957   , 0.443923055337109   , 0.556076944662891   , 0.142612762691813   , 0.0009990625628486  , 0.227125568830371   , 0.0423030163346104  , 0.586959589580358   
#>      history: 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.426901650718843   , 0.0941083919026991  , 0.0245768611925155  , 0.0800919583982902  , 0.374321137787652   , 0.393845619662406   , 0.0833053522023362  , 0.0247825631754666  , 0.064418175296523   , 0.433648289663268   , 0.000995279261543769, 0.000995279261543769, 0.000995279261543769, 0.000995279261543769, 0.000995279261543769, 0.995023603692281   , 0.444101960787497   , 0.555898039212503   , 0.142757037842623   , 0.000999062528590067, 0.227072957832758   , 0.0422944599007078  , 0.586876481895321   
#>      history: 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.426923789291205   , 0.0941052809621165  , 0.0245758670544747  , 0.0800885464215706  , 0.374306516270633   , 0.393870702109459   , 0.0833028239521424  , 0.0247817280984656  , 0.0644157469966597  , 0.433628998843273   , 0.000995279247729352, 0.000995279247729352, 0.000995279247729352, 0.000995279247729352, 0.000995279247729352, 0.995023603761353   , 0.444116550905292   , 0.555883449094708   , 0.142778149524151   , 0.000999062525249353, 0.227066257062514   , 0.0422933112629731  , 0.586863219625113   
#>      history: 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.426925812205493   , 0.094105060065308   , 0.0245757813642145  , 0.0800882171447122  , 0.374305129220272   , 0.393873004118112   , 0.0833026823256812  , 0.024781662940692   , 0.0644155329597727  , 0.433627117655743   , 0.000995279246298328, 0.000995279246298328, 0.000995279246298328, 0.000995279246298328, 0.000995279246298328, 0.995023603768508   , 0.444117781688279   , 0.555882218311721   , 0.142780978109497   , 0.000999062524903292, 0.227065420987966   , 0.0422931634619705  , 0.586861374915663
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
#> 1          32          34         16.8             0.999                4
#> 2         159         160         23.4             1.000                4
#> 3         164         171         16.4             0.998                0
#> 4         165         171         16.4             0.998                0
#> 5         166         171         16.4             0.998                0
#> 6         167         171         16.4             0.998                0
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
#>  2 0.000000147  2031  1145     0     0     0.639  1     0.780
#>  3 0.000000281  1676   558   355   587     0.750  0.825 0.786
#>  4 0.000000641  1461   392   570   753     0.788  0.719 0.752
#>  5 0.00000201   1457   392   574   753     0.788  0.717 0.751
#>  6 0.00000211   1450   361   581   784     0.801  0.714 0.755
#>  7 0.00000215   1448   360   583   785     0.801  0.713 0.754
#>  8 0.00000241   1423   243   608   902     0.854  0.701 0.770
#>  9 0.00000383   1384   177   647   968     0.887  0.681 0.771
#> 10 0.00000401   1384   152   647   993     0.901  0.681 0.776
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
#> 1           0           1         8.33             0.705 TRUE       false_negat…
#> 2           0           2         8.33             0.705 TRUE       false_negat…
#> 3           4           6         9.62             0.854 FALSE      false_posit…
#> 4           4          10        13.6              0.989 FALSE      false_posit…
#> 5           5           6         9.62             0.854 FALSE      false_posit…
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
