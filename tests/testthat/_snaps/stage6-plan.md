# print.il_spec() snapshot: empty spec

    Code
      spec <- il_spec()
      print(spec)
    Output
      Linkage Specification
        Comparisons: (none)
        Blocking rules: (none)

# print.il_spec() snapshot: spec with comparisons and blocking

    Code
      spec <- il_block_on(il_block_on(il_compare(il_compare(il_spec(), first_name,
      cl_exact()), surname, cl_jaro_winkler(0.9)), first_name), surname)
      print(spec)
    Output
      Linkage Specification
        Comparisons (2):
          first_name : exact
          surname : jaro_winkler
        Blocking rules (2, OR-ed):
          1. first_name
          2. surname

# print.il_model() snapshot: untrained model

    Code
      print(model)
    Output
      irelink Model
        Status: Untrained
        Link type: dedupe
        Records: 5
        Comparisons: 2
        Blocking rules: 1

# print.il_model() snapshot: trained model

    Code
      print(model)
    Output
      irelink Model
        Status: Trained
        Link type: dedupe
        Records: 6
        Comparisons: 1
        Blocking rules: 1

# summary.il_model() snapshot: trained model

    Code
      summary(model)
    Output
      irelink Model
        Status: Trained
        Link type: dedupe
        Records: 6
        Comparisons: 1
        Blocking rules: 1
      
        Parameters:
          comparisons: # A tibble: 2 x 4
           comparisons:   comparison level         m     u
           comparisons:   <chr>      <chr>     <dbl> <dbl>
           comparisons: 1 first_name match     0.653   0.2
           comparisons: 2 first_name non_match 0.347   0.8
          history: 1                , first_name       , match            , 0.682432432432432
           history: 2               , first_name      , match           , 0.65676738410596
           history: 3                , first_name       , match            , 0.653281533765247
           history: 4                , first_name       , match            , 0.652799474080288
           history: 5                , first_name       , match            , 0.652732644812339
           history: 6                , first_name       , match            , 0.652723376913114

# unit helper print snapshot

    Code
      print(days(30))
    Output
      30 days 
    Code
      print(months(6))
    Output
      6 months 
    Code
      print(years(2))
    Output
      2 years 
    Code
      print(km(10))
    Output
      10 km 
    Code
      print(mi(5))
    Output
      5 mi 

