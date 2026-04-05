# cl_array_min_distance() rejects out-of-range jaro_winkler thresholds

    Code
      cl_array_min_distance("jaro_winkler", 1.5)
    Condition
      Error in `cl_array_min_distance()`:
      ! Jaro-Winkler thresholds must be between 0 and 1.

# cl_array_min_distance() rejects negative levenshtein thresholds

    Code
      cl_array_min_distance("levenshtein", -1)
    Condition
      Error in `cl_array_min_distance()`:
      ! Levenshtein thresholds must be non-negative.

# cl_array_min_distance() rejects empty thresholds

    Code
      cl_array_min_distance("jaro_winkler")
    Condition
      Error in `cl_array_min_distance()`:
      ! `...` must include at least one threshold.

