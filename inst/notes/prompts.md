# prompts

These are the major prompts, organized by stage.
I am not going to track every minor back and forth, like tool calls or requests for information.
I will track any meaningful stage or substage prompts and any decisions made in minor back and forths.

This is organized by stage.

# Scope and structure

## Starter prompt (Opus 4.6 high)

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
