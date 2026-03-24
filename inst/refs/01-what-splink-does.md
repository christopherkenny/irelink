# What splink Does

This document summarizes the goals, scope, architecture, and notable features of
[splink](https://github.com/moj-analytical-services/splink) (v4.0.16), the
Python probabilistic record linkage package that irelink translates into R.

## Overview

Splink is a production-grade library for **probabilistic record linkage**
(entity resolution). It identifies and links duplicate or related records across
one or more datasets that lack a shared unique identifier. The statistical
foundation is the **Fellegi-Sunter model** of record linkage, which uses Bayesian
reasoning to estimate the probability that two records refer to the same entity.

Key selling points:

- **Speed**: ~1 million records linked on a laptop in ~1 minute (DuckDB backend).
- **Accuracy**: Term frequency adjustments and a rich library of fuzzy matching
  functions.
- **Scalability**: From laptop (DuckDB/SQLite) to cluster (Spark) to serverless
  (AWS Athena) to enterprise RDBMS (PostgreSQL).
- **Unsupervised**: No labelled training data required; uses Expectation-Maximisation.
- **Visualisation**: Interactive Altair (Vega-Lite) charts for model diagnostics.

## Scope

Splink covers the full record linkage pipeline:

| Stage | What it does |
|---|---|
| **Configuration** | Declare link type, comparisons, blocking rules, and model parameters via `SettingsCreator`. |
| **Blocking** | Reduce the O(n²) comparison space using deterministic rules (exact match, custom SQL, salted, exploding). |
| **Comparison** | Evaluate similarity on each column via comparison levels (exact, Jaro-Winkler, Levenshtein, date difference, geographic distance, etc.). |
| **Training** | Estimate model parameters: prior probability, M parameters (match distribution), and U parameters (non-match distribution) via EM or labelled data. |
| **Prediction** | Apply Bayes' theorem to compute match probabilities and match weights for every candidate pair. |
| **Clustering** | Convert pairwise predictions to cluster assignments via connected-components graph algorithms (igraph). |
| **Evaluation** | Compute precision, recall, and F-score against a gold-standard dataset. |
| **Visualisation** | Interactive charts: match weights, M/U parameters, waterfall, comparison viewer, cluster studio. |

Three link types are supported:

- `dedupe_only` — find duplicates within a single dataset.
- `link_only` — link records across two or more datasets.
- `link_and_dedupe` — both simultaneously.

## Architecture

### Entry point: the Linker

The central object is `Linker`, which owns the database connection, settings,
and trained model state. It exposes sub-APIs as properties:

```
Linker
├── .training      → LinkerTraining       (EM, U estimation, prior estimation)
├── .inference     → LinkerInference      (predict, deterministic_link)
├── .clustering    → LinkerClustering     (cluster_pairwise_predictions_at_threshold)
├── .evaluation    → LinkerEvaluation     (accuracy metrics)
├── .visualisations→ LinkerVisualisations (all charts)
├── .misc          → LinkerMisc           (profiling, debugging)
└── .table_management → LinkerTableManagement (temp tables)
```

### Settings system

`SettingsCreator` is a dialect-agnostic dataclass that fully describes a linkage
model:

```
SettingsCreator
├── link_type                                 (dedupe_only | link_only | link_and_dedupe)
├── comparisons                               (list of ComparisonCreator)
├── blocking_rules_to_generate_predictions    (list of BlockingRuleCreator)
├── probability_two_random_records_match      (prior, default 0.0001)
├── em_convergence                            (default 0.0001)
├── max_iterations                            (default 25)
├── unique_id_column_name                     (default "unique_id")
├── source_dataset_column_name                (default "source_dataset")
└── retain_matching_columns / retain_intermediate_calculation_columns
```

When bound to a backend, `SettingsCreator` produces a dialect-aware `Settings`
object that resolves SQL expressions for the target engine.

### SQL generation and dialect translation

All computation is expressed as SQL. Splink uses **sqlglot** to translate a
single SQL representation into backend-specific dialects. This is the core
abstraction that allows one codebase to run on multiple engines.

Key SQL constructs used throughout:

- Common Table Expressions (CTEs) chained into pipelines (`CTEPipeline`)
- Self-joins for candidate pair generation
- CASE expressions for comparison level assignment
- Aggregations for parameter estimation
- Window functions for ranking and deduplication

### Package layout

```
splink/
├── backends/                   # Thin public wrappers (re-exports)
│   ├── duckdb.py
│   ├── spark.py
│   ├── sqlite.py
│   ├── postgres.py
│   └── athena.py
├── comparison_library.py       # Public comparison API
├── comparison_level_library.py # Public comparison level API
├── blocking_rule_library.py    # Public blocking API
├── clustering.py               # Public clustering API
├── datasets.py                 # Built-in test datasets
└── internals/                  # All implementation (~68 files)
    ├── linker.py               # Linker class
    ├── database_api.py         # Abstract backend interface
    ├── dialects.py             # SQL dialect abstractions
    ├── settings.py / settings_creator.py
    ├── comparison.py / comparison_level.py / comparison_creator.py
    ├── blocking.py / blocking_rule_creator.py
    ├── expectation_maximisation.py
    ├── predict.py
    ├── clustering.py / connected_components.py
    ├── term_frequencies.py
    ├── linker_components/      # Sub-APIs (training, inference, etc.)
    ├── duckdb/                 # DuckDB backend implementation
    ├── spark/                  # Spark backend implementation
    ├── sqlite/                 # SQLite backend implementation
    ├── postgres/               # PostgreSQL backend implementation
    ├── athena/                 # AWS Athena backend implementation
    └── files/                  # Chart templates, JS/HTML resources
```

## Database backends

Splink's backend system is built on an abstract `DatabaseAPI[TablishType]` base
class. Each backend implements:

| Method | Purpose |
|---|---|
| `_execute_sql_against_backend(sql)` | Run raw SQL |
| `register_table(input, name)` | Register a dataframe/dict/list as a named table |
| `table_to_splink_dataframe(templated, physical)` | Wrap query results |
| `sql_to_splink_dataframe_checking_cache()` | Execute with result caching |
| `sql_pipeline_to_splink_dataframe()` | Execute a CTE pipeline |

Each backend also has a `SplinkDialect` that handles SQL syntax differences
(function names, type casting, identifier quoting).

### Supported backends

| Backend | Class | Use case |
|---|---|---|
| **DuckDB** | `DuckDBAPI` | Default. In-process, fast, zero-config. Best for datasets up to ~10M records. |
| **Apache Spark** | `SparkAPI` | Distributed. For 100M+ records. Scala UDFs for string distances. Databricks-aware. |
| **AWS Athena** | `AthenaAPI` | Serverless queries over S3 data. Uses awswrangler. |
| **SQLite** | `SQLiteAPI` | Lightweight, file-based. Limited string function support. |
| **PostgreSQL** | `PostgresAPI` | Enterprise RDBMS. SQLAlchemy-based. |

### Translation relevance

R's DBI and dbplyr ecosystem provides analogous abstractions. The backend
strategy maps well:

- DuckDB → `duckdb` + `DBI` R packages
- SQLite → `RSQLite` + `DBI`
- PostgreSQL → `RPostgres` + `DBI`
- Spark → `sparklyr`
- Athena → `RAthena` or `noctua`

The `dbplyr` package can translate dplyr verbs to SQL for many backends,
which may reduce the need for raw SQL generation. However, splink's SQL is
often complex (recursive CTEs, window functions, custom UDFs) and may require
direct SQL in many places.

## Comparison system

### High-level comparisons (ComparisonCreator)

Each comparison defines how a column (or set of columns) is evaluated for
similarity. A comparison contains ordered **levels**, each producing a gamma
value (comparison vector element).

Built-in comparisons:

| Comparison | Description |
|---|---|
| `ExactMatch` | Simple equality |
| `LevenshteinAtThresholds` | Edit distance ≤ threshold |
| `DamerauLevenshteinAtThresholds` | Edit distance with transpositions |
| `JaroAtThresholds` | Jaro similarity ≥ threshold |
| `JaroWinklerAtThresholds` | Jaro with prefix weighting |
| `JaccardAtThresholds` | Jaccard similarity on tokenised strings |
| `CosineSimilarityAtThresholds` | Cosine similarity |
| `AbsoluteDateDifferenceAtThresholds` | Date distance |
| `AbsoluteTimeDifferenceAtThresholds` | Timestamp distance |
| `DistanceInKMAtThresholds` | Geographic (Haversine) distance |
| `ArrayIntersectAtSizes` | Array overlap count |
| `DateOfBirthComparison` | Multi-component date matching |
| `EmailComparison` | Email-specific (exact + domain) |
| `PostcodeComparison` | Postcode matching (exact + prefix) |
| `NameComparison` | Name matching |
| `ForenameSurnameComparison` | Combined forename + surname |
| `CustomComparison` | User-defined levels |

### Comparison levels (ComparisonLevelCreator)

Individual conditions within a comparison:

- `ExactMatchLevel`, `NullLevel`, `ElseLevel`
- `LevenshteinLevel`, `JaroLevel`, `JaroWinklerLevel`, `DamerauLevenshteinLevel`
- `JaccardLevel`, `CosineSimilarityLevel`
- `ColumnsReversedLevel` (detect swapped columns)
- `DateDifferenceLevel`, `AbsoluteTimeDifferenceLevel`
- `DistanceInKMLevel`
- `ArrayIntersectLevel`
- `PairwiseStringDistanceLevel`
- `CustomLevel`

### Term frequency adjustments

Comparisons can be configured with `term_frequency_adjustments=True`. This
adjusts match weights based on value rarity — matching on "Smith" contributes
less evidence than matching on "Xyzzynski".

## Blocking system

Blocking rules reduce the comparison space from O(n²) to a tractable number of
candidate pairs.

### Rule types

| Rule | Description |
|---|---|
| `block_on(col1, col2, ...)` | Exact match on one or more columns |
| `ExactMatchRule(col)` | Explicit exact-match blocking |
| `CustomRule(sql)` | Arbitrary SQL condition (auto-translated across dialects) |
| `And(rule1, rule2)` | Logical conjunction |
| `Not(rule)` | Logical negation |
| `SaltedBlockingRule` | Random partitioning to balance skewed blocks |
| `ExplodingBlockingRule` | Expand array/JSON columns before blocking |

Rules are applied sequentially. Each rule's output excludes pairs already
generated by preceding rules (cumulative deduplication).

### Blocking analysis

Splink provides utilities to estimate the number of comparisons each rule will
produce and to find rules that keep comparisons below a user-specified threshold.

## Model training

### Parameters

The Fellegi-Sunter model has three sets of parameters:

1. **Prior** (`probability_two_random_records_match`): The base rate of true
   matches in the data. Estimated via deterministic rules with a user-supplied
   recall estimate, or set manually.

2. **M parameters**: P(comparison level | records match). Estimated by EM or
   from labelled data.

3. **U parameters**: P(comparison level | records do not match). Estimated by
   random sampling (assumes random pairs are non-matches).

### Expectation-Maximisation (EM)

The core unsupervised training algorithm:

1. **E-step**: Compute expected match probability for each record pair using
   current parameter estimates.
2. **M-step**: Update M and U parameters as weighted sums.
3. **Iterate** until convergence (parameter change < threshold) or max
   iterations reached.

EM is run with a blocking rule to select the record pairs used for training.
Multiple EM sessions with different blocking rules can be run sequentially;
each session updates a subset of parameters.

### Training methods

| Method | Purpose |
|---|---|
| `estimate_probability_two_random_records_match()` | Estimate prior from deterministic rules |
| `estimate_u_using_random_sampling()` | Estimate U from random pairs |
| `estimate_parameters_using_expectation_maximisation()` | Full EM (M and U) |
| `estimate_m_from_pairwise_labels()` | M from labelled data |

## Prediction (inference)

After training, `linker.inference.predict()` applies Bayes' theorem:

```
P(match | data) = [P(data | match) × P(match)] /
                  [P(data | match) × P(match) + P(data | non-match) × P(non-match)]
```

This is computed as a sum of log₂ Bayes factors (match weights) across
comparisons. The output is a table of pairwise predictions with match
probabilities and weights.

A threshold is then applied to select predicted matches.

Splink also supports:

- **Deterministic linking**: `linker.inference.deterministic_link()` — strict
  blocking-only matching without probabilistic scoring.
- **Real-time prediction**: `linker.inference.realtime.predict_from_dicts()` —
  compare single records on the fly.

## Clustering

Pairwise predictions are converted to entity clusters using **connected
components** from graph theory (via the igraph library):

1. Build a graph: nodes = records, edges = predicted matches above threshold.
2. Find connected components: all records reachable from each other are assigned
   the same cluster ID.
3. Transitive closure is guaranteed: if A~B and B~C, then A, B, C share a cluster.

Additional clustering methods:

- **Multiple thresholds**: Cluster at several thresholds in one pass.
- **Single best links**: Greedy one-to-one matching (each record linked to its
  best match only).
- **Graph metrics**: Node degree, clustering coefficient, centrality — useful
  for identifying problematic high-degree nodes.

## Visualisation

All visualisations are built with Altair (Vega-Lite) and can be rendered in
notebooks or saved as standalone HTML files.

| Chart | Purpose |
|---|---|
| `match_weights_chart()` | Bar chart of partial match weights per comparison level |
| `m_u_parameters_chart()` | M and U probability estimates |
| `match_weights_histogram()` | Distribution of match weights across predictions |
| `parameter_estimate_comparisons_chart()` | Compare estimates across EM runs |
| `tf_adjustment_chart()` | Impact of term frequency adjustments |
| `waterfall_chart()` | Step-by-step Bayes factor breakdown for a record pair |
| `comparison_vector_distribution_chart()` | Distribution of comparison patterns |
| `comparison_viewer_dashboard()` | Interactive comparison exploration |
| `cluster_studio_dashboard()` | Interactive cluster exploration |

Offline chart support via `save_offline_chart()` embeds all JS dependencies
into a self-contained HTML file.

## Other notable features

- **Data profiling**: Column completeness, value distributions, top values.
- **Pair debugging**: `compare_two_records()` shows detailed comparison
  breakdown for a specific pair.
- **Labelling tool**: Interactive UI for labelling record pairs (match/non-match).
- **Built-in datasets**: Synthetic test data for quick experimentation.
- **Settings serialisation**: Full model can be saved/loaded as JSON.
- **Table caching**: Intermediate results cached with hash-based lookup to
  avoid redundant computation.
- **CTE pipelines**: SQL is organised as chains of Common Table Expressions
  for readability and execution efficiency.

## Provenance

- **Authors**: Robin Linacre (lead), Sam Lindsay, Theodore Manassis, Tom Hepworth,
  Andy Bond, Ross Kennedy.
- **Copyright**: © 2020 Ministry of Justice (UK Government).
- **License**: MIT.
- **Repository**: <https://github.com/moj-analytical-services/splink>
- **Citation**: Linacre et al. (2022), International Journal of Population Data
  Science.

## Scale of translation

A full translation of splink into R involves:

- ~68 internal Python modules plus 5 backend implementations.
- A rich comparison and blocking rule library with ~20 comparison types and
  ~15 comparison level types.
- An EM training engine with multiple estimation strategies.
- A graph-based clustering system (igraph is already available in R).
- An interactive visualisation suite (can target htmlwidgets or ggplot2 in R).
- A SQL generation layer (can leverage dbplyr, DBI, and glue for templating).
- A settings/configuration system (can use R lists or S3/R6 classes).
- Comprehensive test suite (~hundreds of tests across backends).

The fundamental architecture — generate SQL, execute on a backend, collect
results — maps naturally to R's DBI/dbplyr ecosystem. The main challenge is
translating Python's class hierarchy (abstract base classes, dataclasses,
generics) into idiomatic R (likely R6 or S3 classes).
