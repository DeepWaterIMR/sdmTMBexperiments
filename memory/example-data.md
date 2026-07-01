# Example data: `sebastes`

`data/sebastes.rda` is a compact, public demonstration dataset used by the
survey-comparison and prediction-grid examples/tests/vignette.

## Contents
16,699 bottom-trawl stations, 12 columns: `cruiseseries`, `year`, `month`,
`geartype`, `lon`, `lat`, `X`, `Y` (UTM 33N / EPSG:32633, in km), `depth`,
`swept_area` (nmi^2), `biomass` (kg), `density` (kg/nmi^2). Five surveys
(`EcoS`, `WinterS`, `CoastalS`, `EggaN`, `EggaS`), years 2004–2025, beaked
redfish (*Sebastes mentella*) only. ~0.5 MB (xz-compressed).

## Provenance
Subset of the public station data from the ref-index-paper repository, a public
subset of the NMDC dataset:
- <https://github.com/DeepWaterIMR/ref-index-paper> (`data/public/redfish_station_data.rds`)
- <https://metadata.nmdc.no/metadata-api/landingpage/a22ab5e19ba4e81b2614170bc45e0e06>
- Reference: Vihtakari et al. (2026), ICES JMS 83(2), fsag009,
  <https://doi.org/10.1093/icesjms/fsag009>

## Regeneration
Run `data-raw/sebastes.R`. It downloads the public source, filters to beaked
redfish / 2004–2025 / the five surveys, projects to EPSG:32633 (X/Y in km via
`sdmTMB::add_utm_columns()`), computes `swept_area`, and writes
`data/sebastes.rda` with `usethis::use_data(compress = "xz")`.

## Notes
The name is the genus *Sebastes*; it carries no assessment/redfish-specific
context and is safe for a public, generic package. Keep the dataset small
(< ~1 MB) so it does not bloat the build.
