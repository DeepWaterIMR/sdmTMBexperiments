# Plot survey comparison results

Plots the results of
[`compare_surveys()`](https://deepwaterimr.github.io/sdmTMBexperiments/reference/compare_surveys.md)
as a time series of indices (`type = "index"`), a scatter plot of survey
vs compiled indices (`type = "scatter"`), or a spatial
prediction-difference map (`type = "spatial"`, on a
[`ggOceanMaps::basemap()`](https://mikkovihtakari.github.io/ggOceanMaps/reference/basemap.html)).

## Usage

``` r
# S3 method for class 'sdmTMB_survey_comparison'
plot(
  x,
  type = "index",
  index_divisor = NULL,
  unit = NA,
  viridis = FALSE,
  annotate_fit = TRUE,
  spatial_response = "mean_pr_diff",
  fill_prefix = NULL,
  transform_color_scale = TRUE,
  limit_rounding = 10,
  break_rounding = 5,
  base_size = 11,
  ...
)
```

## Arguments

- x:

  An object of class `sdmTMB_survey_comparison`.

- type:

  Character. `"index"` (default), `"scatter"` or `"spatial"`.

- index_divisor:

  Optional numeric divisor applied to index values.

- unit:

  Character. Unit label. If `NA`, `"Index value"` is used.

- viridis:

  Logical. Use the viridis palette for survey series? Default `FALSE`.

- annotate_fit:

  Logical. For `type = "scatter"`, annotate each survey's panel-free
  regression line with its fitted equation and R², coloured to match
  that survey? Default `TRUE`.

- spatial_response:

  Character. Column mapped in spatial plots: `"mean"`, `"pr_mean"` or
  `"mean_pr_diff"`. Default `"mean_pr_diff"`. See Details.

- fill_prefix:

  Character. Prefix for the spatial-plot fill legend title
  (`type = "spatial"`), e.g. `"Biomass density"` or `"CPUE"`. If `NULL`
  (default), the legend title is `"Percent anomaly"`; otherwise
  `paste(fill_prefix, "percent anomaly", sep = "\n")`. Surveys don't
  necessarily share a response variable, so this isn't inferred
  automatically.

- transform_color_scale:

  Logical. Apply a signed square-root colour scale for spatial plots?
  Default `TRUE`.

- limit_rounding, break_rounding:

  Numeric rounding for map fill limits and breaks. Defaults `10` and
  `5`.

- base_size:

  Numeric. Base font size. Default `11`.

- ...:

  Currently ignored.

## Value

A `ggplot` object (`type = "index"`/`"scatter"`) or a `cowplot` grid
(`type = "spatial"`).

## Details

For `type = "spatial"`, each grid cell is compared between a survey's
fitted model and the compiled reference model, for every year they
share, on the response scale (i.e. `predict(..., type = "response")`,
e.g. density rather than log density): `diff = est - ref_est` and
`pr_diff = 100 * diff / ref_est` (percent). `spatial_response` selects
how these per-year values are summarised across years into the single
value mapped for each cell:

- `"mean"`: `mean(diff)` — the average absolute difference, in response
  units. Useful for the raw magnitude of disagreement, but not
  comparable across cells with very different baseline abundance.

- `"pr_mean"`: `mean(pr_diff)` — the average of the yearly percent
  differences. Because each year is divided by that year's own (possibly
  small) reference value, a handful of low-abundance years/cells can
  dominate this average with large percentage swings even when the
  absolute difference is small.

- `"mean_pr_diff"` (default): `100 * mean(diff) / mean(ref_est)` — the
  percent difference between the across-year mean predictions (a ratio
  of means, not a mean of ratios). This is usually the more robust
  percent-based summary, since a cell's overall multi-year baseline is
  used in the denominator instead of each individual year's value.

## See also

[`compare_surveys()`](https://deepwaterimr.github.io/sdmTMBexperiments/reference/compare_surveys.md)

## Author

Mikko Vihtakari

## Examples

``` r
# \donttest{
data(sebastes)
sub <- subset(sebastes, cruiseseries %in% c("EcoS", "WinterS") & year >= 2020)
compiled_mesh <- sdmTMB::make_mesh(sub, c("X", "Y"), cutoff = 50)
# `biomass` (raw catch), not `density`, is the response: `density` is
# already swept_area-normalised, so pairing it with the swept_area offset
# below would double-correct for effort.
compiled_model <- sdmTMB::sdmTMB(
  biomass ~ 0 + as.factor(year), data = sub, time = "year",
  mesh = compiled_mesh, family = sdmTMB::tweedie(), spatiotemporal = "off",
  offset = log(sub$swept_area)
)
full_region <- make_survey_prediction_region(sub, crs = 32633, concavity = 5)
full_grid <- sdmTMB::replicate_df(
  make_prediction_grid(full_region, resolution = 20), "year", unique(sub$year)
)
# swept_area is in square nautical miles, so cell area must be too: convert
# the 20 km grid resolution to nautical miles before squaring.
cell_area <- (20 / 1.852)^2
compiled_index <- sdmTMB::get_index_split(
  compiled_model, newdata = full_grid, area = cell_area, nsplit = 3, silent = TRUE
)
#> Bias correction is turned off.
#> It is recommended to turn this on for final inference.
#> Bias correction is turned off.
#> It is recommended to turn this on for final inference.
#> Bias correction is turned off.
#> It is recommended to turn this on for final inference.
sc <- compare_surveys(
  data = sub, compiled_index = compiled_index, compiled_model = compiled_model,
  surveys = c("EcoS", "WinterS"), newdata = full_grid, object_crs = 32633,
  mesh_cutoff = 50, offset_col = "swept_area", area = cell_area
)
#> ⠙ Fitting 2 survey models
#> ✔ Fitting 2 survey models [4ms]
#> 
#> ✔ EcoS: model OK
#> ✔ WinterS: model OK
#> ⠙ Building 2 survey prediction grids
#> ✔ Building 2 survey prediction grids [4ms]
#> 
#> ⠙ Computing 2 survey indices
#> ✔ Computing 2 survey indices [4ms]
#> 
#> ✔ EcoS: index done
#> ✔ WinterS: index done
#> ⠙ Computing spatial prediction differences
#> ✔ Computing spatial prediction differences [4ms]
#> 
#> ✔ EcoS: spatial diff done
#> ✔ WinterS: spatial diff done
plot(sc)                                              # scaled index time series

plot(sc, type = "scatter", annotate_fit = TRUE)       # survey vs compiled

plot(sc, type = "spatial", fill_prefix = "Biomass density") # prediction differences

# }
```
