# Plot an sdmTMB survey index

Plots one or more index time series (each from
[`sdmTMB::get_index()`](https://sdmTMB.github.io/sdmTMB/reference/get_index.html)
/
[`sdmTMB::get_index_split()`](https://sdmTMB.github.io/sdmTMB/reference/get_index.html))
with confidence ribbons. A named list of indices is faceted or coloured
by name.

## Usage

``` r
plot_index(index, facet = TRUE, index_unit = NA, base_size = 11)
```

## Arguments

- index:

  A data frame with `year`, `est`, `lwr`, `upr`, or a named list of such
  data frames.

- facet:

  Logical. If `index` is a list, facet by name (`TRUE`, default) rather
  than colour by name.

- index_unit:

  Optional character for the y-axis label. Default `NA`.

- base_size:

  Numeric. Base font size. Default `11`.

## Value

A `ggplot` object.

## Author

Mikko Vihtakari

## Examples

``` r
idx <- data.frame(year = 2000:2010, est = runif(11, 5, 9))
idx$lwr <- idx$est * 0.8
idx$upr <- idx$est * 1.2
plot_index(idx)
```
