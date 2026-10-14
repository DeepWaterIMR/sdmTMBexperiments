# The best candidate in a selection table

Looks the best-supported candidate up **in the metric column**, not by
row position, and by default considers only rows the table marks as
comparable.

## Usage

``` r
best_candidate(x, n = 1, by = NULL, comparable_only = TRUE)
```

## Arguments

- x:

  An `sdmTMB_selection` object, or its `table`.

- n:

  Number of candidates to return. Default `1`.

- by:

  Metric to rank by: `"cv"` (per-observation hold-out log-likelihood),
  `"aic"`, or `NULL` (default) to use CV when it is present and AIC
  otherwise.

- comparable_only:

  Consider only rows with `comparable == TRUE`? Default `TRUE`.

## Value

A character vector of candidate names, best first.

## Details

Reading the winner off the first row couples downstream code to how the
table happens to be sorted; a later change of sort key then silently
changes which model the document claims to have selected. Use this
instead — including to build a cross-validation shortlist from an AIC
ladder, via `n`.

## See also

[`sdmTMB_selection()`](https://deepwaterimr.github.io/sdmTMBexperiments/reference/sdmTMB_selection.md)

## Author

Mikko Vihtakari

## Examples

``` r
tab <- data.frame(
  model = c("a", "b", "c"), AIC = c(1002, 1000, 1010),
  comparable = c(TRUE, TRUE, FALSE)
)
best_candidate(tab, n = 2, by = "aic")
#> [1] "b" "a"
```
