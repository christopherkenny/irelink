# FEBRL 4a — Record Linkage Original Records

The FEBRL (Freely Extensible Biomedical Record Linkage) dataset 4a
contains 5,000 original records. It is designed to be linked against
[febrl4b](http://christophertkenny.com/irelink/reference/febrl4b.md),
which contains one duplicate record per original. Ground truth is
encoded in `rec_id`: records sharing the same base ID (e.g.,
`rec-1070-org` and `rec-1070-dup-0`) refer to the same entity.

## Usage

``` r
febrl4a
```

## Format

A tibble with 5,000 rows and 11 columns:

- rec_id:

  Character. Record identifier encoding entity and origin (`-org`
  suffix).

- given_name:

  Character. Given name, sometimes missing.

- surname:

  Character. Family name, sometimes missing.

- street_number:

  Integer. Street number, sometimes missing.

- address_1:

  Character. Primary address line, sometimes missing.

- address_2:

  Character. Secondary address line, often missing.

- suburb:

  Character. Suburb or neighbourhood.

- postcode:

  Integer. Postal code.

- state:

  Character. Australian state abbreviation.

- date_of_birth:

  Integer. Date of birth as `YYYYMMDD` integer, sometimes missing.

- soc_sec_id:

  Integer. Social security identifier.

## Source

Distributed via the splink datasets repository
(<https://github.com/moj-analytical-services/splink_datasets>) under the
MIT licence. The FEBRL datasets originate from Christen and Churches
(2004) and are widely used as record-linkage benchmarks.

## References

Christen, P. and Churches, T. (2004). Febrl – Freely Extensible
Biomedical Record Linkage. Australian National University.

## See also

[febrl4b](http://christophertkenny.com/irelink/reference/febrl4b.md) for
the corresponding duplicate records.
