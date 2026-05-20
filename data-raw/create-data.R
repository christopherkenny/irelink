library(readr)
library(stringr)

clean_strings <- function(df) {
  df |>
    dplyr::mutate(dplyr::across(where(is.character), \(x) {
      x |>
        str_trim() |>
        na_if('')
    }))
}

base_url <- 'https://raw.githubusercontent.com/moj-analytical-services/splink_datasets/master/data'

local_path <- '../splink/tests/datasets/fake_1000_from_splink_demos.csv'
fake_1000_path <- paste0(base_url, '/fake_1000.csv')
if (file.exists(local_path)) {
  fake_1000_path <- local_path
}

fake_1000 <- read_csv(fake_1000_path, show_col_types = FALSE) |>
  dplyr::mutate(dob = as.character(dob)) |>
  clean_strings()
usethis::use_data(fake_1000, overwrite = TRUE)

fake_1000_labels <- read_csv(
  paste0(base_url, '/fake_1000_labels.csv'),
  show_col_types = FALSE
)
usethis::use_data(fake_1000_labels, overwrite = TRUE)

febrl4a <- read_csv(
  paste0(base_url, '/febrl/dataset4a.csv'),
  show_col_types = FALSE
) |>
  clean_strings()
usethis::use_data(febrl4a, overwrite = TRUE)

febrl4b <- read_csv(
  paste0(base_url, '/febrl/dataset4b.csv'),
  show_col_types = FALSE
) |>
  clean_strings()
usethis::use_data(febrl4b, overwrite = TRUE)

# Small hardcoded dataset for quick examples and tests
fake_20 <- tibble::tibble(
  first_name = c(
    'John',
    'Jon',
    'Jane',
    'Jane',
    'Bob',
    'Bobby',
    'Alice',
    'Alicia',
    'Tom',
    'Thomas',
    'John',
    'Jon',
    'Jane',
    'Janet',
    'Bob',
    'Robert',
    'Alice',
    'Alison',
    'Tom',
    'Tomas'
  ),
  surname = c(
    'Smith',
    'Smith',
    'Doe',
    'Doe',
    'Jones',
    'Jones',
    'Brown',
    'Brown',
    'White',
    'White',
    'Smith',
    'Smyth',
    'Doe',
    'Doe',
    'Jones',
    'Jones',
    'Brown',
    'Browne',
    'White',
    'White'
  ),
  dob = c(
    '1990-01-01',
    '1990-01-01',
    '1985-06-15',
    '1985-06-15',
    '2000-12-01',
    '2000-12-01',
    '1975-03-22',
    '1975-03-22',
    '1988-07-04',
    '1988-07-04',
    '1990-01-01',
    '1990-01-02',
    '1985-06-15',
    '1985-06-16',
    '2000-12-01',
    '2000-12-02',
    '1975-03-22',
    '1975-03-23',
    '1988-07-04',
    '1988-07-05'
  ),
  city = c(
    'London',
    'London',
    'Paris',
    'Paris',
    'Berlin',
    'Berlin',
    'Rome',
    'Rome',
    'Madrid',
    'Madrid',
    'London',
    'London',
    'Paris',
    'Paris',
    'Berlin',
    'Berlin',
    'Rome',
    'Rome',
    'Madrid',
    'Madrid'
  ),
  email = c(
    'john@example.com',
    'jon@example.com',
    'jane@example.com',
    'jane@example.com',
    'bob@example.com',
    'bobby@example.com',
    'alice@example.com',
    'alicia@example.com',
    'tom@example.com',
    'thomas@example.com',
    'john@example.com',
    'jon@example.com',
    'jane@example.com',
    'janet@example.com',
    'bob@example.com',
    'robert@example.com',
    'alice@example.com',
    'alison@example.com',
    'tom@example.com',
    'tomas@example.com'
  ),
  cluster = rep(1:5, each = 4)
)
usethis::use_data(fake_20, overwrite = TRUE)
