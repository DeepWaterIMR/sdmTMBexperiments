# Mohn's rho for a set of index series

Computes Mohn's rho, the mean relative bias between the terminal-year
estimate of each non-reference series (e.g. a retrospective peel or an
alternative model) and the reference series estimate in that same year.

This is the shared engine used by the plotting methods of
[`sdmTMB_retro()`](https://deepwaterimr.github.io/sdmTMBexperiments/reference/sdmTMB_retro.md),
[`compare_models()`](https://deepwaterimr.github.io/sdmTMBexperiments/reference/compare_models.md)
and
[`compare_meshes()`](https://deepwaterimr.github.io/sdmTMBexperiments/reference/compare_meshes.md),
exposed so it can be used directly on any long-format table of index
series.

## Usage

``` r
mohns_rho(
  data,
  group_col,
  reference,
  year_col = "year",
  est_col = "est",
  exclude_crashed = TRUE
)
```

## Arguments

- data:

  A long-format data frame containing at least the grouping column, a
  year column, and an estimate column.

- group_col:

  Character. Name of the column identifying the series (e.g. `"peel"`,
  `"model"`, `"cutoff"`).

- reference:

  The value of `group_col` that identifies the reference series to
  compare against.

- year_col:

  Character. Name of the year column. Default `"year"`.

- est_col:

  Character. Name of the estimate column. Default `"est"`.

- exclude_crashed:

  Logical. Drop rows whose `type` column equals `"crashed"` before
  computing? Default `TRUE`.

## Value

A single numeric value (the mean relative bias). Returns `NA` if no
valid comparisons can be made.

## Details

For each non-reference series \\p\\ the terminal (maximum) year \\T_p\\
is found, and the relative bias is \$\$b_p = \frac{\hat{I}\_p^{(T_p)} -
\hat{I}\_{ref}^{(T_p)}}{\hat{I}\_{ref}^{(T_p)}}.\$\$ Mohn's rho is the
mean of these relative biases: \$\$\rho = \frac{1}{P} \sum\_{p=1}^{P}
b_p.\$\$

## Author

Mikko Vihtakari

## Examples

``` r
idx <- data.frame(
  peel = rep(c("peel 0", "peel 1", "peel 2"), each = 5),
  year = rep(2016:2020, 3),
  est = c(
    10, 11, 12, 13, 14,
    10, 11, 12, 13.5, NA,
    10, 11, 12.5, NA, NA
  )
)
# peel 1 terminal year is 2019, peel 2 terminal year is 2018:
mohns_rho(idx, group_col = "peel", reference = "peel 0")
#> [1] 0.0400641
```
