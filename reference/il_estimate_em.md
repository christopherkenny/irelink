# Train Parameters via Expectation-Maximization

Runs the EM algorithm under a blocking rule to learn m and u parameters
from unlabeled data. Multiple calls with different blocking rules can be
chained to train on complementary subsets of record pairs — each call
updates the model cumulatively.

## Usage

``` r
il_estimate_em(
  model,
  blocking,
  convergence = 1e-05,
  fix_u = TRUE,
  fix_m = FALSE,
  max_iterations = 100L,
  fix_prior = FALSE,
  estimate_without_tf = TRUE,
  derive_prior = FALSE,
  estimator_mode = c("independent", "dependency-aware"),
  ...
)
```

## Arguments

- model:

  An `il_model` object (piped in).

- blocking:

  A blocking rule created by
  [`block_on()`](http://christophertkenny.com/irelink/reference/block_on.md).

- convergence:

  A numeric convergence tolerance. The EM loop stops when the largest
  change in any updated parameter is below this value. Defaults to
  `1e-5`.

- fix_u:

  Logical. If `TRUE` (the default), hold u parameters fixed during EM —
  only m is updated. Set to `FALSE` to also estimate u. Only supported
  with `estimator_mode = "independent"`.

- fix_m:

  Logical. If `TRUE`, hold m parameters fixed during EM. Defaults to
  `FALSE`. At least one of `fix_u` and `fix_m` must be `FALSE`,
  otherwise the algorithm cannot learn anything. Only supported with
  `estimator_mode = "independent"`.

- max_iterations:

  Maximum number of EM iterations. Defaults to `100L`. The loop stops
  early when convergence is reached.

- fix_prior:

  Logical. If `TRUE`, hold the prior (probability that two random
  records match) fixed during EM iterations. Defaults to `FALSE`.

- estimate_without_tf:

  Logical. If `TRUE` (the default), EM runs on aggregated gamma-pattern
  counts (fast, but ignores per-pair term frequency variation). If
  `FALSE`, EM runs on individual pairs and incorporates per-pair TF
  adjustments in the E-step, matching splink's default behavior. Only
  matters when at least one comparison has `term_frequency = TRUE`. Only
  supported with `estimator_mode = "independent"`.

- derive_prior:

  Logical. If `TRUE`, derive the prior from the trained parameter values
  after EM completes and store it in the model. Defaults to `FALSE`.
  Only supported with `estimator_mode = "independent"`.

- estimator_mode:

  Estimator to use. `"independent"` keeps the conditionally independent
  Fellegi-Sunter EM estimator. `"dependency-aware"` fits log-linear
  matched and unmatched comparison-pattern distributions.

- ...:

  Reserved for future options.

## Value

An updated `il_model` with trained m and u parameters.

## Examples

``` r
df <- data.frame(
  unique_id = 1:20,
  first_name = c(
    'John', 'Jon', 'Jane', 'Jane', 'Bob',
    'Bobby', 'Alice', 'Alicia', 'Tom', 'Thomas',
    'John', 'Jon', 'Jane', 'Janet', 'Bob',
    'Robert', 'Alice', 'Alison', 'Tom', 'Tomas'
  ),
  surname = c(
    'Smith', 'Smith', 'Doe', 'Doe', 'Jones',
    'Jones', 'Brown', 'Brown', 'White', 'White',
    'Smith', 'Smyth', 'Doe', 'Doe', 'Jones',
    'Jones', 'Brown', 'Browne', 'White', 'White'
  ),
  dob = c(
    '1990-01-01', '1990-01-01', '1985-06-15', '1985-06-15',
    '2000-12-01', '2000-12-01', '1975-03-22', '1975-03-22',
    '1988-07-04', '1988-07-04', '1990-01-01', '1990-01-02',
    '1985-06-15', '1985-06-16', '2000-12-01', '2000-12-02',
    '1975-03-22', '1975-03-23', '1988-07-04', '1988-07-05'
  ),
  city = c(
    'London', 'London', 'Paris', 'Paris', 'Berlin',
    'Berlin', 'Rome', 'Rome', 'Madrid', 'Madrid',
    'London', 'London', 'Paris', 'Paris', 'Berlin',
    'Berlin', 'Rome', 'Rome', 'Madrid', 'Madrid'
  ),
  email = c(
    'john@example.com', 'jon@example.com', 'jane@example.com',
    'jane@example.com', 'bob@example.com', 'bobby@example.com',
    'alice@example.com', 'alicia@example.com', 'tom@example.com',
    'thomas@example.com', 'john@example.com', 'jon@example.com',
    'jane@example.com', 'janet@example.com', 'bob@example.com',
    'robert@example.com', 'alice@example.com', 'alison@example.com',
    'tom@example.com', 'tomas@example.com'
  )
)
con <- DBI::dbConnect(duckdb::duckdb())
spec <- il_spec() |>
  il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(surname, cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(dob, cl_exact()) |>
  il_block_on(surname) |>
  il_block_on(first_name)
model <- il_model(df, spec = spec, con = con)
model <- il_estimate_u(model)

model <- il_estimate_em(model, block_on(surname))
#> EM trained: first_name and dob | skipped (blocked on): surname
DBI::dbDisconnect(con, shutdown = TRUE)
```
