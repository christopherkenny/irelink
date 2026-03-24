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
