# Complete-case frame for a set of model-selection candidates

Drops every row that is missing a variable used by *any* candidate, so
that all candidates are fitted to identical records.

## Usage

``` r
selection_frame(data, candidates, formula = NULL, extra = NULL)
```

## Arguments

- data:

  A data frame.

- candidates:

  A named list of candidates, as accepted by
  [`sdmTMB_selection()`](https://deepwaterimr.github.io/sdmTMBexperiments/reference/sdmTMB_selection.md):
  each element a formula, or a list that may contain a `formula`
  element.

- formula:

  Optional default formula for candidates that do not carry one.

- extra:

  Character vector of further columns that must also be complete (e.g.
  the coordinate columns, the time column, or an offset column).

## Value

`data` with incomplete rows removed. The number of dropped rows and the
columns that were checked are attached as the `"dropped"` and
`"columns"` attributes.

## Details

This is the precondition that makes a selection table mean anything.
Information criteria and cross-validated log-likelihoods are only
comparable between models fitted to the same response data; if one
candidate carries `s(depth)` and another does not, and `depth` has gaps,
[`sdmTMB()`](https://sdmTMB.github.io/sdmTMB/reference/sdmTMB.html)
silently drops different rows for each and the resulting AIC column
compares two different quantities.

Build the selection frame once, select on it, then fit the *chosen*
specification to the full data: there is no reason to keep discarding
records because a covariate that did not enter the model is missing for
them.

## See also

[`sdmTMB_selection()`](https://deepwaterimr.github.io/sdmTMBexperiments/reference/sdmTMB_selection.md)

## Author

Mikko Vihtakari

## Examples

``` r
cands <- list(
  "Full" = density ~ 0 + as.factor(year) + depth_scaled,
  "No depth" = density ~ 0 + as.factor(year)
)
d <- selection_frame(sdmTMB::pcod, cands, extra = c("X", "Y"))
attr(d, "dropped")
#> [1] 0
```
