# Manual review plan

The package has ~100 exported functions across the core R implementation, testthat coverage, and 7 vignettes.
It layers a Fellegi-Sunter probabilistic record linkage engine on top of a DBI/DuckDB-oriented SQL backend.

The point of this plan is to divide the package into reviewable surfaces.
Each chunk names the main files, the part of the package surface covered, and the nearest neighboring chunks so the boundaries are clear.

## Chunk 1 -- Foundations

Files: `il_spec.R`, `il_model.R`, `utils-classes.R`, `utils-data.R`, `utils-register.R`, `il_compare.R`, `il_block_on.R`

The spec/model object lifecycle, class constructors, and how comparisons and blocking rules get added.
This chunk establishes the package's main nouns: specs, models, registered data, comparisons, blocking rules, and link modes.

Include here:

- object structure and class invariants
- how `il_compare()` and `il_block_on()` mutate or extend a spec
- how data inputs become model-owned database tables
- dedupe, link, and link-and-dedupe setup

Leave for later chunks:

- details of comparison-level SQL generation
- EM fitting and scoring
- cleanup behavior after tables already exist

## Chunk 2 -- Comparison layers

Files: all `cl_*.R` files plus `utils-comparison-helpers.R` and `utils-unit-helpers.R`

Repetitive -- establish a pattern on a few, scan the rest.
The critical question is whether SQL generation is consistent and correct across similarity types and whether each constructor creates comparison levels with the same internal shape.

Cover:

- primitive levels such as exact, string similarity, numeric difference, date difference, time difference, distance, arrays, and custom SQL
- structural levels such as null, else, nested levels, and boolean composition
- domain bundles in `cl_domain.R`
- unit helpers used by date/time/distance comparisons

This chunk owns comparison-level semantics.
Chunk 3 owns transforms applied before comparisons.
Chunk 7 owns shared SQL infrastructure.

## Chunk 3 -- Column transforms

Files: `il_transform.R`, `il_column_transforms.R`

How transforms compose and emit SQL.
This covers transform chains and exported transform helpers such as substring, regex extraction, null handling, casting, date parsing, timestamp parsing, and array element extraction.

Include the use of transforms inside `il_compare()` and `il_block_on()` only as needed to understand the transform contract.
Do not fold general comparison SQL review into this chunk.

## Chunk 4 -- EM & parameter estimation

Files: `il_estimate_em.R`, `il_estimate_u.R`, `il_estimate_prior.R`, `il_estimate_m_from_column.R`, `il_estimate_m_from_labels.R`, `il_priors.R`, `il_parameters.R`, `il_training_history.R`, `il_register_tf.R`, `utils-em.R`, `utils-tf.R`, `utils-dependency-aware.R`

The statistical core -- convergence logic, E/M-step correctness, TF-adjustment interactions, custom priors, fixed constraints, and dependency-aware scoring.

This chunk is about fitted parameter state.
It should be kept separate from prediction mechanics even though prediction uses the fitted parameters.
Highest risk.

## Chunk 5 -- Prediction & scoring

Files: `predict.R`, `il_find_matches.R`, `il_deterministic_link.R`, `il_compare_records.R`, `il_score_missing_edges.R`, `il_waterfall.R`, `il_weights.R`, `utils-scoring.R`

How gamma vectors become probabilities, incremental matching, deterministic fallback, per-record comparison, missing-edge scoring, waterfall decomposition, and exposed weight summaries.

This chunk starts after a model already has parameters.
Do not include EM updates here except where scoring code consumes EM output.

## Chunk 6 -- Clustering

Files: `il_cluster.R`, `il_graph_metrics.R`, `utils-cc.R`

Connected-components and best-link with dataset constraints.
The iterative SQL connected-components implementation is a known complexity area.

Include graph summaries here because they sit on the same pairwise edge representation as clustering.
Cluster evaluation belongs in Chunk 8.

## Chunk 7 -- Database layer

Files: `utils-db.R`, `utils-sql.R`, `il_cleanup.R`

Multi-backend compatibility, table lifecycle, generated SQL fragments, temporary table cleanup, and lazy eval via dbplyr.

This is the shared infrastructure layer.
Review it after seeing at least one caller from comparisons, EM, prediction, and clustering, because many helpers only make sense from their call sites.

## Chunk 8 -- Evaluation & diagnostics

Files: `il_accuracy.R`, `il_roc.R`, `il_precision_recall.R`, `il_comparator_score.R`, `il_confusion_matrix.R`, `il_cluster_confusion_matrix.R`, `il_completeness.R`, `il_comparison_vectors.R`, `il_unlinkables.R`, `il_largest_blocks.R`, `il_suggest_blocking.R`, `il_errors.R`, `il_profile.R`, `il_string_similarity.R`, `utils-evaluation.R`

Scan for consistency in how ground truth labels are handled and whether metrics are computed correctly.
This chunk includes both post-model evaluation and pre-model diagnostics.

Boundary:

- blocking suggestion and largest-block summaries live here as diagnostics
- blocked-pair construction itself belongs to Chunk 7
- graph metrics live with clustering in Chunk 6

## Chunk 9 -- Visualization & I/O

Files: `autoplot.R`, `il_tf_chart.R`, `il_phonetic.R`, `il_save.R`

Low risk relative to EM and scoring, but useful to keep separate because these functions are mostly presentation and persistence.

Include:

- autoplot methods
- TF and phonetic charts
- phonetic helpers
- save/load behavior and JSON/RDS boundaries

## Chunk 10 -- Integration tests & vignettes

Files: integration test files, `README.Rmd`, `_pkgdown.yml`, and `vignettes/`

Sanity check that the full pipeline narrative holds together.
This pass is for cross-chunk coherence: whether the examples describe the same package that the implementation provides, and whether the public story has drifted from the actual API.
