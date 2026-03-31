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
           comparisons:   comparison gamma_level     m     u
           comparisons:   <chr>            <int> <dbl> <dbl>
           comparisons: 1 first_name           0 0.252   0.8
           comparisons: 2 first_name           1 0.748   0.2
          history: 1                , 1                , 1                , 1                , first_name       , first_name       , 0                , 1                , 0.232673267326733, 0.767326732673267
           history: 1                , 1                , 2                , 2                , first_name       , first_name       , 0                , 1                , 0.249001403433013, 0.750998596566987
           history: 1                , 1                , 3                , 3                , first_name       , first_name       , 0                , 1                , 0.251242328198734, 0.748757671801266
           history: 1                , 1                , 4                , 4                , first_name       , first_name       , 0                , 1                , 0.251554301316564, 0.748445698683436
           history: 1                , 1                , 5                , 5                , first_name       , first_name       , 0                , 1                , 0.251597818904961, 0.748402181095039
           history: 1                , 1                , 6                , 6                , first_name       , first_name       , 0                , 1                , 0.251603890908476, 0.748396109091524

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

