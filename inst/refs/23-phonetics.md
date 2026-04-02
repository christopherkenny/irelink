# Phonetic Algorithms for Record Linkage

## Research Summary

### What splink does

Splink (Python) supports three phonetic algorithms:

1. **Soundex** — 4-character code (letter + 3 digits). Groups similar-sounding
   names: Smith = Smyth (S530), Robert = Rupert (R163).
2. **Metaphone** — Variable-length code. Improved over Soundex with better
   consonant-cluster handling.
3. **Double Metaphone** — Two codes per word (primary + alternate pronunciation).
   Handles more languages/dialects than Metaphone.

Splink implements phonetics as **Python-side pre-computation**: users derive
phonetic columns with the `phonetics` Python package *before* importing data.
The pre-computed columns are used via `ArrayIntersectLevel` for comparison
and equality joins for blocking. Only the Spark backend has native SQL UDFs
(Dmetaphone, DmetaphoneAlt registered from a JAR).

### What irelink does differently

We push phonetic computation into SQL so users never materialise data:
- **DuckDB**: `il_soundex` registered as a `CREATE MACRO` at connection time.
  DuckDB has no native phonetic functions or fuzzystrmatch extension.
- **PostgreSQL**: native `soundex()`, `metaphone(text, max_length)`,
  `dmetaphone(text)` from the `fuzzystrmatch` extension.
- **SQLite**: not supported (no phonetic SQL functions).

Phonetic transforms plug into the existing `transform` argument on
`il_compare()` and the new `.transform` argument on `il_block_on()` /
`block_on()`.

### SQL availability matrix

| Function        | DuckDB            | PostgreSQL          | SQLite |
|-----------------|-------------------|---------------------|--------|
| `il_soundex`    | ✓ (SQL macro)     | ✓ (`soundex()`)     | ✗      |
| `il_metaphone`  | ✗                 | ✓ (`metaphone()`)   | ✗      |
| `il_dmetaphone` | ✗                 | ✓ (`dmetaphone()`)  | ✗      |

### Usage examples

```r
# Block on soundex of first_name (DuckDB or PostgreSQL)
spec <- il_spec() |>
  il_block_on(first_name, .transform = il_soundex)

# Compare with soundex transform
spec <- il_spec() |>
  il_compare(first_name, cl_exact(), transform = il_soundex)

# Training-time blocking
model <- il_estimate_em(model, block_on(first_name, .transform = il_soundex))

# PostgreSQL: metaphone and double metaphone also available
spec <- il_spec() |>
  il_block_on(surname, .transform = il_dmetaphone)
```

### DuckDB Soundex macro

DuckDB lacks native phonetic functions and backreference regex (`\1`), so
the macro uses `translate()` for letter→code mapping, nested `replace()` for
adjacent-duplicate removal, and string slicing.

The implementation is a faithful Soundex except for the "H/W separator" rule
(standard: two letters with the same code separated by H or W collapse to
one). This edge case does not affect blocking correctness — names still
receive the *same* code consistently.

### References

- Splink phonetic docs: `docs/topic_guides/comparisons/phonetic.md`
- Splink feature engineering: `docs/topic_guides/data_preparation/feature_engineering.md`
- PostgreSQL fuzzystrmatch: https://www.postgresql.org/docs/current/fuzzystrmatch.html
- Soundex algorithm: https://en.wikipedia.org/wiki/Soundex
