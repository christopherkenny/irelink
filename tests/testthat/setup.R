# setup.R — shared test configuration for irelink
#
# This file is sourced by testthat before any test files run.
# It defines the current sprint level and a skip helper so that
# tests for not-yet-implemented sprints are automatically skipped.

# Current implementation sprint. Increase as sprints are completed.
# Sprint 0 means nothing is implemented yet (all tests skip).
current_sprint <- 10L

#' Skip a test if the current sprint has not reached the required level
#'
#' @param sprint Integer. The sprint number that must be completed
#'   for this test to run. For example, `skip_if_sprint_lt(3)` will
#'   skip unless `current_sprint >= 3`.
skip_if_sprint_lt <- function(sprint) {
  testthat::skip_if(
    current_sprint < sprint,
    message = paste0("Sprint ", sprint, " not yet implemented (current: ", current_sprint, ")")
  )
}
