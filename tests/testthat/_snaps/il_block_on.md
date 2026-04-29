# il_block_on() errors on one-sided formula

    Code
      il_block_on(il_spec(), ~ il_substr(1, 3))
    Condition
      Error in `parse_blocking_cols()`:
      ! Left-hand side of a `~` formula must be a bare column name.

# il_block_on() errors on non-symbol LHS in formula

    Code
      il_block_on(il_spec(), "first_name" ~ il_substr(1, 3))
    Condition
      Error in `parse_blocking_cols()`:
      ! Left-hand side of a `~` formula must be a bare column name.

# il_block_on() errors when formula RHS is not a function

    Code
      il_block_on(il_spec(), first_name ~ "not_a_transform")
    Condition
      Error in `parse_blocking_cols()`:
      ! Right-hand side of `first_name ~ ...` must evaluate to a transform function.

# il_block_on() errors on unnamed list .transform

    Code
      il_block_on(il_spec(), first_name, .transform = list(il_substr(1, 3)))
    Condition
      Error in `validate_transform_arg()`:
      ! `.transform` list must be fully named (one name per column transform).

# il_block_on() errors on list with non-function entries

    Code
      il_block_on(il_spec(), first_name, .transform = list(first_name = "not_a_function"))
    Condition
      Error in `validate_transform_arg()`:
      ! All entries in `.transform` list must be functions.

