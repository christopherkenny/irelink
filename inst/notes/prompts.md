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

# Speed

Let's get a rough idea of speed.
Can you look at this blog post <https://www.robinlinacre.com/fast_deduplication/> and run the same thing for our codebase?
Don't rerun any of the other systems, just get use this to eyeball how we are doing.

If we're behind, identify what we might need to fix.

## follow up

Write these updates to `inst/refs/16-performance.md`.

Also review the description: it looks like we have some packages as "suggests" but use them unconditionally.
That needs to be fixed by upgrading them to imports.

Then, can you run the blog post examples and see how we do now that you patched duckdb?

# Missing features

I had another Claude look at this and it found some issues.

Most important:

term_frequency is not implemented -- it silently does nothing.

The term_frequency = TRUE flag is accepted by cl_exact() and stored on the comparison level object (there's even a test that checks lev$term_frequency == TRUE), but it is never read anywhere downstream. Neither utils-sql.R, utils-scoring.R, nor predict.R reference term_frequency at all.

The inst/refs/07-features-for-later.md file explicitly deferred it: "Term-frequency tables will be computed internally by cl_exact(term_frequency = TRUE)" -- meaning the intent was there but it was never built.

The risk: The benchmark at inst/benchmarks/rl-workshop.qmd uses cl_exact(term_frequency = TRUE) on city, which will produce the same result as cl_exact() with no flag. If someone benchmarks against splink using TF weighting enabled, the results will quietly differ.

## follow up

Things to verify before asking for feedback:

link_and_dedupe mode -- the from_splink vignette lists it as supported, but the explore found it may be incomplete. Worth checking whether il_model() actually handles it correctly end-to-end.

il_find_matches() -- the README doesn't cover it, but the from_splink vignette maps it. Worth a quick smoke test to make sure it runs correctly with a trained model.

The fake_1000_links demo dataset -- the two halves are just a random split of the same 1000-record pool rather than a true held-out linked dataset. This means the "linking" demo doesn't actually demonstrate cross-dataset linkage in a meaningful way. Splink's demo data has genuine cross-dataset pairs. This could confuse someone benchmarking against splink.

What's genuinely missing vs splink:

No equivalent to splink's linker.visualisations.* charts -- only autoplot() for match weights. Splink's waterfall chart, parameter estimate comparisons, and unlinkables chart are popular; if those aren't rendered as interactive HTML, that's a notable gap.
No phonetic blocking (Soundex, Metaphone). Splink doesn't have it either out of the box, but it's a common ask.
No batched/incremental retraining API.


#

explain use of stringdist == bad and get rid of places where we do large computations outside of duckdb/the sql engine
