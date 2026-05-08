# FEBRL 4b: Record Linkage Duplicate Records

The FEBRL (Freely Extensible Biomedical Record Linkage) dataset 4b
contains 5,000 duplicate records, one for each original in
[febrl4a](http://christophertkenny.com/irelink/reference/febrl4a.md).
Duplicates have been corrupted with typographical errors, missing
values, and transpositions. Ground truth is encoded in `rec_id`: the
base number matches the corresponding original (e.g., `rec-1070-dup-0`
matches `rec-1070-org`).

## Usage

``` r
febrl4b
```

## Format

A tibble with 5,000 rows and 11 columns:

- rec_id:

  Character. Record identifier encoding entity and duplicate status
  (`-dup-0` suffix).

- given_name:

  Character. Given name, sometimes corrupted or missing.

- surname:

  Character. Family name, sometimes corrupted or missing.

- street_number:

  Integer. Street number, sometimes missing.

- address_1:

  Character. Primary address line, sometimes corrupted.

- address_2:

  Character. Secondary address line, often missing.

- suburb:

  Character. Suburb or neighborhood.

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
MIT license. The FEBRL datasets originate from Christen and Churches
(2004) and are widely used as record-linkage benchmarks.

## References

Christen, P. and Churches, T. (2004). Febrl – Freely Extensible
Biomedical Record Linkage. Australian National University.

## See also

[febrl4a](http://christophertkenny.com/irelink/reference/febrl4a.md) for
the corresponding original records.
