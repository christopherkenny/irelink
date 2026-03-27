# Load a Demo Dataset

Returns a built-in demo dataset for experimenting with irelink. The
datasets contain synthetic records with deliberate duplicates and typos,
mirroring splink's demo data.

## Usage

``` r
il_demo(name)
```

## Arguments

- name:

  A character string identifying the demo dataset (e.g., `"fake_1000"`).

## Value

A tibble of demo records.

## Examples

``` r
il_demo()
#> [1] "fake_1000"       "fake_1000_links" "fake_20"        
df <- il_demo("fake_20")
head(df)
#> # A tibble: 6 × 6
#>   unique_id first_name surname dob        city   email            
#>       <int> <chr>      <chr>   <chr>      <chr>  <chr>            
#> 1         1 John       Smith   1990-01-01 London john@example.com 
#> 2         2 Jon        Smith   1990-01-01 London jon@example.com  
#> 3         3 Jane       Doe     1985-06-15 Paris  jane@example.com 
#> 4         4 Jane       Doe     1985-06-15 Paris  jane@example.com 
#> 5         5 Bob        Jones   2000-12-01 Berlin bob@example.com  
#> 6         6 Bobby      Jones   2000-12-01 Berlin bobby@example.com
```
