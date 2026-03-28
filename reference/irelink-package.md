# irelink: Fast Probabilistic Record Linkage

Performs fast, scalable probabilistic record linkage and deduplication
using the Fellegi-Sunter model. Records lacking a shared unique
identifier are compared across configurable dimensions using exact,
fuzzy, and distance-based comparisons, with model parameters estimated
via unsupervised Expectation-Maximisation. Multiple SQL backends are
supported through 'DBI', enabling execution from laptop-scale ('DuckDB')
through to distributed engines. This package is a translation of the
Python 'splink' library by Linacre et al. into idiomatic R.

## See also

Useful links:

- <http://christophertkenny.com/irelink/>

## Author

**Maintainer**: Christopher T. Kenny <ctkenny@proton.me>
([ORCID](https://orcid.org/0000-0002-9386-6860))

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
