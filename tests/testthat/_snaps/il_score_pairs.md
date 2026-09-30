# il_score_pairs() errors without term-frequency tables

    Code
      il_score_pairs(model, fake_1000[1, ], fake_1000[2, ], con = other)
    Condition
      Error in `il_score_pairs()`:
      ! Term-frequency adjustments for first_name need the model's term-frequency tables.
      i Attach the model's data with `il_attach()` or register tables with `il_register_tf()`, then score with the model's connection.

# il_score_pairs() errors on missing columns

    Code
      il_score_pairs(model, fake_1000[1, ], data.frame(first_name = "a"))
    Condition
      Error in `il_score_pairs()`:
      ! Columns surname and dob required by the model spec are missing from the records.

