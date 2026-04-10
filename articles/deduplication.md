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
#>      comparisons:  2 first_name           1 0.0941 0.0158 
#>      comparisons:  3 first_name           2 0.0246 0.00183
#>      comparisons:  4 first_name           3 0.0801 0.00272
#>      comparisons:  5 first_name           4 0.374  0.00676
#>      comparisons:  6 surname              0 0.394  0.972  
#>      comparisons:  7 surname              1 0.0833 0.0144 
#>      comparisons:  8 surname              2 0.0248 0.00186
#>      comparisons:  9 surname              3 0.0644 0.00243
#>      comparisons: 10 surname              4 0.434  0.0095 
#>      comparisons: # ℹ 13 more rows
#>     history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.00099644401169903 , 0.00099644401169903 , 0.00099644401169903 , 0.00099644401169903 , 0.996014223953204   , 0.14796536254434    , 0.0953258879568405  , 0.0492869794765196  , 0.0837417689240461  , 0.623680001098254   , 0.000998410508974289, 0.000998410508974289, 0.260335575059738   , 0.0955315663724466  , 0.020511366734139   , 0.621624670815728   , 0.481141617219322   , 0.518858382780678   , 0.139446621685771   , 0.000999108625637153, 0.24210790606454    , 0.0505124330119586  , 0.566933930612093   
#>      history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996403527699925, 0.000996403527699925, 0.000996403527699925, 0.000996403527699925, 0.9960143858892     , 0.188272766600318   , 0.0995072652937678  , 0.0477866106516163  , 0.0828918676107588  , 0.58154148984354    , 0.000998419263331763, 0.000998419263331763, 0.283379766627059   , 0.100516839274194   , 0.0241183991331309  , 0.589988156438952   , 0.510768324393077   , 0.489231675606923   , 0.194388317459041   , 0.000999098450125619, 0.233125583427164   , 0.0459420253005735  , 0.525544975363095   
#>      history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996398365129165, 0.000996398365129165, 0.000996398365129165, 0.000996398365129165, 0.996014406539483   , 0.198301158599581   , 0.0986366741214786  , 0.0471997992486873  , 0.081857298347997   , 0.574005069682256   , 0.000998541120013988, 0.000998541120013988, 0.28738829658735    , 0.100114971783636   , 0.0251271959925144  , 0.585372453396472   , 0.515575616900025   , 0.484424383099975   , 0.204998326089368   , 0.000999097152486977, 0.23005019467028    , 0.0453306655057561  , 0.518621716582108   
#>      history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996397314129217, 0.000996397314129217, 0.000996397314129217, 0.000996397314129217, 0.996014410743483   , 0.20041520991462    , 0.0984132774895387  , 0.0470757182087931  , 0.0816397902229421  , 0.572456004164106   , 0.000998565309332605, 0.000998565309332605, 0.288346246237133   , 0.099986776156714   , 0.0253576841676836  , 0.584312162819804   , 0.516640816287636   , 0.483359183712364   , 0.207162802480127   , 0.000999096888311515, 0.229422417115729   , 0.0452062071222374  , 0.517209476393596   
#>      history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996397094162063, 0.000996397094162063, 0.000996397094162063, 0.000996397094162063, 0.996014411623352   , 0.2008590474021     , 0.098365609343943   , 0.0470496800185438  , 0.0815941649991126  , 0.572131498236301   , 0.000998570285095336, 0.000998570285095336, 0.288555795868567   , 0.0999578856569962  , 0.025406550720463   , 0.584082627183783   , 0.516867839239515   , 0.483132160760485   , 0.207615932347938   , 0.000999096833021331, 0.229290997378562   , 0.0451801575481938  , 0.516913815892285   
#>      history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996397047892939, 0.000996397047892939, 0.000996397047892939, 0.000996397047892939, 0.996014411808428   , 0.200952444636609   , 0.0983555590997448  , 0.0470442012738731  , 0.0815845642816226  , 0.572063230708151   , 0.000998571328806114, 0.000998571328806114, 0.288600358121351   , 0.0999517145269633  , 0.0254168046214963  , 0.584033980072577   , 0.51691577119311    , 0.48308422880689    , 0.207711252179399   , 0.000999096821391281, 0.229263352154903   , 0.0451746780600122  , 0.516851620784294   
#>      history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996397038151071, 0.000996397038151071, 0.000996397038151071, 0.000996397038151071, 0.996014411847396   , 0.200972110525085   , 0.0983534423077848  , 0.0470430476876562  , 0.0815825426878378  , 0.572048856791636   , 0.000998571548456453, 0.000998571548456453, 0.288609766451053   , 0.099950411012168   , 0.0254189582511136  , 0.584023721188752   , 0.516925871165374   , 0.483074128834626   , 0.207731321825695   , 0.000999096818942598, 0.229257531424971   , 0.0451735243617309  , 0.51683852556866    
#>      history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996397036099582, 0.000996397036099582, 0.000996397036099582, 0.000996397036099582, 0.996014411855602   , 0.200976251906611   , 0.0983529965225192  , 0.0470428047592257  , 0.0815821169603555  , 0.572045829851288   , 0.000998571594708487, 0.000998571594708487, 0.28861174914686    , 0.099950136330482   , 0.0254194112156708  , 0.58402156011757    , 0.516927998432589   , 0.483072001567411   , 0.207735548198864   , 0.000999096818426943, 0.229256305662876   , 0.0451732814102062  , 0.516835767909627   
#>      history: 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.148141266345474   , 0.111058818760682   , 0.0346027730077845  , 0.114674102679665   , 0.591523039206394   , 0.162682059224297   , 0.102308491297013   , 0.0362179033838061  , 0.0838266977250398  , 0.614964848369844   , 0.000995425577631418, 0.000995425577631418, 0.000995425577631418, 0.000995425577631418, 0.000995425577631418, 0.995022872111843   , 0.449465988366765   , 0.550534011633235   , 0.145252274259776   , 0.000999097907976023, 0.232233654518389   , 0.0456816787891906  , 0.575833294524668   
#>      history: 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.385461128864234   , 0.100414034496903   , 0.0264183960126053  , 0.0859352351193239  , 0.401771205506935   , 0.351496133861677   , 0.0888427218196623  , 0.0265428911048591  , 0.068572178004133   , 0.464546075209669   , 0.000995298718981696, 0.000995298718981696, 0.000995298718981696, 0.000995298718981696, 0.000995298718981696, 0.995023506405092   , 0.421512400720759   , 0.578487599279241   , 0.140716832762906   , 0.0009990672338745  , 0.229497344128948   , 0.0426970431730279  , 0.586089712701243   
#>      history: 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.42356492295118    , 0.0946740539703155  , 0.0247354573988711  , 0.0805687041576382  , 0.376456861521995   , 0.390192306578744   , 0.0838381316924804  , 0.0249315919225571  , 0.0647892837856747  , 0.436248686020544   , 0.000995280910142434, 0.000995280910142434, 0.000995280910142434, 0.000995280910142434, 0.000995280910142434, 0.995023595449288   , 0.441753238754482   , 0.558246761245518   , 0.141884164368801   , 0.000999062927266965, 0.227487740239418   , 0.0423563588702945  , 0.58727267359422    
#>      history: 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.426733249138787   , 0.0941300075310646  , 0.0245861255469296  , 0.080118546395707   , 0.374432071387512   , 0.39364814436684    , 0.0833389306123207  , 0.0247902123185012  , 0.0644373248113195  , 0.433785387891019   , 0.000995279358722449, 0.000995279358722449, 0.000995279358722449, 0.000995279358722449, 0.000995279358722449, 0.995023603206388   , 0.443915413791388   , 0.556084586208612   , 0.142673558864139   , 0.000999062552090596, 0.22709901970016    , 0.0422978168252161  , 0.586930542058394   
#>      history: 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.426989767764931   , 0.0940878383336046  , 0.0245741123131072  , 0.0800808735967598  , 0.374267407991598   , 0.393935708840585   , 0.0833012027292944  , 0.0247793767928768  , 0.064408525319491   , 0.433575186317753   , 0.000995279217651687, 0.000995279217651687, 0.000995279217651687, 0.000995279217651687, 0.000995279217651687, 0.995023603911742   , 0.444092447410749   , 0.555907552589251   , 0.142819457004258   , 0.00099906251797573 , 0.227046269934301   , 0.0422892282316707  , 0.586845982311794   
#>      history: 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.427011784331245   , 0.0940847595974115  , 0.0245731250413683  , 0.0800774762907398  , 0.374252854739236   , 0.393960647696244   , 0.0832987133125389  , 0.0247785498027951  , 0.0644061124729071  , 0.433555976715515   , 0.000995279203871815, 0.000995279203871815, 0.000995279203871815, 0.000995279203871815, 0.000995279203871815, 0.995023603980641   , 0.444106850621826   , 0.555893149378174   , 0.142840789360048   , 0.00099906251464337 , 0.227039536197423   , 0.0422880726022838  , 0.586832539325601   
#>      history: 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.427013800432452   , 0.0940845414422759  , 0.0245730397949898  , 0.0800771476007017  , 0.374251470729581   , 0.393962941209486   , 0.0832985751931742  , 0.0247784852911218  , 0.0644058993775427  , 0.433554098928675   , 0.00099527920244081 , 0.00099527920244081 , 0.00099527920244081 , 0.00099527920244081 , 0.00099527920244081 , 0.995023603987796   , 0.444108064265295   , 0.555891935734705   , 0.142843647350459   , 0.000999062514297313, 0.227038694488527   , 0.042287923666138   , 0.586830671980578
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
#> 1           0           3         16.7             0.999                4
#> 2           1           3         11.4             0.953                4
#> 3           2           3         11.4             0.953                4
#> 4           8          11         11.4             0.953                4
#> 5          33          36         25.4             1.000                4
#> 6          38          42         23.5             1.000                4
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
#> 1 57        cluster_50 
#> 2 411       cluster_409
#> 3 624       cluster_618
#> 4 35        cluster_32 
#> 5 596       cluster_592
#> 6 882       cluster_879
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
#>  2 0.000000148  2031  1145     0     0     0.639  1     0.780
#>  3 0.000000280  1676   558   355   587     0.750  0.825 0.786
#>  4 0.000000641  1461   392   570   753     0.788  0.719 0.752
#>  5 0.00000199   1457   392   574   753     0.788  0.717 0.751
#>  6 0.00000211   1450   361   581   784     0.801  0.714 0.755
#>  7 0.00000217   1448   360   583   785     0.801  0.713 0.754
#>  8 0.00000241   1423   243   608   902     0.854  0.701 0.770
#>  9 0.00000379   1384   177   647   968     0.887  0.681 0.771
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
#> 1           0           1         8.34             0.707 TRUE       false_negat…
#> 2           0           2         8.34             0.707 TRUE       false_negat…
#> 3           4           6         9.63             0.855 FALSE      false_posit…
#> 4           4          10        13.6              0.990 FALSE      false_posit…
#> 5           5           6         9.63             0.855 FALSE      false_posit…
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
