# prompts

These are the major prompts, organized by stage.
I am not going to track every minor back and forth, like tool calls or requests for information.
I will track any meaningful stage or substage prompts and any decisions made in minor back and forths.

This is organized by stage.

# Scope and structure

## Starter prompt a (Opus 4.6 high)

We are starting a project to translate splink, a python package for record linkage, into R.
All that is done so far is the barebones package structure for this new R package, irelink.

A local copy of the splink library is available at ../splink.
Websearch anything that you have questions about or ask me.
Review the code in splink and advise on the below.

You should:
- write a document, `inst/refs/01-what-splink-does.md` that goes through splink and highlights the goals, scope, architecture, backends, and any other notable features that will help use understand the full scale of a translation
- update the licensing and cph tag in the DESCRIPTION to properly credit the splink authors, as this is a derivative work
- draft a description paragraph in the DESCRIPTION file which aspirationally explains the package (as if it's done) in 3-5 sentences
- add some sentences to README.Rmd about what this package does (as if it's done) to complete the open goals section

## Follow up b (Opus 4.6)

As a reminder on form, make sure any *text* is not directly copied and that after updating the README.Rmd, that you render it with devtools::build_readme().

Now, research the dependencies for splink.
What does it use for any of the feature that you laid out like tables, visualizations, evaluation, etc.
What R packages should we expect to import?

When it comes to sql, what backend tools do we need?
Can we cover equivalent features using DBI/dbplyr?
Ideally, we would be able to use dbplyr as the main entrypoint here.

Research both big buckets of questions.
Then write your findings to `inst/refs/02-splink-and-r-deps.md`.

## Stage wrapup (Opus 4.6)

Based on what you've done in `inst/refs/01--02`, write a stage summary, `inst/refs/stage-01-notes.md`.
This should be an executive summary with key references back to the other files.

# Planning

## Starter prompt a (Opus 4.6 high)

We are starting a project to translate splink, a python package for record linkage, into R.
A local copy of the splink library is available at `../splink`.
We have some background research in `inst/refs/stage-01-notes.md`.

Our next step is to create detailed tables of any meaningful functions, what they do, if they're internal or external, and what file they reside in.
Organize them by category so that each distinct type of thing has its own section.

Ignore things like thin one-liners and niche python adjustments.

Write your findings to `inst/refs/03-splink-functions.md`.

## Step b (Opus 4.6 high)

Now, define the R interface for irelink.
This should not be a direct copy of splink's interface.
Instead, it should be designed like dplyr verbs are from the tidyverse.

Consider first how things like dplyr's joins look.
Then, consider what the core data structure for linkers and database passing and other key components look like.
Then, write a series of target examples.

Iterate on those examples until they look like something that a tidyverse user would be familiar with.
Draw explicit comparisons between choices here and in the tidyverse.

Once there is a system of examples that have familiarity to tidyverse users, make explicit comparisons to those functions or workflows.
Be sure to consider both the inputs and outputs.
For example, how would a pipe to join two datasets and then plot some column from dataset a by a column from in dataset b.
What types of layers and aesthetics would go into it for a ggplot summary?

Finally, write your findings to `inst/refs/04-irelink-core-interface.md`.
This should detail the types, the major inputs, and any other details about how this can be friendly for tidyverse users.
Ensure that there are examples in this document.

## Follow up b (Opus 4.6 high)

This looks very good.
Please also look at `gt`, which has a slightly more modern interface than `ggplot2`.
It is also made by Posit.
Check for any improvements that we should make based on how they handle the data and building complicated calls.

## Implement b (Opus 4.6 high)

Now, based on the interface and examples in `inst/refs/04-irelink-core-interface.md`, build out the R files that will hold these.
Functions should all be a stub for now that simply look internally as:

```
cli::cli_warn('Function {.fn THE NAME} is not yet implemented.')
invisible(NULL)
```

Put one major function in each file.
Name the files after the function (though you may omit prefixes unless those help sort them).
If there are planned common utility functions, place those in `R/utils-INFORMATIVE NAME.R`.

We can edit the function signatures later, but pay careful attention to what arguments are included and in what order.
Make sure functions remain "tidy" and pipe-able.

Write a summary of this, with key details, to `utils/refs/05-file-function-structure.md`.

## Roxygen c (Opus 4.6 high)

Now, based on the interface, examples, and details in `inst/refs/04-irelink-core-interface.md` and `utils/refs/05-file-function-structure.md`, start writing roxygen documentation for every function.
Functions should remain as stubs for now.

Every single exported function should have roxygen documentation.
They should all have arguments that look like the below:

```
#' Title
#'
#' A brief sentence or two description
#'
#' @param smthn some parameter
#'
#' @return type of return and a few words
#' @export
#'
#' @examples
#' AN ACTUAL EXAMPLE THAT (will eventually) RUN
my_fn <- function(smthn) {
    cli::cli_warn('Function {.fn THE NAME} is not yet implemented.')
    invisible(NULL)
}
```

Internal functions should still be documented, but should replace @export with @noRd.

Make sure every function has at least these arguments and that they keep this order and spacing.
This ensures that we have sufficient information for the next stage and that they can be parsed as text cleanly.

Write a summary of this, with key details, to `utils/refs/06-function-draft-documentation.md`.

## Roxygen d (Opus 4.6 high)

Verify that this software is sufficient to cover all core features in the translation from splink.
Refresh your memory with `refs/03-splink-functions.md`.
For any features that are not implemented, make a determination of it they should be in the core set of things that we first build out.
Otherwise, make a note in `utils/refs/07-features-for-later.md`.

For truly optional things like interactive plots, leave those as a note.

## Organization e (Opus 4.6 high)

Now, we need to organize the package implementation into sprints.

We want to break up the implementation into 10 or so concrete pieces.
This should allow us to start with the core of the core: the main features that everything needs.
Then, we can build out slowly in stages until everything has moved from a stub implementation to actual, functioning code.

Identify which functions go into which sprints.
Functions can rely on functions in prior, but not later, sprints.

For implementing this, we will then take a tests-first approach.
Be aware that this means each sprint should have some features that are user facing and can be verified against
Consider this when designing the sprints to make sure we can proceed with deliverables from a sprint.

Write up a detailed description `inst/refs/08-sprints.md`.
Explain the goals of each sprint and what can be done after a sprint is complete within the document.
Each sprint should have a preamble and a table of functions.

## Implementation plan f (Opus 4.6 high)

Now, take everything from this stage and provide two documents.
First, a full implementation plan for stages 3--7 from `inst/notes/goals.md`.
Make this detailed so that the stages and everything we've done have sufficient notes to continue forward.

Second, write `stage-02-notes.md` that summarizes everything we have done in this stage.

# Test implementation

## Initial translation a-b (Opus 4.6 high)

We are starting a project to translate splink, a python package for record linkage, into R.
A local copy of the splink library is available at `../splink`.
We have some background research in `inst/refs/stage-01-notes.md` and implementation plans in `inst/refs/stage-02-notes.md`.

Our next stage is building out complete tests for the package.
I have already initialized testthat, which we will use for testing.

First, make a helper function for testthat like
`skip_if_sprint_le(sprint, x)` where `sprint` should be defined in `tests/testthat/setup.R` and you assign a value `x` for each test.

Then, I need you to read `inst/refs/08-sprints.md` and Stage 3 of `inst/refs/09-implementation-plan.md`.

Third, using that information, review every single test in splink and copy it to our testthat.
When copied, we need to translate their syntax into our functions.

For this last stage, proceed in 4 steps.

1. Make an inventory of the tests in splink.
2. Identify our translation for each test.
3. Write a test for each of their tests. Attempt to match their expectations. *Never* put expectation statements from testthat in a loop, as it inflates the test count without providing new information and makes it hard to track failures in the future.
4. Compare with notes in 08 and 09 to identify which sprint it will be implemented in.

Make a detailed report on testing in `inst/refs/10-testing-translation.md`.

## Update translation (Opus 4.6 high)

Can you also look at every test suggestion in `inst/refs/09` and see if it should be added to the stages?
I believe those are aimed more at our objects and less at splink things.

# R code implementation

Following the implementation plan in `inst/refs/08-sprints.md` and `inst/refs/09-implementation-plan.md`, write the package.

Go sprint by sprint.
Only proceed to the next sprint once the tests pass.
The tests are presumed correct until proven otherwise.

After each sprint, write an update to `inst/refs/11-writing-r.md`.

## Stage wrapups (Opus 4.6)

Based on what you've done for testing in `inst/refs/10`, write a stage summary, `inst/refs/stage-03-notes.md`.

Similarly, based on what you've just finished for the implementation and your notes in `inst/refs/11`, write a stage summary, `inst/refs/stage-04-notes.md`.

Both should be executive summaries with key references back to the other files.

# Code simplification (Opus 4.6)

Now, identify places in the code base where there is duplication.
If there are places where logic is being repeated, move them to helper functions placed in correctly named utils files.
If there are very similar patterns in multiple places, with small differences, write these to helpers with options.

Reefer to `inst/refs/09-implementation-plan.md` stage 5 for notes on some common things to look for.

Make a detailed report on simplification in `inst/refs/12-simplifying-r.md`.

# Test review

## Starter prompt (Opus 4.6 high)

Review the notes on tests for this package in stage-03-notes.
The tests are primarily translations from python.
Scan the tests and look for any things that may be missing due to using a more function-based interface, R objects, or things like R's vectorization.
Add tests for anything missing.

Write a summary to `inst/refs/13-tests-for-r.md`.

## Agent-suggested review points (Opus 4.6 high)

Now go through all of the suggested things to check for in the Stage 6 notes of `inst/refs/09-implementation-plan.md`.

Write a summary to `inst/refs/14-more-tests-for-r.md`.

## Stage wrapups (Opus 4.6 high)

Summarize anything you've just done with `inst/refs/13-tests-for-r.md` and `inst/refs/14-more-tests-for-r.md` into `inst/refs/stage-06-notes.md`

I also forgot to write a `inst/refs/stage-05-notes.md`.
Can you add an executive summary of `inst/refs/12-simplifying-r.md` to it.

# Performance review (Opus 4.6 high)

Review `inst/refs/09-implementation-plan.md` Stage 7.
Do not actually create direct comparisons with splink, yet.

First, run steps 7a-7e, focused specifically on our R and SQL implementation.
If necessary and things are surprisingly slow, consider C implementations.
Don't add C implementations yet, but do note them.

Write a summary in `inst/refs/15-performance-in-r.md`.
If there are things you suggest rewriting in C, note them in the document and in your response to me.

# Polish

## Some taste things (Opus 4.6 high)

Can you review the code in the package and identify things that could be cleaned up.

First, all examples should run.
They should not use `\dontrun` unless there is a very good reason why they can't such as needing an API key.
Long running examples can be wrapped with `\donttest`.
The use of either of these should be extremely unlikely and I suspect we do not need either.

Then, review the internals, especially the pieces that write strings and sql.
Let's use the `glue` package internally since there seems to be a lot of string building.
Look in particular at `glue::glue()`, `glue::glue_sql()`, and the other glue sql functions.

Finally, make sure all printing to the console is done with `cli`.
Avoid using `cat`.
`print` and `format` should be used rarely, primarily for custom classes where necessary.

Make sure that devtools::check() comes back cleanly.

## Docs (Opus 4.6 high)

Awesome. I have done 3 things:

1. Added a pkgdown site. Add all of the functions by category. Check it with `pkgdown::check_pkgdown()`.
2. Added an empty intro vignette `irelink.Rmd`. Fill it out with a descriptive starter info. Use what splink discusses as the baseline for what to include. Don't just copy text though.
3. Added an empty irelink <--> splink vignette `from_splink.Rmd`. Add primary tables of references between the two. Then, provide a few comparison examples of code. Don't go crazy with the examples, but demo what some of the main things people would do and how it can be done. This should mostly be a series of tables separated clearly by grouping. The categories from (1) may help.

Finally, check that the readme.Rmd is up to date and add info if necessary, but keep the document clean.

Check that it still builds cleanly with devtools::check() and that this is only moderately slower. (Try to keep the full check to under 3:15 with the vignettes.)

For readability, any time you write to markdown, please make sure that each sentence has its own line and that there are not new linebreaks in the middle of sentences.

# Speed (Opus 4.6 high)

Let's get a rough idea of speed.
Can you look at this blog post <https://www.robinlinacre.com/fast_deduplication/> and run the same thing for our codebase?
Don't rerun any of the other systems, just get use this to eyeball how we are doing.

If we're behind, identify what we might need to fix.

## follow up (Opus 4.6 high)

Write these updates to `inst/refs/16-performance.md`.

Also review the description: it looks like we have some packages as "suggests" but use them unconditionally.
That needs to be fixed by upgrading them to imports.

Then, can you run the blog post examples and see how we do now that you patched duckdb?

# Missing features (Opus 4.6 high)

I had another Claude look at this and it found some issues.

Most important:

term_frequency is not implemented -- it silently does nothing.

The term_frequency = TRUE flag is accepted by cl_exact() and stored on the comparison level object (there's even a test that checks lev$term_frequency == TRUE), but it is never read anywhere downstream. Neither utils-sql.R, utils-scoring.R, nor predict.R reference term_frequency at all.

The inst/refs/07-features-for-later.md file explicitly deferred it: "Term-frequency tables will be computed internally by cl_exact(term_frequency = TRUE)" -- meaning the intent was there but it was never built.

The risk: The benchmark at inst/benchmarks/rl-workshop.qmd uses cl_exact(term_frequency = TRUE) on city, which will produce the same result as cl_exact() with no flag. If someone benchmarks against splink using TF weighting enabled, the results will quietly differ.

## follow up (Opus 4.6 high)

Things to verify before asking for feedback:

link_and_dedupe mode -- the from_splink vignette lists it as supported, but the explore found it may be incomplete. Worth checking whether il_model() actually handles it correctly end-to-end.

il_find_matches() -- the README doesn't cover it, but the from_splink vignette maps it. Worth a quick smoke test to make sure it runs correctly with a trained model.

The fake_1000_links demo dataset -- the two halves are just a random split of the same 1000-record pool rather than a true held-out linked dataset. This means the "linking" demo doesn't actually demonstrate cross-dataset linkage in a meaningful way. Splink's demo data has genuine cross-dataset pairs. This could confuse someone benchmarking against splink.

What's genuinely missing vs splink:

No equivalent to splink's linker.visualisations.* charts -- only autoplot() for match weights. Splink's waterfall chart, parameter estimate comparisons, and unlinkables chart are popular; if those aren't rendered as interactive HTML, that's a notable gap.
No phonetic blocking (Soundex, Metaphone). Splink doesn't have it either out of the box, but it's a common ask.
No batched/incremental retraining API.


# Performance Again

## Things done in R that should be in backend (Opus 4.6 high)

Here are a few major things I need you to look at.

First, why do we use stringdist in R?
Shouldn't we be pushing all of those types of computation straight at the duckdb or other sql backend?
It would seem a huge portion of timing during tests is from materializing data that can stay within the SQL.

Further, for EM calculations and the gamma, why are we pulling that into R?
That should, again, happen in SQL.
Look to what splink (../splink) does for things like that.

The canary in the coalmine here is that a `con` was created for DBI and then nothing happens with it.
Scan for any other instances of where that occurs.

Fix these two issues and anything similar that you identify.
Write your findings to `inst/refs/17-shove-into-sql.md`.

# Features

## Things to make sure we can do (Opus 4.6 high)

Please review the codebase as I have made a few changes.
Check the last few commits and see what they do.
Then, figure out why the `devtools::check()` does not pass.

Once we have a clean starting place, let's look to ensure that we have strong feature compatibility.

First, look at `inst/benchmarks/rl-workshop.qmd`.
It is a translation from my officemate's demo, at `C:/Users/chris/Documents/GitHub/rl-bootcamp/scripts/demo.ipynb`.
Identify all missing features from that translation and write them to `inst/refs/18-feature-parity.md`.

Secpond, replicate this process for each file in `../splink/docs/demos/tutorials`.
Write a translation in `inst/benchmarks/` with a clear name.
Ideally make notes if a feature is missing and implement it as close as possible.
Make sure the code runs if possible.
Then, identify all missing features and write them to `inst/refs/18-feature-parity.md`.

Once you have identified all of the gaps, implement the changes.
I do not want you to consider (1) interactive graphics, (2) obscure pythonic features, or (3) compiled documents to be missing features that need to be implemented, but you should note them in the doc.

## Improving the basics (Opus 4.6 high)

Based on your looking at splink are there 1-2 reasonable sized datasets that we could include in the package to do real benchmarking and comparison? This could allow us to include some vignettes that better  help users get through major tasks with realistic data examples?

Further, are there any plotting lessons  or summary()-type lessons that we should implement here based on the tutorials? Think through these, implement the data and any new features you see from working through the tutorials.

Then, write two vignettes which use the new data and (if possible) the new plots or diagnostic summaries.

Write an update to `inst/refs/19-tutorial-lessons.md`.


## Follow up (Opus 4.6 high)

So these changes look like they're in the right direction but, it doesn't seem like you listened to what I asked for.

Look at the datasets in `../splink/tests/datasets/` and choose 1-2 to include in this package.
We are a derivative of splink and should include some of the same data to ensure comparability.
Create a `data.R` file that documents and exports the chosen datasets using `usethis::use_data()`, with documentation that explicitly references splink as the source.

Also, `set.seed()` must never appear in package code.
Never!
Perhaps make a random vector once now  and use that to index entries or something, if you really need random stuff for `il_demo()`.
`set.seed()` is only appropriate in vignettes and the README.

Finally, update the vignettes to reflect these changes.

## Follow up (Opus 4.6 high)

Again, moving in the right direction, but some of these things follow bad patterns.

First, there's no reason for `il_demo()` anymore, since we have real demo data.
The one thing to do is to write the fake 20 line dataset with the other ones in `data-raw/`.
I don't know why you were making them in a random directory, so I moved it there and .Rbuildignored the folder.

Looking at the changes, it looks like there must be a regression, since you added:

```{r}
# irelink requires a unique_id column
df_a$unique_id <- seq_len(nrow(df_a))
df_b$unique_id <- seq_len(nrow(df_b))
```

That's silly, why would it require a user to make a unique_id column.
You can't rely on this!
This is package code and user datasets will come in all shapes, sizes, and column names.

The original readme example was cleaner with:

```
  il_compare(first_name, cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(surname, cl_jaro_winkler(0.9, 0.7)) |>
  il_compare(dob, cl_exact()) |>
```

suburb and "given" name seem like fake columns.
Are there better columns to use, like the first name or dob?

Avoid using cat so much in the vignettes.
That creates very bad code to read in a demo!

Finally, you seem to have stopped following the conventions in CLAUDE.md.
Properly format code as you go using `styler.quote::style_pkg()`?

## Tests (Opus 4.6 high)

Now, let's do a targeted pass on the check.
One of the big things I see is that the tests have ballooned and that doesn't represent better testing.
There are many tests that test NOTHING about the package.
Remove things that test features of R rather than the package.

For example, tests that a dataframe that is saved has the right number of columns
That adds time, but absolutely nothing else.
Scrutinize every single test and ask if it is testing a feature of the package or is just a test with no purpose.
Be critical and delete tests that do not need to be there.

The sprints for testing purposes should also be entirely eliminated.

## Scaling

Right now, it looks like a lot of the functions take in-memory data and work with that.
That works well for testing and maybe for some cases.
However, that will not scale into huge data.
We need to figure out a clean way to accept in memory data e.g., tibbles or data.frames and ALSO accept dbplyr or DBI database connections.

I suspect, the interface we want is to accept database references and avoid doing things like converting them to data frames in memory.

To be clear, we should support both in memory and database connections.

Identify how splink (../splink) handles this type of constraint, make a plan for us to do it well in R, and then expand our behavior.

Write a summary of your findings, plan, and edits to `insts/refs/20-connections.md`

## Update notes (Opus 4.6 high)

Can you write a summary of files 15--20 as `stage-08-notes.md`. This should be described as the polishing stage." Include references and format the file similar to the stage 7 notes.

## igraph + components (Opus 4.6 high)

One of the big remaining things that I see to do in this package is that we have to pull a lot of data out to run the igraph-related clustering.

Review `inst/refs/17-shove-into-sql.md` and `inst/refs/20-connections.md` that describe some related steps in this package.

Then, look at ../splink, which we are a derivative of, and identify how it handles this within the SQL engine, where possible.
Note any things that we can learn from their approach.

Then, develop a plan so that we can minimize the amount of data that we pull out and optimize the amount of processing in SQL for our clustering steps.

While doing this, consider how this impacts future extensibility and keep careful notes on what you find an change in `inst/refs/21-clusters.md`.


## Updating plots (Sonnet 4.6 medium)

Can you now do a writeup in `inst/benchmarks` as a Quarto file which provides light prose (explaining what's going on, but without excessive detail), to test the accuracy of our method.
I want you to use the febrl4 data and attempt this: https://moj-analytical-services.github.io/splink/demos/examples/duckdb/febrl4.html

Identify if we are missing features for their default plots and implement them.


## Cross-checking plots (Codex GPT-5.4)

Can you review all of the autoplot methods for this new record linking R package?
Please fix any issues you encounter.

## Cross-checking vignettes (Opus 4.6 high)

Can you review all of the vignettes for this new record linking R package?
Please fix any issues you encounter.

## US-ability (Sonnet 4.6 medium)

Can you scan for non-American terms and flag them, such as postcode.
We should ensure that US records are treated well.

## Phonetics (Opus 4.6 high)

We are working on a new record linkage package in R, derivative of splink (available at ../splink).
One feature that we have skipped up to this point is phonetic algorithms.

Can you research which phonetic algorithms are supported by splink?
These are used for blocking.

Then, implement them here.
Make sure that they will be handled SQL-side so that we do not have to materialize data.

Add corresponding tests.

Write up your research and a summary of findings in `inst/refs/23-phonetics.md`

## Polish (Sonnet 4.6 medium)

Can you examine the stage updates in inst/ for this project and identify points of weakness relative to splink?
Please identify and fix the biggest gaps.


## ggplot2 polish (Sonnet 4.6 medium)

We are working on an R package.
I want you to scan the autoplot functions (don't worry about the rest of the package) and identify places where we've set scales or themes.
We need to standardize this into a light touch.
Strip things which change from defaults without a clear purpose.
Keep theming as minimal.

## Comparison check (Opus 4.6 high)

Perform a deep dive comparison between this package (irelink) and splink (../splink).
This package is a derivative.
We want to ensure that all features of splink are incorporated here.
If there are improvements here that are not in splink, note those.

Prepare a detailed writeup with notes on any missing features in `inst/refs/28-comparison.md`.
Include relevant paths and links to the source of the differences.

### Follow-up (Opus 4.6 high)

Implement all high priority gaps.
Then, give 5, 6, 7, 9 and 10 a go.

Update the `inst/refs/28-comparison.md` document with notes on how it was resolved.
Mark the tables as resolved once they are fixed, too.

### Follow-up (Opus 4.6 high)

Continue going through the remaining gaps.
Proceed in the order of the sections.

If things are marked as out of scope, do not attempt them.
Skip dataset parity for now.

For all updates, ensure that as much as possible is done on the SQL side and that data should nearly never be materialized from SQL to R.

Update the `inst/refs/28-comparison.md` document with notes on things being resolved.

### Wrap-up (Opus 4.6 high)

I see some failures on the CI for building the pkgdown.
Make sure the pkgdown is updated to include al of the Rd updates from the changes covered in `inst/refs/28-comparison.md`

I have not yet pushed your most recent changes, but the prior set failed with:


```
Error in `build_reference_index()`:
! In _pkgdown.yml, 9 topics missing from index:
  "autoplot.il_string_similarity", "cl_columns_reversed", "cl_time_diff",
  "hours", "il_score_missing_edges", "il_tf_chart", "il_transform", "minutes",
  and "seconds".
ℹ Either add to the reference index, or use `@keywords internal` to drop from
  the index.
```

Then, update the NEWS.md to include the features that we just added, where applicable.
Note that this is still a first release and is not public yet, so it should be more about feature coverage rather than updates.
Avoid framing like "new", "now", "fixed", etc that imply change, rather than a first release.

Finally, write a stage-09-notes.md summary doc, on this new "Coverage and Polish" stage.
It should cover `inst/refs/21`--`inst/refs/28` with links.
Keep the style very close to an executive summary with references for easy searching later, like how the other stage notes are written.

### Wrap-up (Opus 4.6 high)

Ensure devtools::check() returns cleanly.
Further, do a dive on all of the changes from today and verify that everything is pushed into SQL as much as possible.
Fallbacks to R should be a worst case scenario and extremely rare

## linting (Opus 4.6 high)

Can you scan all ggplot calls for the following INCORRECT AND NEVER ALLOWED patterns:

Never do:
ggplot(df)

Always should be:
df |>
  ggplot()

Never do:
ggplot(aes(x = ...))

Always should be:
ggplot() +
  geom_SOMELAYER(aes(x = ...))

## linting (Opus 4.6 high)

Run `jarl check .` to use the jarl linter.
A large number of lints indicate the unnecessary use of `:::`.
Drop those, as `testthat` makes internal functions available for testing.

Then, for each remaining piece, identify what the best course of action is.
Fix small lints first.

Next, refer back to the `inst/refs` folder for functions which are defined but unused.
Identify what their purpose is and why they were written.
If a function should be used, find out where it is missing.
If it should be removed, do so but only hesistantly.
Be very sure before removal.

Then provide a detailed writeup with notes in `inst/refs/29-linting.md`.


## Tests (Opus 4.6 high)

Now, let's do a targeted pass on the tests.
The number of tests has drastically ballooned and that doesn't represent better testing.
There are many tests that test NOTHING about the package.
Remove things that test features of R rather than the package.

Scrutinize every single test and ask if it is testing a feature of the package or is just a test with no purpose.
Be critical and delete tests that do not need to be there.

If there are blocks of tests that are near identical code and could be combined into a cleaner set of expectations, combine them.
Never put any expectations within a for-loop.
Always make use of R's vectorized approach to ensure that tests get their money's worth.

## Vignette (Opus 4.6 high)

Create a new vignette, based on: https://moj-analytical-services.github.io/splink/demos/examples/duckdb/deduplicate_50k_synthetic.html.
Copy the format and make sure we can replicate each of the pieces of the analysis.

Indicate explicitly at the top that it is based on the Splink demo that we are working from.

The data can be read from: https://raw.githubusercontent.com/moj-analytical-services/splink_datasets/master/data/historical_figures_with_errors_50k.parquet.

Make compilation of the vignette dependent on succesful reading of the file.
You may use a suggests for a parquet reading file, likely nanoparquet.
Compilation should also be dependent on that package being available.


## Vignette (Opus 4.6 high)

Create a new vignette, based on: https://moj-analytical-services.github.io/splink/demos/examples/duckdb/transactions.html.
Copy the format and make sure we can replicate each of the pieces of the analysis.

Indicate explicitly at the top that it is based on the Splink demo that we are working from.

The data can be read from:
- https://raw.githubusercontent.com/moj-analytical-services/splink_datasets/master/data/transactions_origin.parquet
- https://raw.githubusercontent.com/moj-analytical-services/splink_datasets/master/data/transactions_destination.parquet

Make compilation of the vignette dependent on succesful reading of the files.
You may use a suggests for a parquet reading file, likely nanoparquet.
Compilation should also be dependent on that package being available.

## SQL materialisation audit (Opus 4.6 high)

We recently fixed a performance bug in `il_estimate_u()`.
`get_random_pairs_with_gammas()` was building a SQL query that computed gamma values in DuckDB correctly, but then pulling the entire result into R via `DBI::dbGetQuery()` and counting level frequencies in R loops.
For 5 million pairs that meant materialising a large matrix in R — work that DuckDB could do in a single `GROUP BY COUNT(*)`.
The fix was to wrap the sampled pairs in an outer `SELECT ... GROUP BY` so only a tiny aggregated table crosses the boundary.

Audit every `DBI::dbGetQuery()` call in `R/`.
For each one, look at what R does with the returned data frame immediately after.
If R aggregates, counts, filters, or reduces the rows, that work belongs in SQL.
If the result is stored and passed around, trace how it is eventually consumed and apply the same test.

Pay particular attention to `utils-em.R`, `utils-scoring.R`, `predict.R`, `il_cluster.R`, and `utils-evaluation.R`.
Cross-check against `../splink` to see whether splink keeps the equivalent step in SQL and note any place where splink uses a SQL aggregate that we do not.

Implement fixes for any site where moving to SQL is clearly correct and safe.
Do not fix sites where the R-side processing is genuinely non-trivial (e.g. stringdist comparisons with no SQL equivalent in the current dialect).

Write your findings and any fixes to `inst/refs/30-sql-audit.md`.

## Deep-Dive

Perform a deep dive comparison between this package (irelink) and splink (../splink).
This package is a derivative.
We want to ensure that all features of splink are incorporated here.
If there are improvements here that are not in splink, note those.

Pay particular attention to any SQL generation.
We need to ensure that any SQL we generate is correct and true to its intentions.

Prepare a detailed writeup with notes on any missing features in `inst/refs/32-comparison.md`.
Include relevant paths and links to the source of the differences.


### Follow-up

Identify all meaningful gaps and implement them.
Use the splink code as the reference, since we are a pure derivative product.
Go through carefully, updating the 32-comparison doc after each fix.
Make notes about how they were fixed.

### Follow-up

I reverted your commits.
As per the instructions document, you are never ever allowed to commit.
All changes must be approved by me directly.

Below are comments on specific pieces:

1.
> splink's `cumulative_comparisons_to_be_scored_from_blocking_rules_data()`
(`blocking_analysis.py:335+`) aggregates comparison counts across multiple
blocking rules and visualises per-rule marginal impact. irelink has no
equivalent — users can call `il_count_pairs()` per rule but there is no
built-in cumulative analysis or chart.

I'm very sure we have a chart for this already.
Please verify and remove this if you agree.

2.
> **Key implementation difference:** irelink runs EM in R on aggregated
gamma-pattern counts (`GROUP BY` gammas → R-side matrix operations on ~100-1000
patterns), while splink runs the full EM loop in SQL. irelink's approach is
typically faster because the pattern matrix is tiny relative to the pair count.

I need you to consider this very carefully.
Is this actually equivalent?
Those summary statistics are useful and it makes sense that it might be faster in R.
However, it is not clear that this is actually correct.
I don't know of anything that would guarantee that these are sufficient statistics if there is additional information for the m estimation that could come from the term frequency weights.
Verify with exact line references and details on the SQL generated and the R code run.

3.
**Difference:** splink enforces the dataset constraint iteratively during
representative propagation (per iteration); irelink pre-filters edges once
before the algorithm starts. For two-source linking, the results are typically
identical. For multi-source linking (3+ datasets), splink's iterative approach
may produce cleaner results.

Have you fixed this?

Fix all of the issues you have encountered.
Include your responses to each question and details on the fixes in document 32.

## Trace down bug

`irelink` appears to overmatch substantially relative to `fastLink`.
In the rendered comparison, `fastLink` remains much more precise, while `irelink` still produces many extra links that should not be there.

Before deciding what to do next, the main things to check are:

- whether the issue is mostly in pairwise scoring or mostly in clustering
- whether some comparisons are being weighted too strongly, especially for plausible near-matches
- whether the EM-trained probabilities are poorly calibrated even when ranking is reasonable
- whether the same false-positive pattern persists under labeled estimation rather than unsupervised EM

That would tell us whether this is mainly a vignette/demo problem, a calibration problem, or evidence of a deeper modeling issue.

## Follow-up

High-level issue: after fixing the EM bug, irelink is no longer failing catastrophically, but it still appears to produce too many false positives relative to fastLink on this benchmark.
The remaining errors are mostly very plausible near-matches: exact or near-exact names with 2 out of 3 DOB components matching.
That suggests the comparison is now surfacing a real modeling/calibration gap rather than just a vignette setup problem.

Things worth looking at next:

- Whether irelink is overcounting correlated evidence, especially exact first name + exact surname + partial DOB agreement.
- Whether the learned u probabilities are too small for common nonmatch patterns, which would make these near-matches look rarer than they really are.
- Whether the current discretized comparison design for names and dates is too coarse relative to fastLink’s partial-agreement handling.
- Whether the remaining gap is mostly in pairwise scoring or in how pairwise links are turned into clusters.
- Whether probability calibration is too aggressive even when the ranking of candidate pairs is reasonable.


## SQL pushdown audit (Opus 4.6 high)

We are auditing `irelink` to ensure that as much work as possible stays in SQL rather than being materialized into R.
Your job is to identify every place in the code path for a target feature where data crosses from the database into R, determine whether that boundary is necessary, and, where safe, push more of the work into SQL.

Focus especially on:
- `R/utils-evaluation.R`
- `R/predict.R`
- `R/il_cluster.R`
- `R/utils-cc.R`
- `R/utils-em.R`
- `R/utils-sql.R`
- any directly related helper files you discover while tracing execution

For each target function or workflow:
1. Identify the entrypoint function and list the exact downstream helper calls in order.
2. Mark every `DBI::dbGetQuery()`, `collect`, `as.data.frame`, `as.matrix`, `tibble` construction from SQL results, or other point where SQL results are materialized into R.
3. For each materialization point, answer:
   - what rows and columns are being pulled into R?
   - approximately how large could that object become on a large job?
   - what does R do with it immediately afterward?
   - could that next step be done in SQL instead?
4. Distinguish carefully between:
   - necessary materialization for final user-facing output
   - harmless materialization of a tiny aggregated result
   - harmful materialization of pair-level or record-level data that should stay in SQL
5. Cross-check the equivalent logic in `../splink` and note whether splink keeps that step in SQL, and how.
6. If a safe SQL pushdown is possible, implement it.
7. If a pushdown is not clearly safe, explain why not, with exact references.

Important rules:
- Do not assume that because something is "aggregated" in R it is necessarily correct or efficient.
- Be especially skeptical of any place where pair-level rows, gamma matrices, cluster assignments, or labeled-pair universes are pulled into R.
- If the R side immediately groups, counts, filters, ranks, joins, or computes flags on SQL results, that is a strong sign the work belongs in SQL.
- Keep a special eye on lazy-vs-collected paths. If a function already has a SQL path, prefer extending it rather than creating a new R-heavy branch.
- Verify empty-result behavior and singleton/no-edge cases. SQL pushdown changes often break those.

Your output should include:
- a concise table in `inst/refs/33-sql-audit.md` with every exported function
- for each function, include: `function`, `sql-first?`, `materializes to R?`, `problem`, `action`, and `notes`
- keep each cell short and human-readable
- add file and line references where useful
- note any correctness risks, not just performance risks
- include a short summary of code changes made

If you modify code, run the relevant tests afterward and report which passed.

## Correctness audit (Opus 4.6 high)

Perform an extremely detailed correctness comparison between this package (`irelink`) and `splink` (`../splink`).
Focus on places where a small mistranslation could silently change results, especially SQL generation, comparison translation, EM estimation, term frequency, scoring, clustering, defaults, and edge-case handling.

For each investigation, identify the `irelink` entrypoint and matching `splink` code path, trace the relevant helpers, compare the SQL and output behavior, determine whether the translation is correct, and fix anything that is wrong.
Be especially careful about places where `irelink` aggregates in R while `splink` aggregates in SQL, where flags or defaults are accepted but not used, or where behavior may diverge on empty inputs, singleton inputs, tied scores, or multi-dataset linking.

Write the results to `inst/refs/34-splink-correctness.md`.
Include a primary markdown table with one row per investigation and these columns: `investigation`, `irelink path`, `splink path`, `status`, `risk`, `action`, and `summary`

After the table, include a short markdown subsection for each investigation covering what was checked, what was found, why it is or is not correct, what was changed, and any remaining follow-up.

Ensure all tests pass after corrections.

## Correctness audit (Opus 4.6 high)

Perform an independent correctness audit between this package (`irelink`) and `splink` (`../splink`).
Do not treat prior comparison writeups as authoritative.
In particular, `inst/refs/34-splink-correctness.md` is an example of an audit that is too cursory and too willing to declare equivalence.
Use it only as a warning about what not to do.

Your job is to perform the audit directly.
Trace the code paths yourself.
Check the SQL yourself.
Verify edge cases yourself.
Do not rely on high-level claims like "same algorithm", "equivalent", or "no bugs found" unless you can support them with exact evidence.

Focus on places where a small mistranslation could silently change results, especially:
- SQL generation
- comparison level behavior
- term frequency handling
- EM estimation
- scoring and thresholds
- clustering and connected components
- defaults and fallback behavior
- empty, NULL, tied-score, and multi-dataset edge cases

When prior work such as `inst/refs/34-splink-correctness.md` makes a claim, verify it from the code rather than repeating it.
If the prior writeup is too weak to support a claim, say so plainly and then determine the answer yourself.

Write the results to `inst/refs/35-correctness-audit.md`.
Include a primary markdown table with these columns: `investigation`, `status`, `risk`, `irelink path`, `splink path`, `evidence`, `action`

After the table, include short subsections for the most important investigations.
For each one, state what was checked, what was found, why the evidence is sufficient, and what remains uncertain.
If you find places where `34` made claims that were too cursory, unsupported, or overstated, note that briefly as part of the investigation rather than turning this into a review of that file.

## Scaling Testing (Opus 4.6 high)

We need to develop some pseudopeople benchmarks.
In `../pseudopeople-ri` are 5 parquet files.
Look at the single python file there, which will show how they were generated.

We want to population a single quarto file in `inst/benchmarks/pseudopeople.qmd` which runs several benchmarks:

- zero:zero (ideal scenario that should be merge-equivalent)
- zero:default (admin linkage to normal data)
- zero:high (admin linkage to noisy data)
- default:high (realistic linkage)
- rbind(zero, default, high) (deduplication)

For each of these, be sure to contain information about (1) accuracy, (2) blocking rules, (3) model fit, and (4) timing.
Each task should include relevant plots and timing information in the text.

The files cannot be copied into this repo, but exist at `../pseudopeople-ri/`.
They are parquet files and, ideally, you should not ever read the data into memory.

Process-wise, start by running tasks in R without Quarto, then move them into the Quarto document once it works interactively.
Ping me once the file successfully compiles and report back on any specific changes you need to make.

Note: there is no python on this machine.
You cannot run any python commands.
Everything must be done in R.


## Fixes after scaling testing (GPT-5.4)

We have performed some large scale testing of this package.
Most of the results look very good.

Look at this summary of the problem we encounter:

The stacked dedupe scenario is not good if we judge it by pairwise duplicate detection.
Its best threshold is 0, pairwise precision is only 24.24%, F1 is 0.39, it emits 14.4M duplicate pairs, and clustering produces a largest cluster of 733,099 records.
That reads like substantial over-linking, even though cluster-level metrics recover somewhat to precision 77.68% / recall 99.59% / F1 0.873: pseudopeople.typ (line 1473), pseudopeople.typ (line 1559), pseudopeople.typ (line 1598), pseudopeople.typ (line 1635).

As needed, look at ../splink to check our process against theirs, as this is a derivative software.
If you spot meaningful differences, implement them here.

Return when you have identified and fixed the problem.

# Eric Requests

## JSON (GPT-5.4 high)

You are working on a record linkage package in R.
It is a derivative product of splink (../splink).
You can use their implementations as necessary.

In commit d6851a, we removed parity for splink's json saving of models.
This makes sense for pure R since it is replaced with a compressed RDS.

We need to add back support for the JSON and make it work so that it can be passed between the programs.
Look at `inst/refs/` and identify notes on why it was removed and its goals.

Then, re-implement it with fixes.
Add corresponding tests.
It should be explictly tested that if a valid json is given as a model, that we can run predict after.

## Greedy matching (GPT-5.4 high)

You are working on a record linkage package in R.
It is a derivative product of splink (../splink).

We are adding a new feature: simple greedy matching.
This is not a splink feature.

The core idea is that for linking, we should take the best linkings, sorted by highest posterior matches.
In cases of ties, break first by the smaller row index of the first dataset and then by the smaller row index of the second.

When you are done, write a summary to `inst/38-greedy-matching.md`.

## Custom priors (Codex GPT-5.5 medium)

You are working on a record linkage package in R.
It is a derivative product of splink (../splink).

We are adding a new feature: custom priors.
This is not a splink feature.

Read `features.md`, especially the custom-priors section. Treat it as the
source of truth for the API and semantics.

The feature has two distinct concepts:

- regularizing priors, which softly pull EM estimates using finite
  pseudo-count strength;
- fixed constraints, which hold selected parameters fixed and must not be
  implemented as huge prior strengths.

Implement the full feature set described in `features.md`:

- user-facing helpers for prevalence priors and matched-class field priors;
- user-facing helpers for field-level fixed constraints;
- storage on the model in a clear, inspectable form;
- integration with `il_estimate_em()`;
- validation for bad probabilities, bad strengths, unknown columns, malformed
  level distributions, and priors or constraints on comparisons deactivated by
  the EM blocking rule;
- focused tests showing regularizing priors move estimates in the expected
  direction;
- focused tests showing fixed constraints hold the requested parameters fixed;
- save/load round-trip coverage for the new metadata.

If you discover a genuine blocker that prevents implementing one part of the
spec, do not silently omit it. Leave the code in a coherent state, document the
blocker in `inst/39-custom-priors.md`, and make sure unsupported combinations
raise clear errors.

Update user-facing docs as needed.

When you are done, write a summary to `inst/39-custom-priors.md`.
