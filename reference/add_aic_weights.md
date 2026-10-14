# Add delta-AIC and Akaike weights to a comparison table

Adds `deltaAIC` and `AICweight` columns to a data frame that carries an
`AIC` column, and sorts the result so the best-supported model comes
first.

## Usage

``` r
add_aic_weights(x, group = NULL, aic_col = "AIC")
```

## Arguments

- x:

  A data frame with an `AIC` column.

- group:

  Optional column name whose levels delimit comparable sets.

- aic_col:

  Name of the AIC column. Default `"AIC"`.

## Value

`x` with `deltaAIC` and `AICweight` columns, sorted by AIC within group.

## Details

**Akaike weights are only meaningful among models fitted to the same
response data.** A table that mixes fits on different subsets — a
Tweedie over all hauls beside a Gamma over the positive ones, say, or a
biomass model beside an abundance model — has no common likelihood
scale, and weights computed across it would invite exactly the
comparison the table should be warning against. `group` exists for that
case: weights are computed within each group, and left `NA` for groups
with a single member.

## See also

[`sdmTMB_selection()`](https://deepwaterimr.github.io/sdmTMBexperiments/reference/sdmTMB_selection.md)

## Author

Mikko Vihtakari

## Examples

``` r
tab <- data.frame(
  model = c("a", "b", "c"),
  AIC = c(1002, 1000, 1010)
)
add_aic_weights(tab)
#> # A tibble: 3 × 4
#>   model   AIC deltaAIC AICweight
#>   <chr> <dbl>    <dbl>     <dbl>
#> 1 b      1000        0   0.727  
#> 2 a      1002        2   0.268  
#> 3 c      1010       10   0.00490
```
