# irelink: Fast Probabilistic Record Linkage

Performs fast, scalable probabilistic record linkage and deduplication
using the Fellegi-Sunter model. Records lacking a shared unique
identifier are compared across configurable dimensions using exact,
fuzzy, and distance-based comparisons, with model parameters estimated
via unsupervised Expectation-Maximization. Multiple SQL backends are
supported through 'DBI', enabling execution from laptop-scale ('DuckDB')
through to distributed engines. This package is a translation of the
Python 'splink' library by Linacre et al. (2022)
[doi:10.23889/ijpds.v7i3.1794](https://doi.org/10.23889/ijpds.v7i3.1794)
into idiomatic R.

## Package options

- `irelink.show_sql`: If `TRUE`, print the SQL that
  [`predict()`](https://rdrr.io/r/stats/predict.html),
  [`il_estimate_u()`](http://christophertkenny.com/irelink/reference/il_estimate_u.md),
  and
  [`il_estimate_prior()`](http://christophertkenny.com/irelink/reference/il_estimate_prior.md)
  send to the database, as messages. This covers the same queries that
  `profile_sql = TRUE` times. Defaults to `FALSE`.

## See also

Useful links:

- <http://christophertkenny.com/irelink/>

- <https://github.com/christopherkenny/irelink>

- Report bugs at <https://github.com/christopherkenny/irelink/issues>

## Author

**Maintainer**: Christopher T. Kenny <ctkenny@proton.me>
([ORCID](https://orcid.org/0000-0002-9386-6860)) \[copyright holder\]

Authors:

- Christopher T. Kenny <ctkenny@proton.me>
  ([ORCID](https://orcid.org/0000-0002-9386-6860)) \[copyright holder\]

Other contributors:

- Robin Linacre (Lead author of splink, the Python package this is
  derived from) \[copyright holder\]

- Sam Lindsay (Author of splink) \[copyright holder\]

- Theodore Manassis (Author of splink) \[copyright holder\]

- Tom Hepworth (Author of splink) \[copyright holder\]

- Andy Bond (Author of splink) \[copyright holder\]

- Ross Kennedy (Author of splink) \[copyright holder\]

- UK Ministry of Justice (Copyright holder of splink) \[copyright
  holder\]
