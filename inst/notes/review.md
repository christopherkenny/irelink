# Handled in interactive Codex session with GPT 5.5 medium/Claude Code Sonnet 4.6 medium

- [x] autoplot: should formatC be used here or is this excessive?
- [x] Rename the geographic distance constructor to cl_geo_distance().
- [x] data.R: Clean up the old style latex to use modern roxygen2 markdown.
- [x] bad `if else` patterns. There should never be assignment EVER of the form `x <- if ()`, nor `x <- if () ... else ...`. Clean up every case of that to use a proper approach.
- [x] `il_cleanup_all()` doesn't contain an actual example. It requires one, even if minor.
- [x] `il_regex_extract()` docs are out of date.
- [x] `il_comparator_score` docs are out of date too.
- [x] All autoplot.* functions should be defined in `autoplot.R`.
- [x] We use tidyselect in a lot of places, but it is a suggests. Weigh in on if it is used in sufficient locations to upgrade it to an imports.
- [x] There are a small number of \dontrun statements. These are not acceptable for package code. Identify how each use should be made into proper package code that runs and fix it.
- [x] In some examples, I see things like throwaway renames, like df <- fake_20, which are both unnecessary and reduce clarity. search for cases like that and fix them.
- [x] Remove fake legacy updater `migrate_params_to_gamma_level()`.
- [x] There are inconsistent cross-package references. When referencing an object or function from another package, we should do our best to use the proper references so pkgdown can generate links on the website.
- [x] I spy some uses of `<<-` and `->` within package code, which is absolutely not ever allowed. Please rewrite those to be properly scoped and avoid hacks.
- [x] Classes are somewhat inconsistently defined, with many of them being thrown into `utils-classes.R`. Let's correct this and move all of the class creators into the correct files. For example, move new_il_spec to il_spec.R.
- [x] Some functions have hard coded colors in (searching `'#` returns a number of them). Remove every case of this and allow colors and fills to be ggplot defaults
- [x] There remain some britishisms in the code. Can you please make the code use proper English? For example, neighbors is wrong.
- [x] Package code should not have random section markers in it. `  # ---- tbl_lazy ([dbplyr::tbl_lazy] table reference) ----` for example, needs to go. Find all cases and variations of this within the R folder and remove them.
