#' Load a Demo Dataset
#'
#' Returns a built-in demo dataset for experimenting with irelink. The
#' datasets contain synthetic records with deliberate duplicates and
#' typos, mirroring splink's demo data.
#'
#' @param name A character string identifying the demo dataset (e.g.,
#'   `"fake_1000"`).
#'
#' @return A tibble of demo records.
#' @export
#'
#' @examples
#' \dontrun{
#' df <- il_demo("fake_1000")
#' head(df)
#' }
il_demo <- function(name) {
  available <- c("fake_1000", "fake_1000_links")

  if (missing(name)) {
    return(available)
  }

  if (!is.character(name) || length(name) != 1L || !name %in% available) {
    cli::cli_abort(
      c("Unknown demo dataset {.val {name}}.",
        "i" = "Available datasets: {.val {available}}.")
    )
  }

  set.seed(42L)
  first_names <- c(
    "James", "Mary", "Robert", "Patricia", "John", "Jennifer", "Michael",
    "Linda", "David", "Elizabeth", "William", "Barbara", "Richard",
    "Susan", "Joseph", "Jessica", "Thomas", "Sarah", "Christopher",
    "Karen", "Daniel", "Lisa", "Matthew", "Nancy", "Anthony", "Betty",
    "Mark", "Margaret", "Donald", "Sandra", "Steven", "Ashley",
    "Andrew", "Dorothy", "Paul", "Kimberly", "Joshua", "Emily",
    "Kenneth", "Donna"
  )
  surnames <- c(
    "Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia",
    "Miller", "Davis", "Rodriguez", "Martinez", "Hernandez", "Lopez",
    "Gonzalez", "Wilson", "Anderson", "Thomas", "Taylor", "Moore",
    "Jackson", "Martin", "Lee", "Perez", "Thompson", "White",
    "Harris", "Sanchez", "Clark", "Ramirez", "Lewis", "Robinson"
  )
  cities <- c(
    "London", "Manchester", "Birmingham", "Leeds", "Glasgow",
    "Liverpool", "Bristol", "Sheffield", "Edinburgh", "Cardiff"
  )

  n <- 1000L
  ids <- seq_len(n)
  fn <- sample(first_names, n, replace = TRUE)
  sn <- sample(surnames, n, replace = TRUE)
  dobs <- as.character(
    as.Date("1960-01-01") + sample(0:14600, n, replace = TRUE)
  )
  ct <- sample(cities, n, replace = TRUE)
  em <- paste0(
    tolower(substr(fn, 1, 1)), tolower(sn), ids, "@example.com"
  )

  # Introduce typos/corruption in ~10% of records
  corrupt_idx <- sample(n, n %/% 10)
  for (i in corrupt_idx) {
    field <- sample(4L, 1L)
    if (field == 1L) {
      chars <- strsplit(fn[i], "")[[1]]
      if (length(chars) > 2L) {
        pos <- sample(2:length(chars), 1L)
        chars[pos] <- sample(letters, 1L)
        fn[i] <- paste0(chars, collapse = "")
      }
    } else if (field == 2L) {
      chars <- strsplit(sn[i], "")[[1]]
      if (length(chars) > 2L) {
        pos <- sample(2:length(chars), 1L)
        chars[pos] <- sample(letters, 1L)
        sn[i] <- paste0(chars, collapse = "")
      }
    } else if (field == 3L) {
      dobs[i] <- as.character(as.Date(dobs[i]) + sample(-30:30, 1L))
    } else {
      ct[i] <- sample(cities, 1L)
    }
  }

  df <- tibble::tibble(
    unique_id = ids,
    first_name = fn,
    surname = sn,
    dob = dobs,
    city = ct,
    email = em
  )

  if (name == "fake_1000") {
    return(df)
  }

  if (name == "fake_1000_links") {
    split_at <- n %/% 2
    return(list(
      df_a = df[seq_len(split_at), ],
      df_b = df[seq(split_at + 1L, n), ]
    ))
  }
}
