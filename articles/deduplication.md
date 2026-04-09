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
#>      comparisons:  1 first_name           0 0.427  0.974  
#>      comparisons:  2 first_name           1 0.0942 0.0153 
#>      comparisons:  3 first_name           2 0.0246 0.00171
#>      comparisons:  4 first_name           3 0.0800 0.00285
#>      comparisons:  5 first_name           4 0.374  0.00663
#>      comparisons:  6 surname              0 0.394  0.973  
#>      comparisons:  7 surname              1 0.0834 0.0136 
#>      comparisons:  8 surname              2 0.0248 0.00167
#>      comparisons:  9 surname              3 0.0644 0.00247
#>      comparisons: 10 surname              4 0.434  0.00914
#>      comparisons: # ℹ 13 more rows
#>     history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996443443106585, 0.000996443443106585, 0.000996443443106585, 0.000996443443106585, 0.996014226227574   , 0.148248181455931   , 0.0954618888448685  , 0.0493670391675382  , 0.0836325819650821  , 0.623290308566581   , 0.000998425228996166, 0.000998425228996166, 0.260259995186641   , 0.0961457097100169  , 0.0204069615864807  , 0.621190483058869   , 0.481439294533163   , 0.518560705466837   , 0.140116126842998   , 0.000999108482727721, 0.241973826082297   , 0.0504471492494204  , 0.566463789342557   
#>      history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996403340585212, 0.000996403340585212, 0.000996403340585212, 0.000996403340585212, 0.996014386637659   , 0.188527204803493   , 0.0995480432730567  , 0.0477795833548952  , 0.082850980504014   , 0.581294188064541   , 0.000998436255423297, 0.000998436255423297, 0.283374619132725   , 0.100754948852233   , 0.0240287319046855  , 0.58984482759951    , 0.510828639163379   , 0.489171360836621   , 0.194772875771685   , 0.000999098403093552, 0.2330135860109     , 0.0459198237241668  , 0.525294616090155   
#>      history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996398237854748, 0.000996398237854748, 0.000996398237854748, 0.000996398237854748, 0.996014407048581   , 0.198469393063984   , 0.0986670367855084  , 0.047194541926413   , 0.0818294136540296  , 0.573839614570065   , 0.000998564514202807, 0.000998564514202807, 0.287372328869946   , 0.100336134460939   , 0.0250115230536633  , 0.585282884587046   , 0.515615319173991   , 0.484384680826009   , 0.205259596779481   , 0.000999097120495772, 0.229974149161449   , 0.0453155616797837  , 0.518451595258791   
#>      history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996397204302714, 0.000996397204302714, 0.000996397204302714, 0.000996397204302714, 0.996014411182789   , 0.200551114779665   , 0.0984454464433315  , 0.0470719765447491  , 0.0816156699078723  , 0.572315792324382   , 0.000998589665936389, 0.000998589665936389, 0.288321821364636   , 0.100206206103525   , 0.025234724378417   , 0.584240068821549   , 0.516667963569332   , 0.483332036430668   , 0.207388013154976   , 0.000999096860705906, 0.229356853865142   , 0.0451931730027846  , 0.517062863116391   
#>      history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996396989174573, 0.000996396989174573, 0.000996396989174573, 0.000996396989174573, 0.996014412043302   , 0.200985674800717   , 0.0983984952688748  , 0.0470464061367214  , 0.0815710817273459  , 0.571998342066341   , 0.000998594807456205, 0.000998594807456205, 0.288528230229341   , 0.100177158138709   , 0.0252818589125776  , 0.584015563104461   , 0.516890918536279   , 0.483109081463721   , 0.207831148196413   , 0.000999096806632032, 0.229228337574333   , 0.0451676972011808  , 0.516773720221441   
#>      history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996396944172507, 0.000996396944172507, 0.000996396944172507, 0.000996396944172507, 0.99601441222331    , 0.201076613773761   , 0.0983886525215082  , 0.0470410556435472  , 0.081561750990067   , 0.571931927071117   , 0.000998595879797582, 0.000998595879797582, 0.288571867382837   , 0.100170990724173   , 0.0252917047536016  , 0.583968245379793   , 0.51693772423105    , 0.48306227576895    , 0.207923852114197   , 0.000999096795320464, 0.229201452013702   , 0.0451623679139406  , 0.51671323116284    
#>      history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996396934749515, 0.000996396934749515, 0.000996396934749515, 0.000996396934749515, 0.996014412261002   , 0.201095656697384   , 0.0983865908766778  , 0.0470399352597265  , 0.0815597970540805  , 0.571918020112131   , 0.000998596104220444, 0.000998596104220444, 0.288581028417165   , 0.100169695303487   , 0.0252937622681135  , 0.583958321802793   , 0.516947532252062   , 0.483052467747938   , 0.207943263650524   , 0.000999096792951932, 0.229195822359455   , 0.0451612520099298  , 0.516700565187139   
#>      history: 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , 8                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.000996396932776076, 0.000996396932776076, 0.000996396932776076, 0.000996396932776076, 0.996014412268896   , 0.201099644861822   , 0.098386159090302   , 0.0470397006191244  , 0.0815593878353221  , 0.57191510759343    , 0.000998596151217111, 0.000998596151217111, 0.288582948288949   , 0.100169423833016   , 0.0252941927232334  , 0.583956242852368   , 0.516949586661127   , 0.483050413338873   , 0.207947328980825   , 0.000999096792455895, 0.22919464334748    , 0.0451610183081467  , 0.516697912571093   
#>      history: 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , 1                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.148516104709501   , 0.111446689929805   , 0.0347283488905229  , 0.114367793667476   , 0.590941062802695   , 0.162493208284815   , 0.102745565230625   , 0.0362684675268318  , 0.0836323968485835  , 0.614860362109145   , 0.000995425129340201, 0.000995425129340201, 0.000995425129340201, 0.000995425129340201, 0.000995425129340201, 0.995022874353299   , 0.449300232328054   , 0.550699767671946   , 0.145646109410861   , 0.000999097799590787, 0.232208188917347   , 0.0455885184033093  , 0.575558085468891   
#>      history: 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , 2                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.385063304998107   , 0.10056844514788    , 0.0264563472719774  , 0.0859315576200949  , 0.40198034496194    , 0.350908465810347   , 0.0890192578586047  , 0.0265997659518186  , 0.0685874626997576  , 0.464885047679473   , 0.000995298817770819, 0.000995298817770819, 0.000995298817770819, 0.000995298817770819, 0.000995298817770819, 0.995023505911146   , 0.421051820765706   , 0.578948179234294   , 0.141225631477131   , 0.000999067257763771, 0.22946270599229    , 0.0425952977108366  , 0.585717297561978   
#>      history: 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , 3                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.42332664969644    , 0.094798886265656   , 0.0247674196122453  , 0.0805445658449321  , 0.376562478580727   , 0.389820957343048   , 0.0839918429675642  , 0.0249856841808508  , 0.0647846786742139  , 0.436416836834323   , 0.000995280930954591, 0.000995280930954591, 0.000995280930954591, 0.000995280930954591, 0.000995280930954591, 0.995023595345227   , 0.441481830666825   , 0.558518169333175   , 0.142360370856452   , 0.000999062932299916, 0.227415521892966   , 0.0423016815674139  , 0.586923362750868   
#>      history: 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , 4                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.426565095354327   , 0.0942459850659577  , 0.0246158625224077  , 0.0800835121713274  , 0.37448954488598    , 0.393352405151157   , 0.0834865062718531  , 0.0248429094848061  , 0.0644239110014961  , 0.433894268090688   , 0.000995279344537548, 0.000995279344537548, 0.000995279344537548, 0.000995279344537548, 0.000995279344537548, 0.995023603277312   , 0.443705150829332   , 0.556294849170668   , 0.143151936574322   , 0.00099906254866029 , 0.227015771779001   , 0.042248984941473   , 0.586584244156543   
#>      history: 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , 5                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.426831480340486   , 0.09420237405144    , 0.0246034532423381  , 0.0800443908184214  , 0.374318301547314   , 0.39365063784738    , 0.0834476881892193  , 0.0248317905974874  , 0.0643939263730975  , 0.433675956992816   , 0.000995279198681459, 0.000995279198681459, 0.000995279198681459, 0.000995279198681459, 0.000995279198681459, 0.995023604006593   , 0.443890051641432   , 0.556109948358568   , 0.143299191227801   , 0.000999062513388197, 0.226961525673416   , 0.0422408115917126  , 0.586499408993682   
#>      history: 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , 6                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.426854643542378   , 0.0941991036373924  , 0.0246024116945086  , 0.0800408348470069  , 0.374303006278715   , 0.393676829875188   , 0.0834450433406867  , 0.0248309221174572  , 0.0643913835887097  , 0.433655821077958   , 0.000995279184356059, 0.000995279184356059, 0.000995279184356059, 0.000995279184356059, 0.000995279184356059, 0.99502360407822    , 0.443905306140964   , 0.556094693859036   , 0.143320769346094   , 0.000999062509923912, 0.226954617885102   , 0.0422396805218272  , 0.586485869737053   
#>      history: 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 9                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , 7                   , first_name          , first_name          , first_name          , first_name          , first_name          , surname             , surname             , surname             , surname             , surname             , dob                 , dob                 , dob                 , dob                 , dob                 , dob                 , city                , city                , email               , email               , email               , email               , email               , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0                   , 1                   , 2                   , 3                   , 4                   , 5                   , 0                   , 1                   , 0                   , 1                   , 2                   , 3                   , 4                   , 0.42685678437544    , 0.0941988623737689  , 0.0246023198243957  , 0.0800404898109236  , 0.374301543615471   , 0.393679260822502   , 0.0834448856325725  , 0.024830852398063   , 0.0643911571454205  , 0.433653844001442   , 0.000995279182866978, 0.000995279182866978, 0.000995279182866978, 0.000995279182866978, 0.000995279182866978, 0.995023604085665   , 0.4439066068595     , 0.5560933931405     , 0.143323659953077   , 0.000999062509563811, 0.226953757322226   , 0.0422395327876673  , 0.586483987427465
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
#> 1 144       cluster_142
#> 2 819       cluster_814
#> 3 147       cluster_142
#> 4 68        cluster_63 
#> 5 379       cluster_372
#> 6 477       cluster_476
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
#>  6 0.00000220   1450   361   581   784     0.801  0.714 0.755
#>  7 0.00000221   1425   244   606   901     0.854  0.702 0.770
#>  8 0.00000236   1423   243   608   902     0.854  0.701 0.770
#>  9 0.00000399   1384   177   647   968     0.887  0.681 0.771
#> 10 0.00000427   1384   152   647   993     0.901  0.681 0.776
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
#> 3           4           6         9.59             0.851 FALSE      false_posit…
#> 4           4          10        13.6              0.990 FALSE      false_posit…
#> 5           5           6         9.59             0.851 FALSE      false_posit…
#> 6           5           7        11.3              0.950 FALSE      false_posit…
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
