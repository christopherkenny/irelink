# Fake 20 — Minimal Deduplication Example

A small, hand-crafted dataset of 20 records representing 5 unique
people. Each person has four records with varying levels of corruption:
exact matches, minor typos, and slightly shifted dates of birth.
Designed for quick examples and unit tests.

## Usage

``` r
fake_20
```

## Format

A tibble with 20 rows and 6 columns:

- first_name:

  Character. Given name, sometimes corrupted.

- surname:

  Character. Family name, sometimes corrupted.

- dob:

  Character. Date of birth in `YYYY-MM-DD` format, sometimes shifted by
  one day.

- city:

  Character. City of residence.

- email:

  Character. Email address, sometimes corrupted.

- cluster:

  Integer. Ground-truth entity label (1 to 5).

## See also

[fake_1000](http://christophertkenny.com/irelink/reference/fake_1000.md)
for a larger benchmark dataset.
