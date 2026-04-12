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
#>   <chr>        <dbl>            <dbl>            <dbl>
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
#>      comparisons:  1 first_name           0 0.427  0.974  
#>      comparisons:  2 first_name           1 0.0943 0.0147 
#>      comparisons:  3 first_name           2 0.0246 0.00168
#>      comparisons:  4 first_name           3 0.0801 0.00292
#>      comparisons:  5 first_name           4 0.374  0.00672
#>      comparisons:  6 surname              0 0.394  0.972  
#>      comparisons:  7 surname              1 0.0834 0.0145 
#>      comparisons:  8 surname              2 0.0249 0.00158
#>      comparisons:  9 surname              3 0.0644 0.00247
#>      comparisons: 10 surname              4 0.434  0.00951
#>      comparisons: # ℹ 13 more rows
#>     history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996443816084291, 0.000996443816084291, 0.000996443816084291, 0.000996443816084291, 0.996014224735663   , 0.148143469446254   , 0.0952280647455363  , 0.0494562915373691  , 0.0836512038625525  , 0.623520970408289   , 0.00099841497778848 , 0.00099841497778848 , 0.260227418188233   , 0.0962108543452709  , 0.0203321087100588  , 0.621232788800861   , 0.481079026586109   , 0.518920973413891   , 0.139702346236058   , 0.000999108576471562, 0.241945053449472   , 0.0504874172391196  , 0.566866074498879   
#>      history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996403481038132, 0.000996403481038132, 0.000996403481038132, 0.000996403481038132, 0.996014386075848   , 0.188346514423749   , 0.0995019780803254  , 0.047802904500473   , 0.0828771814406022  , 0.581471421554851   , 0.000998423476409509, 0.000998423476409509, 0.283369283684864   , 0.100807468016833   , 0.0239572974177496  , 0.589869103927734   , 0.510657796387787   , 0.489342203612213   , 0.194491348793085   , 0.000999098438396983, 0.233093955399671   , 0.0459363909875971  , 0.52547920638125    
#>      history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996398371647376, 0.000996398371647376, 0.000996398371647376, 0.000996398371647376, 0.996014406513411   , 0.19827174591045    , 0.098642686868099   , 0.0472151494875017  , 0.0818559461173336  , 0.574014471616616   , 0.000998547195738292, 0.000998547195738292, 0.287369139627591   , 0.10038741387185    , 0.0249203776465873  , 0.585325974462496   , 0.515447628103609   , 0.484552371896391   , 0.204989529531906   , 0.000999097154125369, 0.230051705335134   , 0.0453313487800746  , 0.51862831919876    
#>      history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996397338748909, 0.000996397338748909, 0.000996397338748909, 0.000996397338748909, 0.996014410645004   , 0.200349078535182   , 0.0984235641069257  , 0.0470924435233104  , 0.0816425023487645  , 0.572492411485817   , 0.000998571582062071, 0.000998571582062071, 0.288317020848413   , 0.100257308251297   , 0.0251387798750621  , 0.584289747861104   , 0.516499047523454   , 0.483500952476546   , 0.207116220387811   , 0.000999096894499834, 0.229434962915465   , 0.045209039702758   , 0.517240680099467   
#>      history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996397124037511, 0.000996397124037511, 0.000996397124037511, 0.000996397124037511, 0.99601441150385    , 0.200782238655684   , 0.0983771242292828  , 0.047066879156303   , 0.0815980316842966  , 0.572175726274434   , 0.000998576561789458, 0.000998576561789458, 0.288522772076437   , 0.100228260156545   , 0.0251849080108044  , 0.584066906632635   , 0.516721460475317   , 0.483278539524683   , 0.207558417565669   , 0.000999096840530721, 0.229306729090003   , 0.0451836137079687  , 0.516952142795829   
#>      history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996397079176002, 0.000996397079176002, 0.000996397079176002, 0.000996397079176002, 0.996014411683296   , 0.200872779250024   , 0.0983673983288193  , 0.0470615363111262  , 0.0815887365399235  , 0.572109549570107   , 0.000998577599133341, 0.000998577599133341, 0.288566212884542   , 0.100222100043332   , 0.0251945401163513  , 0.584019991757509   , 0.516768097197065   , 0.483231902802935   , 0.20765081541409    , 0.000999096829254485, 0.229279934476651   , 0.045178301159842   , 0.516891852120163   
#>      history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996397069793325, 0.000996397069793325, 0.000996397069793325, 0.000996397069793325, 0.996014411720827   , 0.200891716871458   , 0.0983653634507509  , 0.0470604188240926  , 0.0815867923127056  , 0.572095708540993   , 0.000998577815977553, 0.000998577815977553, 0.288575321507466   , 0.100220807644576   , 0.0251965513736226  , 0.584010163842381   , 0.516777858493631   , 0.483222141506369   , 0.207670140452376   , 0.000999096826896088, 0.229274330365416   , 0.0451771900496079  , 0.516879242305704   
#>      history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996397067830587, 0.000996397067830587, 0.000996397067830587, 0.000996397067830587, 0.996014411728678   , 0.200895678428218   , 0.0983649377570221  , 0.0470601850589473  , 0.081586385595443   , 0.57209281316037    , 0.000998577861334696, 0.000998577861334696, 0.288577228142939   , 0.100220537117354   , 0.0251969717306046  , 0.584008107286434   , 0.516779900765419   , 0.483220099234581   , 0.207674183016355   , 0.000999096826402741, 0.229273158051795   , 0.045176957619225   , 0.516876604486222   
#>      history: 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.146939779049081   , 0.111741660857765   , 0.0347816848077502  , 0.114345800275851   , 0.592191075009552   , 0.162550062303913   , 0.102401799483146   , 0.0363999833993783  , 0.083777530845253   , 0.614870623968309   , 0.000995426075515834, 0.000995426075515834, 0.000995426075515834, 0.000995426075515834, 0.000995426075515834, 0.995022869622421   , 0.448748317984348   , 0.551251682015652   , 0.1456464018054     , 0.000999098028351526, 0.232130590489318   , 0.0456626728735156  , 0.575561236803416   
#>      history: 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.383987663358592   , 0.100808626280115   , 0.0265055690829685  , 0.0860661518132114  , 0.402631989465114   , 0.35006939281314    , 0.0890390114011999  , 0.0266682371658846  , 0.0687016659682567  , 0.465521692651519   , 0.000995299330879959, 0.000995299330879959, 0.000995299330879959, 0.000995299330879959, 0.000995299330879959, 0.9950235033456     , 0.420311361806485   , 0.579688638193515   , 0.141094173539205   , 0.000999067381844203, 0.229424790219779   , 0.0426332783385035  , 0.585848690520669   
#>      history: 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.422862312216495   , 0.094934224820567   , 0.0247890741018672  , 0.0805964649807253  , 0.376817923880346   , 0.389515830040468   , 0.0839306105773773  , 0.0250329549607631  , 0.0648423492832517  , 0.436678255138139   , 0.000995281188481078, 0.000995281188481078, 0.000995281188481078, 0.000995281188481078, 0.000995281188481078, 0.995023594057595   , 0.440997622792983   , 0.559002377207017   , 0.142130076025626   , 0.000999062994576873, 0.227449963818009   , 0.0423277903308051  , 0.587093106830982   
#>      history: 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.426208440415814   , 0.0943628748866316  , 0.0246324405970547  , 0.0801199860436623  , 0.374676258056838   , 0.393162335697889   , 0.0834035303474006  , 0.0248863601265578  , 0.0644698282788504  , 0.434077945549302   , 0.000995279554778037, 0.000995279554778037, 0.000995279554778037, 0.000995279554778037, 0.000995279554778037, 0.99502360222611    , 0.44330277943953    , 0.55669722056047    , 0.142907698529288   , 0.000999062599502322, 0.227056269689459   , 0.0422731337360296  , 0.586763835445721   
#>      history: 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.426487359153849   , 0.0943169694726694  , 0.0246194240177662  , 0.0800790561630384  , 0.374497191192677   , 0.393474588225073   , 0.0833619844064974  , 0.0248747371986399  , 0.0644383726443898  , 0.4338503175254     , 0.00099527940309802 , 0.00099527940309802 , 0.00099527940309802 , 0.00099527940309802 , 0.00099527940309802 , 0.99502360298451    , 0.443497870380256   , 0.556502129619744   , 0.143054643867103   , 0.000999062562821852, 0.22700202775012    , 0.0422647308635232  , 0.586679534956431   
#>      history: 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.426511844246764   , 0.0943134533287621  , 0.0246183189760728  , 0.0800753073998402  , 0.374481076048561   , 0.393502280992883   , 0.0833590661629657  , 0.0248738099570576  , 0.0644356693138675  , 0.433829173573226   , 0.000995279388110205, 0.000995279388110205, 0.000995279388110205, 0.000995279388110205, 0.000995279388110205, 0.995023603059449   , 0.443514199083163   , 0.556485800916838   , 0.143076417061835   , 0.000999062559197379, 0.226995041687631   , 0.0422635693198829  , 0.586665909371454   
#>      history: 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.426514119941294   , 0.0943131877289608  , 0.0246182208061626  , 0.0800749422471209  , 0.374479529276461   , 0.393504866060196   , 0.0833588838083061  , 0.0248737338531357  , 0.0644354261992694  , 0.433827090079093   , 0.000995279386546812, 0.000995279386546812, 0.000995279386546812, 0.000995279386546812, 0.000995279386546812, 0.995023603067266   , 0.443515606717199   , 0.556484393282801   , 0.143079360874281   , 0.000999062558819306, 0.226994163444963   , 0.0422634171888563  , 0.58666399593308
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
#> 1          38          42         23.5             1.000                4
#> 2          39          42         25.5             1.000                4
#> 3          40          42         13.4             0.987                4
#> 4          41          42         25.5             1.000                4
#> 5         136         140         17.0             0.999                4
#> 6         196         203         23.4             1.000                4
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
#> 1 53        cluster_50 
#> 2 179       cluster_179
#> 3 164       cluster_164
#> 4 447       cluster_441
#> 5 593       cluster_592
#> 6 761       cluster_760
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
#>  3 0.000000282  1676   558   355   587     0.750  0.825 0.786
#>  4 0.000000462  1461   392   570   753     0.788  0.719 0.752
#>  5 0.00000208   1457   392   574   753     0.788  0.717 0.751
#>  6 0.00000214   1455   391   576   754     0.788  0.716 0.751
#>  7 0.00000224   1448   360   583   785     0.801  0.713 0.754
#>  8 0.00000237   1423   243   608   902     0.854  0.701 0.770
#>  9 0.00000400   1384   177   647   968     0.887  0.681 0.771
#> 10 0.00000412   1384   175   647   970     0.888  0.681 0.771
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
#> 1           0           1         8.35             0.708 TRUE       false_negat…
#> 2           0           2         8.35             0.708 TRUE       false_negat…
#> 3           4          10        13.6              0.989 FALSE      false_posit…
#> 4           5           7        11.2              0.947 FALSE      false_posit…
#> 5           5          10        13.6              0.989 FALSE      false_posit…
#> 6           6           8        11.2              0.947 FALSE      false_posit…
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
