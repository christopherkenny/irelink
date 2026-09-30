# il_count_pairs() warns when sampled estimates are unstable

    Code
      result <- il_count_pairs(df, block_on(first_name), con = con,
      record_sample_proportion = 0.5)
    Condition
      Warning:
      Pair counts for "first_name" are estimated from fewer than 1000 sampled pairs and may be unstable.
      i Increase `record_sample_proportion`, or set it to 1 for exact counts.

# il_count_pairs() validates record_sample_proportion

    Code
      il_count_pairs(df, block_on(first_name), con = con, record_sample_proportion = 0)
    Condition
      Error in `il_count_pairs()`:
      ! `record_sample_proportion` must be a single number in (0, 1].

