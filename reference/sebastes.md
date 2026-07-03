# Beaked redfish survey stations (example data)

A compact, public example dataset of bottom-trawl survey stations for
beaked redfish (*Sebastes mentella*) in the Barents and Norwegian Seas,
used to demonstrate the survey-comparison and prediction-grid functions.

## Usage

``` r
sebastes
```

## Format

A data frame with 16,699 rows and 12 columns:

- cruiseseries:

  Survey series identifier (the "survey" grouping).

- year:

  Year of the survey (integer).

- month:

  Month of the station (integer).

- geartype:

  Trawl gear type.

- lon, lat:

  Station longitude and latitude (decimal degrees).

- X, Y:

  Projected coordinates (UTM zone 33N, EPSG:32633) in kilometres.

- depth:

  Bottom depth at the station start (m).

- swept_area:

  Swept area (square nautical miles); usable as a log-offset for catch
  models.

- biomass:

  Catch biomass (kg).

- density:

  Swept-area biomass density (kg per square nautical mile).

## Source

Public station data from the ref-index-paper repository
(<https://github.com/DeepWaterIMR/ref-index-paper>), a public subset of
the NMDC dataset
(<https://metadata.nmdc.no/metadata-api/landingpage/a22ab5e19ba4e81b2614170bc45e0e06>).
Prepared by `data-raw/sebastes.R`.

## Details

It is a subset of the public station data accompanying Vihtakari et al.
(2026): beaked redfish only, years 2004-2025, and five surveys with good
coverage (`EcoS`, `WinterS`, `CoastalS`, `EggaN`, `EggaS`). Coordinates
are projected to UTM zone 33N (EPSG:32633) and stored in kilometres,
following the sdmTMB convention.

## References

Vihtakari, M., Aune, M., Assmann, K. M., Howell, D., Hallfredsson, E.
H., and Ward, E. J. (2026). Demersal distribution and fisheries
independent trends of beaked and golden redfish in the Barents and
Norwegian Seas. ICES Journal of Marine Science, 83(2), fsag009.
[doi:10.1093/icesjms/fsag009](https://doi.org/10.1093/icesjms/fsag009)

## Examples

``` r
data(sebastes)
table(sebastes$cruiseseries)
#> 
#> CoastalS     EcoS    EggaN    EggaS  WinterS 
#>     3986     4465     1933      392     5923 
```
