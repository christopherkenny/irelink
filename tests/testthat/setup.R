# setup.R — shared test configuration for irelink

#' Create a test database connection (DuckDB preferred, SQLite fallback)
test_con <- function() {
 if (requireNamespace('duckdb', quietly = TRUE)) {
 DBI::dbConnect(duckdb::duckdb())
 } else {
 DBI::dbConnect(RSQLite::SQLite(), ':memory:')
 }
}

#' Disconnect a test database connection
test_discon <- function(con) {
 if (inherits(con, 'duckdb_connection')) {
 DBI::dbDisconnect(con, shutdown = TRUE)
 } else {
 DBI::dbDisconnect(con)
 }
}
