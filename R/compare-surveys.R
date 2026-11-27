#' Define a survey for compare_surveys()
#'
#' @description
#' Describes one survey index for [compare_surveys()]: which survey series it
#' combines, and any model or prediction-grid settings that differ from the
#' defaults given to [compare_surveys()]. Every argument except `series`
#' defaults to `NULL`, meaning "use the [compare_surveys()] default", which in
#' turn is inherited from the compiled model where possible.
#'
#' Surveys differ in coverage, season, depth range and sampling frequency, so a
#' model that suits the compiled data set rarely suits each survey on its own.
#' A survey sampled every second year, for example, often needs AR(1) or random
#' walk spatiotemporal fields to bridge the gaps, and two series that alternate
#' years can be combined with the series as a fixed effect
#' (`formula = value ~ 0 + cruiseseries + s(depth)`) and predicted for one of
#' them (`predict_values = list(cruiseseries = "SeriesA")`).
#'
#' @param series Character vector of the survey series (values of the
#'   `survey_col` column) included in the survey index.
#' @param formula,family,spatial,spatiotemporal,control Model settings passed
#'   to [sdmTMB::sdmTMB()].
#' @param extra_time Optional numeric vector of extra time steps passed to
#'   [sdmTMB::sdmTMB()], e.g. a year without data inside the series. Indices
#'   are reported only for years with data.
#' @param mesh_cutoff Numeric mesh cutoff (in model units, typically km).
#' @param filter Optional function taking the survey's data frame and
#'   returning a subset of it, e.g. `function(x) subset(x, lat <= 80)`.
#'   Applied after selecting `series`.
#' @param depth_range Optional depth band for the prediction grid: a numeric
#'   vector `c(min, max)`, or `"data"` to use quantiles of the survey's haul
#'   depths (see `depth_quantiles` in [compare_surveys()]). Requires a depth
#'   column in the prediction grid.
#' @param concavity,buffer Concave-hull settings for the survey footprint (see
#'   [make_survey_prediction_region()]). `buffer` is in CRS units (typically
#'   m).
#' @param newdata Optional prediction grid for this survey, used instead of
#'   clipping the common `newdata` given to [compare_surveys()] to the survey
#'   footprint. Useful when the survey extends outside the compiled
#'   prediction domain (e.g. deeper). If it has no time column, it is
#'   replicated over the survey years and the years of the compiled model;
#'   if it has one, it must cover every year of the compiled model for the
#'   same-area comparison. Must contain every predictor of the survey model
#'   (and of the compiled model for the same-area comparison).
#' @param area Grid cell area for `newdata`. Defaults to the `area` given to
#'   [compare_surveys()].
#' @param predict_values Optional named list of values assigned to columns of
#'   the prediction grid before predicting from the survey model, e.g.
#'   `list(cruiseseries = "EggaN")` to predict a multi-series model for one
#'   series.
#'
#' @return A list of class `sdmTMB_survey_spec`.
#'
#' @section AI assistance:
#' AI-assisted (model not recorded); not yet reviewed in full by the current
#' model.
#'
#' @author Mikko Vihtakari
#' @seealso [compare_surveys()]
#' @examples
#' # Two series that alternate years, combined with the series as a fixed
#' # effect and AR(1) fields that bridge the alternating gaps
#' survey_spec(
#'   c("EggaN", "EggaS"),
#'   formula = biomass ~ 0 + cruiseseries + s(depth),
#'   spatiotemporal = "ar1",
#'   predict_values = list(cruiseseries = "EggaN"),
#'   depth_range = "data"
#' )
#' @export
survey_spec <- function(
  series,
  formula = NULL,
  family = NULL,
  spatial = NULL,
  spatiotemporal = NULL,
  control = NULL,
  extra_time = NULL,
  mesh_cutoff = NULL,
  filter = NULL,
  depth_range = NULL,
  concavity = NULL,
  buffer = NULL,
  newdata = NULL,
  area = NULL,
  predict_values = NULL
) {
  if (!is.character(series) || length(series) < 1) {
    stop("`series` must be a character vector of survey series names.")
  }
  if (!is.null(filter) && !is.function(filter)) {
    stop("`filter` must be a function that takes and returns a data frame.")
  }
  if (!is.null(depth_range) && !identical(depth_range, "data") &&
      !(is.numeric(depth_range) && length(depth_range) == 2)) {
    stop("`depth_range` must be NULL, \"data\" or a numeric vector c(min, max).")
  }
  if (!is.null(predict_values) &&
      (!is.list(predict_values) || is.null(names(predict_values)))) {
    stop("`predict_values` must be a named list.")
  }
  structure(
    list(
      series = series, formula = formula, family = family, spatial = spatial,
      spatiotemporal = spatiotemporal, control = control,
      extra_time = extra_time, mesh_cutoff = mesh_cutoff, filter = filter,
      depth_range = depth_range, concavity = concavity, buffer = buffer,
      newdata = newdata, area = area, predict_values = predict_values
    ),
    class = "sdmTMB_survey_spec"
  )
}

#' Turn the `surveys` argument into a named list of survey specifications
#' @keywords internal
#' @noRd
.resolve_surveys <- function(surveys, data, survey_col) {
  if (is.null(surveys)) surveys <- unique(as.character(data[[survey_col]]))
  if (inherits(surveys, "sdmTMB_survey_spec")) {
    stop("Wrap a single survey_spec() in a named list.")
  }
  if (is.character(surveys)) {
    if (is.null(names(surveys))) names(surveys) <- surveys
    surveys <- as.list(surveys)
  }
  if (!is.list(surveys) || is.null(names(surveys)) || any(names(surveys) == "")) {
    stop("A list of surveys must be named; the names are used as survey labels.")
  }
  specs <- lapply(surveys, function(s) {
    if (inherits(s, "sdmTMB_survey_spec")) s else survey_spec(as.character(s))
  })
  missing_series <- setdiff(
    unlist(lapply(specs, `[[`, "series")), unique(data[[survey_col]])
  )
  if (length(missing_series) > 0) {
    stop(
      "Survey series not found in data[[\"", survey_col, "\"]]: ",
      paste(missing_series, collapse = ", ")
    )
  }
  specs
}


#' Compare individual survey indices to a compiled sdmTMB index
#'
#' @description
#' Fits separate sdmTMB models for individual surveys and compares the
#' resulting indices to a compiled reference index. A survey can be one
#' survey series or several series combined, and each survey can have its own
#' model settings and prediction grid (see [survey_spec()]).
#'
#' Two comparisons are made:
#' * **Survey area**: each survey index is predicted over the survey's own
#'   footprint (a concave hull of its hauls, [make_survey_prediction_region()],
#'   optionally limited to a depth band) and plotted against the compiled
#'   index for the whole domain (`plot(type = "index")`). The two cover
#'   different areas, so only their trends are comparable.
#' * **Same area** (`same_area = TRUE`): the survey model and the compiled
#'   model are both predicted over the part of the survey grid inside the
#'   compiled prediction domain, giving two indices of the same quantity for
#'   the same area (`plot(type = "same_area")`). Differences show where the
#'   compiled model, informed by all surveys, departs from what the survey
#'   alone says about its own area.
#'
#' To find which survey carries the signal in the compiled index, refit the
#' compiled model without each survey with [sdmTMB_leave_out()].
#'
#' @param data A data frame containing the modelling data, with a column
#'   identifying the survey series (see `survey_col`) and coordinate columns
#'   (see `xy_cols`).
#' @param compiled_index A data frame of the compiled reference index, with
#'   columns `year`, `est`, `lwr`, `upr`, `se`. A time column named after
#'   `compiled_model$time` (as returned by [sdmTMB::get_index_split()]) is
#'   renamed to `year`. It must be in the same units as the survey indices,
#'   that is, [sdmTMB::get_index_split()] output for `newdata` and `area`
#'   without rescaling; a warning is given when the two differ by more than
#'   1000 times.
#' @param compiled_model A fitted [sdmTMB::sdmTMB()] model for the compiled
#'   index, or `NULL` (default). When provided, all settings of its original
#'   call (as with [sdmTMB::update.sdmTMB()]; e.g. family, random fields, time
#'   column, `spatial_varying`, `priors`, ...), its coordinate columns and CRS
#'   are inherited, except those overridden by `formula`, `family`, `spatial`,
#'   `spatiotemporal`, `control` and `offset_col`, or by a [survey_spec()].
#'   Its `data` and `mesh` are replaced by each survey's data and a new mesh.
#'   A numeric `offset` or `weights` vector in the original call cannot be
#'   carried over to the survey subsets and gives an error (use `offset_col`
#'   or column-name arguments instead). The same-area comparison and spatial
#'   prediction differences are computed. When `NULL`, these are skipped,
#'   `formula`, `family` and `object_crs` must be supplied, and the survey
#'   models use only `formula`, `family`, `spatial`, `spatiotemporal`,
#'   `control`, `offset_col`, a `"year"` time column and the `xy_cols`
#'   coordinates (plus any [survey_spec()] settings).
#' @param surveys Surveys to compare. One of:
#'   * `NULL` (default): every unique value of `data[[survey_col]]`;
#'   * a character vector of series names (names, if given, are used as
#'     labels);
#'   * a named list whose elements are character vectors of series combined
#'     into one survey index, or [survey_spec()] objects with
#'     survey-specific settings, e.g.
#'     `list(EcoS = "EcoS", "Egga N+S" = survey_spec(c("EggaN", "EggaS"), spatiotemporal = "ar1"))`.
#' @param newdata A data frame (the compiled prediction grid, with a time
#'   column) from which survey grids are clipped. Also defines the compiled
#'   domain for the same-area comparison.
#' @param object_crs Coordinate reference system. If `NULL`, taken from
#'   `compiled_model`.
#' @param formula Model formula. If `NULL`, inherited from `compiled_model`.
#' @param family sdmTMB family. If `NULL`, inherited from `compiled_model`.
#' @param spatial,spatiotemporal Random field settings. If `NULL`, inherited from
#'   `compiled_model` (falling back to `"on"`/`"ar1"`).
#' @param control An [sdmTMB::sdmTMBcontrol()] object. If `NULL`, inherited from
#'   `compiled_model` (falling back to `sdmTMBcontrol(newton_loops = 2)`).
#' @param mesh_cutoff Numeric. Default mesh cutoff (in `xy_cols` units,
#'   typically km) for the survey models. Default `30`.
#' @param offset_col Character. Column in `data` to use as a log-offset (e.g.
#'   `"swept_area"`). `NULL` (default) means no offset.
#' @param survey_col Character. Column identifying the survey series. Default
#'   `"cruiseseries"`.
#' @param xy_cols Character vector of the coordinate columns in `data` and
#'   `newdata`. Only used when `compiled_model = NULL`; otherwise taken from
#'   the model mesh. Default `c("X", "Y")`.
#' @param coord_multiplier Numeric factor to convert `xy_cols` to CRS units,
#'   used to build and clip to the survey footprints and to draw the spatial
#'   maps. Default `1000` (coordinates in km, CRS in m); use `1` for
#'   coordinates already in CRS units.
#' @param bias_correct Logical. Apply bias correction? Default `FALSE`.
#' @param level Numeric. Confidence level for index intervals. Default `0.95`.
#' @param area Grid cell area for index calculation: a single value, a column
#'   name in `newdata`, or a numeric vector with one value per row of
#'   `newdata` (subset to each survey's clipped grid). Passed to
#'   [sdmTMB::get_index_split()].
#' @param silent Logical. Suppress model output? Default `TRUE`.
#' @param nsplit Integer. Number of splits for [sdmTMB::get_index_split()].
#'   `NULL` (default) uses about 75 000 grid rows per split, which avoids the
#'   silent crashes of bias-corrected extraction on very large grids.
#' @param n_workers Integer. Number of parallel workers (surveys are processed
#'   in parallel). Default `1`, which uses whatever [future::plan()] is
#'   currently set. Values `> 1` set a temporary parallel plan (forked `future::multicore` where supported,
#'   otherwise `future::multisession`).
#' @param future_seed Logical or integer. Future-compatible random seed.
#' @param concavity Numeric. Default concavity for the survey footprint hulls
#'   (see [make_survey_prediction_region()]). Default `5`.
#' @param buffer Numeric. Default buffer around the survey footprint hulls, in
#'   CRS units (typically m). Default `1`.
#' @param depth_range Default depth band for the survey grids: `NULL` (no
#'   depth limit, the default), a numeric vector `c(min, max)`, or `"data"`
#'   for quantiles of each survey's haul depths.
#' @param depth_quantiles Numeric vector of two probabilities used when
#'   `depth_range = "data"`. Default `c(0.02, 0.98)`.
#' @param depth_col Character. Depth column in `data` and the prediction
#'   grids. Default `"depth"`.
#' @param same_area Logical. Compute the same-area comparison? Default `TRUE`
#'   when `compiled_model` is given.
#' @param compiled_region Optional `sf` polygon of the compiled prediction
#'   domain, used to limit custom survey grids ([survey_spec()] `newdata`) to
#'   the compiled domain for the same-area comparison. If `NULL` (default), a
#'   concave hull of the unique `newdata` coordinates is used. Grids clipped
#'   from `newdata` are inside the domain by construction.
#' @param keep_models Logical. Return the fitted survey models? Default
#'   `FALSE`; models can be large.
#' @param reference_label Character. Label for the compiled reference index.
#'   Default `"Compiled"`.
#' @param verbose Logical. Show progress messages (via \pkg{cli} when installed)?
#'   Default `TRUE`.
#'
#' @return An object of class `sdmTMB_survey_comparison`, a list with
#'   * `sanity`: [sdmTMB::sanity()] results, one column per survey;
#'   * `settings`: one row per survey with the series, number of hauls, years,
#'     depth band, mesh size, number of grid cells and model settings;
#'   * `index`: the indices, with columns `model` (survey label or
#'     `reference_label`), `survey`, `domain` (`"full"` for the compiled index
#'     over the whole domain, `"survey"` for a survey index over its own
#'     footprint, `"shared"` for both models over the same area), `year`,
#'     `est`, `lwr`, `upr`, `se`, `cv`. The time column is always named
#'     `year`;
#'   * `grid`: per-cell prediction differences between each survey model and
#'     the compiled model over the shared area (or `NULL`);
#'   * `models`: the fitted survey models if `keep_models = TRUE`.
#'
#'   Carries `crs`, `coord_multiplier`, `reference_label` and `surveys`
#'   attributes.
#'
#' @section AI assistance:
#' AI-assisted (model not recorded); not yet reviewed in full by the current
#' model.
#'
#' @author Mikko Vihtakari
#' @seealso [survey_spec()], [plot.sdmTMB_survey_comparison()],
#'   [sdmTMB_leave_out()], [compare_models()],
#'   [make_survey_prediction_region()]
#'
#' @importFrom rlang .data
#' @examples
#' \donttest{
#' data(sebastes)
#' sub <- subset(sebastes, cruiseseries %in% c("EcoS", "WinterS") & year >= 2020)
#'
#' # A simple "compiled" full-domain model and index, used as the reference.
#' # `biomass` (raw catch), not `density`, is the response here: `density` is
#' # already swept_area-normalised, so using it together with the swept_area
#' # offset below would double-correct for effort.
#' compiled_mesh <- sdmTMB::make_mesh(sub, c("X", "Y"), cutoff = 50)
#' compiled_model <- sdmTMB::sdmTMB(
#'   biomass ~ 0 + as.factor(year), data = sub, time = "year",
#'   mesh = compiled_mesh, family = sdmTMB::tweedie(), spatiotemporal = "off",
#'   offset = log(sub$swept_area)
#' )
#' full_region <- make_survey_prediction_region(sub, crs = 32633, concavity = 5)
#' full_grid <- sdmTMB::replicate_df(
#'   make_prediction_grid(full_region, resolution = 20), "year", unique(sub$year)
#' )
#' # swept_area is in square nautical miles, so cell area must be too: convert
#' # the 20 km grid resolution to nautical miles before squaring.
#' cell_area <- (20 / 1.852)^2
#' compiled_index <- sdmTMB::get_index_split(
#'   compiled_model, newdata = full_grid, area = cell_area, nsplit = 3, silent = TRUE
#' )
#'
#' # EcoS with the compiled settings, WinterS with its own mesh and fields
#' sc <- compare_surveys(
#'   data = sub, compiled_index = compiled_index, compiled_model = compiled_model,
#'   surveys = list(
#'     EcoS = "EcoS",
#'     WinterS = survey_spec("WinterS", mesh_cutoff = 40, spatial = "off")
#'   ),
#'   newdata = full_grid, object_crs = 32633,
#'   mesh_cutoff = 50, offset_col = "swept_area", area = cell_area
#' )
#' sc$settings
#' plot(sc)
#' plot(sc, type = "same_area")
#' plot(sc, type = "scatter")
#' plot(sc, type = "spatial", fill_prefix = "Biomass density")
#' }
#' @export
compare_surveys <- function(
  data,
  compiled_index,
  compiled_model = NULL,
  surveys = NULL,
  newdata,
  object_crs = NULL,
  formula = NULL,
  family = NULL,
  spatial = NULL,
  spatiotemporal = NULL,
  control = NULL,
  mesh_cutoff = 30,
  offset_col = NULL,
  survey_col = "cruiseseries",
  xy_cols = c("X", "Y"),
  coord_multiplier = 1000,
  bias_correct = FALSE,
  level = 0.95,
  area = 1,
  silent = TRUE,
  nsplit = NULL,
  n_workers = 1,
  future_seed = TRUE,
  concavity = 5,
  buffer = 1,
  depth_range = NULL,
  depth_quantiles = c(0.02, 0.98),
  depth_col = "depth",
  same_area = !is.null(compiled_model),
  compiled_region = NULL,
  keep_models = FALSE,
  reference_label = "Compiled",
  verbose = TRUE
) {
  if (!is.null(compiled_model) && !inherits(compiled_model, "sdmTMB")) {
    stop("`compiled_model` must be a fitted sdmTMB model or NULL.")
  }
  if (!survey_col %in% names(data)) {
    stop("`data` must contain the survey column '", survey_col, "'.")
  }
  if (same_area && is.null(compiled_model)) {
    stop("`same_area = TRUE` requires `compiled_model`.")
  }
  specs <- .resolve_surveys(surveys, data, survey_col)
  surveys <- names(specs)

  # Model settings: user-supplied defaults, then per-survey overrides ---------
  defaults <- list(
    formula = formula, family = family, spatial = spatial,
    spatiotemporal = spatiotemporal, control = control
  )
  if (!is.null(compiled_model)) {
    xy_cols <- compiled_model$spde$xy_cols
    if (is.null(object_crs)) {
      mesh_crs <- compiled_model$spde$mesh$crs
      # make_mesh() has no `crs` argument, so a mesh built the usual way
      # carries an NA (not NULL) crs; catch both, otherwise this silently
      # passes an NA CRS through to the spatial plot.
      if (is.null(mesh_crs) || is.na(sf::st_crs(mesh_crs))) {
        stop("CRS not found in compiled_model mesh. Specify `object_crs`.")
      }
      object_crs <- sf::st_crs(mesh_crs)
    }
    time_col <- compiled_model$time
    .warn_barrier_dropped(compiled_model$spde, "the survey model meshes")
  } else {
    if (is.null(formula)) stop("`formula` must be provided when compiled_model = NULL.")
    if (is.null(family)) stop("`family` must be provided when compiled_model = NULL.")
    if (is.null(object_crs)) stop("`object_crs` must be provided when compiled_model = NULL.")
    if (is.null(spatial)) defaults$spatial <- "on"
    if (is.null(spatiotemporal)) defaults$spatiotemporal <- "ar1"
    if (is.null(control)) defaults$control <- sdmTMB::sdmTMBcontrol(newton_loops = 2)
    time_col <- "year"
  }

  # Arguments of each survey model, evaluated on the main process so that they
  # reach the parallel workers
  model_args <- c("formula", "family", "spatial", "spatiotemporal", "control",
                  "extra_time")
  fit_args <- lapply(specs, function(s) {
    overrides <- defaults
    for (nm in model_args) if (!is.null(s[[nm]])) overrides[nm] <- list(s[[nm]])
    overrides <- overrides[!vapply(overrides, is.null, logical(1))]
    if (!is.null(compiled_model)) {
      # offset_col replaces the original offset (set per survey)
      if (!is.null(offset_col)) overrides["offset"] <- list(NULL)
      do.call(.refit_args, c(list(compiled_model), overrides, subset_ok = FALSE))
    } else {
      c(overrides, list(time = time_col))
    }
  })

  specs <- lapply(specs, function(s) {
    if (is.null(s$mesh_cutoff)) s$mesh_cutoff <- mesh_cutoff
    if (is.null(s$concavity)) s$concavity <- concavity
    if (is.null(s$buffer)) s$buffer <- buffer
    if (is.null(s$depth_range)) s["depth_range"] <- list(depth_range)
    s
  })

  if (!all(xy_cols %in% names(data)) || !all(xy_cols %in% names(newdata))) {
    stop("`data` and `newdata` must contain the coordinate columns ",
         paste(xy_cols, collapse = ", "), ".")
  }
  if (time_col != "year" && time_col %in% names(compiled_index) &&
      !"year" %in% names(compiled_index)) {
    names(compiled_index)[names(compiled_index) == time_col] <- "year"
  }
  # Carry a per-row `area` vector with the grid rows through the clipping
  if (is.numeric(area) && length(area) > 1) {
    .subset_area(area, TRUE, nrow(newdata)) # validate the length
    newdata$.area <- area
    area <- ".area"
  }

  if (same_area && is.null(compiled_region) &&
      any(vapply(specs, function(s) !is.null(s$newdata), logical(1)))) {
    compiled_region <- make_survey_prediction_region(
      unique(newdata[xy_cols]), crs = object_crs, xy_cols = xy_cols,
      coord_multiplier = coord_multiplier, concavity = concavity,
      buffer = buffer
    )
  }
  compiled_depth <- if (depth_col %in% names(newdata)) {
    range(newdata[[depth_col]], na.rm = TRUE)
  } else {
    NULL
  }

  use_cli <- isTRUE(verbose) && requireNamespace("cli", quietly = TRUE)
  step <- function(msg) if (use_cli) cli::cli_progress_step(msg, spinner = TRUE)
  done <- function() if (use_cli) cli::cli_progress_done()
  bad <- function(msg) if (use_cli) cli::cli_alert_danger("{msg}")

  old_parallel <- .setup_parallel(n_workers)
  on.exit(.restore_parallel(old_parallel), add = TRUE)

  # Fit, grid and index per survey -------------------------------------------
  step(paste("Fitting and predicting", length(surveys), "survey models"))
  res <- future.apply::future_lapply(
    surveys,
    function(label) {
      .compare_one_survey(
        label = label, spec = specs[[label]], fit_args = fit_args[[label]],
        data = data, compiled_model = compiled_model, newdata = newdata,
        object_crs = object_crs, survey_col = survey_col, time_col = time_col,
        xy_cols = xy_cols, coord_multiplier = coord_multiplier,
        offset_col = offset_col, depth_col = depth_col,
        depth_quantiles = depth_quantiles, same_area = same_area,
        compiled_region = compiled_region, compiled_depth = compiled_depth,
        area = area, bias_correct = bias_correct, level = level,
        nsplit = nsplit, silent = silent, reference_label = reference_label,
        keep_models = keep_models
      )
    },
    future.seed = future_seed
  )
  names(res) <- surveys
  done()
  for (label in surveys) {
    if (!is.null(res[[label]]$error)) {
      bad(paste0(label, ": model failed: ", res[[label]]$error))
    }
  }

  combined_index <- dplyr::bind_rows(c(
    list(dplyr::mutate(compiled_index, model = reference_label,
                       survey = NA_character_, domain = "full")),
    unname(lapply(res, `[[`, "index"))
  ))
  .check_index_scale(combined_index, reference_label)
  if (!"cv" %in% names(combined_index)) combined_index$cv <- NA_real_
  combined_index$cv <- ifelse(
    is.na(combined_index$cv) & !is.na(combined_index$se),
    sqrt(exp(combined_index$se^2) - 1), combined_index$cv
  )

  out <- list(
    sanity = .sanity_from_list(lapply(res, `[[`, "sanity")),
    settings = dplyr::bind_rows(unname(lapply(res, `[[`, "settings"))),
    index = combined_index,
    grid = if (!is.null(compiled_model)) lapply(res, `[[`, "grid") else NULL
  )
  if (keep_models) out$models <- lapply(res, `[[`, "mod")
  class(out) <- "sdmTMB_survey_comparison"
  attributes(out)$crs <- object_crs
  attributes(out)$coord_multiplier <- coord_multiplier
  attributes(out)$reference_label <- reference_label
  attributes(out)$surveys <- surveys
  out
}

#' Warn when the compiled index is on a different scale from the survey indices
#'
#' A compiled index passed in other units than the survey indices (e.g. kt
#' while the survey indices from `get_index_split()` are in kg) makes the
#' reference line vanish from the plots without an error. A difference of more
#' than three orders of magnitude between the median compiled and median survey
#' index is far beyond what partial survey domains produce.
#'
#' @param index The combined index table.
#' @param reference_label Label of the compiled index rows.
#' @keywords internal
#' @noRd
.check_index_scale <- function(index, reference_label) {
  ref <- index$est[index$model == reference_label & index$domain == "full"]
  srv <- index$est[index$model != reference_label & index$domain == "survey"]
  ref <- stats::median(ref[is.finite(ref) & ref > 0])
  srv <- stats::median(srv[is.finite(srv) & srv > 0])
  if (is.finite(ref) && is.finite(srv) && max(ref / srv, srv / ref) > 1e3) {
    warning(
      "The compiled index (median ", signif(ref, 3), ") and the survey indices ",
      "(median ", signif(srv, 3), ") differ by more than 1000 times. Is ",
      "`compiled_index` in the same units as sdmTMB::get_index_split() output ",
      "for `newdata` and `area` (e.g. kg rather than tonnes or kt)?",
      call. = FALSE
    )
  }
  invisible(NULL)
}

#' Sanity table from a list of unlisted sanity() results
#'
#' Like `.sanity_table()`, but from results already computed on the workers
#' (so the fitted models need not be returned). `NULL` marks a failed fit.
#' @keywords internal
#' @noRd
.sanity_from_list <- function(checks) {
  fitted <- !vapply(checks, is.null, logical(1))
  if (!any(fitted)) {
    out <- as.data.frame(matrix(NA, nrow = 1, ncol = length(checks)))
    names(out) <- names(checks)
    row.names(out) <- "all_ok"
    return(out)
  }
  check_names <- names(checks[[which(fitted)[1]]])
  out <- lapply(checks, function(x) {
    if (is.null(x)) stats::setNames(rep(NA, length(check_names)), check_names)
    else x[check_names]
  })
  as.data.frame(out, row.names = check_names, check.names = FALSE)
}

#' Fit, grid and index one survey for compare_surveys()
#' @keywords internal
#' @noRd
.compare_one_survey <- function(
  label, spec, fit_args, data, compiled_model, newdata, object_crs,
  survey_col, time_col, xy_cols, coord_multiplier, offset_col, depth_col,
  depth_quantiles, same_area, compiled_region, compiled_depth, area,
  bias_correct, level, nsplit, silent, reference_label, keep_models
) {
  x <- data[data[[survey_col]] %in% spec$series, , drop = FALSE]
  if (!is.null(spec$filter)) x <- spec$filter(x)
  x <- droplevels(as.data.frame(x))
  if (nrow(x) == 0) stop("No data left for survey '", label, "'.")
  years <- sort(unique(x[[time_col]]))

  # Prediction grid over the survey footprint ----
  depth_band <- spec$depth_range
  if (identical(depth_band, "data")) {
    if (!depth_col %in% names(x)) {
      stop("`depth_range = \"data\"` needs a '", depth_col, "' column in data.")
    }
    depth_band <- stats::quantile(
      x[[depth_col]], depth_quantiles, na.rm = TRUE, names = FALSE
    )
  }

  custom_grid <- !is.null(spec$newdata)
  grid_area <- area
  if (custom_grid) {
    grid <- as.data.frame(spec$newdata)
    if (!time_col %in% names(grid)) {
      grid_years <- sort(unique(c(years, compiled_model$fitted_time)))
      grid <- sdmTMB::replicate_df(grid, time_col, grid_years)
    }
    grid_area <- spec$area
    if (is.null(grid_area)) {
      if (is.character(area) && !area %in% names(grid)) {
        stop("Give the cell area of the custom grid of '", label,
             "' with survey_spec(area = ).")
      }
      grid_area <- area
    }
    if (is.numeric(grid_area) && length(grid_area) > 1) {
      .subset_area(grid_area, TRUE, nrow(grid))
      grid$.area <- grid_area
      grid_area <- ".area"
    }
  } else {
    region <- make_survey_prediction_region(
      x, crs = object_crs, xy_cols = xy_cols,
      coord_multiplier = coord_multiplier, concavity = spec$concavity,
      buffer = spec$buffer
    )
    grid <- .clip_points_to_region(
      newdata, region, xy_cols = xy_cols, coord_multiplier = coord_multiplier
    )
  }
  if (!is.null(depth_band)) {
    if (!depth_col %in% names(grid)) {
      stop("A depth range was given for '", label, "' but the prediction grid ",
           "has no '", depth_col, "' column.")
    }
    grid <- grid[!is.na(grid[[depth_col]]) &
                   grid[[depth_col]] >= depth_band[1] &
                   grid[[depth_col]] <= depth_band[2], , drop = FALSE]
  }
  # The compiled index needs all its fitted years in the prediction grid
  grid_all <- grid
  grid <- grid[grid[[time_col]] %in% years, , drop = FALSE]
  if (nrow(grid) == 0) stop("The prediction grid for '", label, "' is empty.")

  # Part of the survey grid inside the compiled domain, over all years of the
  # compiled model (`shared_all`) and over the survey years (`shared`)
  shared <- shared_all <- NULL
  if (!is.null(compiled_model)) {
    shared <- grid_all
    if (custom_grid && !is.null(compiled_region)) {
      shared <- .clip_points_to_region(
        shared, compiled_region, xy_cols = xy_cols,
        coord_multiplier = coord_multiplier
      )
    }
    if (custom_grid && !is.null(compiled_depth) && depth_col %in% names(shared)) {
      shared <- shared[shared[[depth_col]] >= compiled_depth[1] &
                         shared[[depth_col]] <= compiled_depth[2], , drop = FALSE]
    }
    shared_all <- shared[shared[[time_col]] %in% compiled_model$fitted_time, , drop = FALSE]
    shared <- shared_all[shared_all[[time_col]] %in% years, , drop = FALSE]
    if (nrow(shared) == 0) shared <- shared_all <- NULL
  }

  survey_values <- function(nd) {
    for (nm in names(spec$predict_values)) nd[[nm]] <- spec$predict_values[[nm]]
    nd
  }

  # Model ----
  mesh <- sdmTMB::make_mesh(x, xy_cols = xy_cols, cutoff = spec$mesh_cutoff)
  args <- fit_args
  if (!is.null(offset_col)) args$offset <- log(x[[offset_col]])
  mod <- try(.refit(args, data = x, mesh = mesh, silent = silent), silent = TRUE)
  fitted <- !inherits(mod, "try-error")

  index_rows <- function(m, nd, model_label, domain) {
    idx <- .safe_index(
      mod = m, newdata = nd, time_col = time_col, nsplit = nsplit,
      bias_correct = bias_correct, level = level, area = grid_area,
      silent = silent, label = paste(model_label, domain)
    )
    if (time_col != "year" && time_col %in% names(idx)) {
      names(idx)[names(idx) == time_col] <- "year"
    }
    idx <- idx[idx$year %in% years, , drop = FALSE]
    tibble::add_column(
      idx, model = model_label, survey = label, domain = domain, .before = 1
    )
  }

  index <- list(index_rows(if (fitted) mod else NULL, survey_values(grid), label, "survey"))
  if (same_area && !is.null(shared)) {
    index <- c(index, list(
      index_rows(if (fitted) mod else NULL, survey_values(shared), label, "shared"),
      index_rows(compiled_model, shared_all, reference_label, "shared")
    ))
  }

  # Spatial prediction differences over the shared area ----
  diff_grid <- NULL
  if (!is.null(shared)) {
    if (fitted) {
      base <- .pred_diff_base(
        mod, compiled_model, survey_values(shared), time_col, xy_cols
      )
      base$reference_model <- reference_label
      base$survey <- label
      diff_grid <- base |>
        dplyr::group_by(.data$reference_model, .data$survey, .data$X, .data$Y) |>
        dplyr::mutate(
          mean_pr_diff = 100 * mean(.data$diff, na.rm = TRUE) /
            mean(.data$ref_est, na.rm = TRUE)
        ) |>
        dplyr::ungroup()
    } else {
      diff_grid <- data.frame(
        reference_model = reference_label, survey = label,
        year = shared[[time_col]],
        X = shared[[xy_cols[1]]], Y = shared[[xy_cols[2]]],
        est = NA, ref_est = NA, diff = NA, pr_diff = NA, mean_pr_diff = NA
      )
    }
  }

  st <- fit_args$spatiotemporal
  fam <- fit_args$family
  form <- fit_args$formula
  settings <- tibble::tibble(
    survey = label,
    series = paste(spec$series, collapse = ", "),
    n_hauls = nrow(x),
    n_years = length(years),
    first_year = min(years),
    last_year = max(years),
    formula = paste(deparse(if (is.list(form)) form[[1]] else form), collapse = " "),
    family = if (is.null(fam)) NA_character_ else paste(fam$family, collapse = "/"),
    spatiotemporal = if (is.null(st)) NA_character_ else
      paste(unique(tolower(unlist(st))), collapse = "/"),
    extra_time = paste(fit_args$extra_time, collapse = ", "),
    mesh_cutoff = spec$mesh_cutoff,
    mesh_vertices = mesh$mesh$n,
    min_depth = if (is.null(depth_band)) NA_real_ else depth_band[1],
    max_depth = if (is.null(depth_band)) NA_real_ else depth_band[2],
    grid_cells = nrow(unique(grid[xy_cols])),
    shared_cells = if (is.null(shared)) 0L else nrow(unique(shared[xy_cols]))
  )

  list(
    mod = if (keep_models) mod else NULL,
    error = if (fitted) NULL else conditionMessage(attr(mod, "condition")),
    sanity = if (fitted) unlist(sdmTMB::sanity(mod, silent = TRUE)) else NULL,
    index = dplyr::bind_rows(index),
    grid = diff_grid,
    settings = settings
  )
}

#' Plot survey comparison results
#'
#' @description
#' Plots the results of [compare_surveys()] as a time series of survey
#' indices over each survey's own area against the compiled index over the
#' whole domain (`type = "index"`), survey and compiled indices over the same
#' area, one panel per survey (`type = "same_area"`), a scatter plot of survey
#' vs compiled indices (`type = "scatter"`), or a spatial prediction-difference
#' map (`type = "spatial"`, on a [ggOceanMaps::basemap()]).
#'
#' @details
#' For `type = "spatial"`, each grid cell is compared between a survey's
#' fitted model and the compiled reference model, for every year they share,
#' on the response scale (i.e. `predict(..., type = "response")`, e.g.
#' density rather than log density): `diff = est - ref_est` and
#' `pr_diff = 100 * diff / ref_est` (percent). `spatial_response` selects how
#' these per-year values are summarised across years into the single value
#' mapped for each cell:
#' * `"mean"`: `mean(diff)` — the average absolute difference, in response
#'   units. Useful for the raw magnitude of disagreement, but not comparable
#'   across cells with very different baseline abundance.
#' * `"pr_mean"`: `mean(pr_diff)` — the average of the yearly percent
#'   differences. Because each year is divided by that year's own (possibly
#'   small) reference value, a handful of low-abundance years/cells can
#'   dominate this average with large percentage swings even when the
#'   absolute difference is small.
#' * `"mean_pr_diff"` (default): `100 * mean(diff) / mean(ref_est)` — the
#'   percent difference between the across-year mean predictions (a ratio of
#'   means, not a mean of ratios). This is usually the more robust
#'   percent-based summary, since a cell's overall multi-year baseline is used
#'   in the denominator instead of each individual year's value.
#'
#' @param x An object of class `sdmTMB_survey_comparison`.
#' @param type Character. `"index"` (default), `"same_area"`, `"scatter"` or
#'   `"spatial"`.
#' @param index_divisor Optional numeric divisor applied to index values.
#' @param unit Character. Unit label. If `NA`, `"Index value"` is used.
#' @param viridis Logical. Use the viridis palette for survey series? Default
#'   `FALSE`.
#' @param annotate_fit Logical. For `type = "scatter"`, annotate each survey's
#'   panel-free regression line with its fitted equation and R², coloured to
#'   match that survey? Default `TRUE`.
#' @param spatial_response Character. Column mapped in spatial plots: `"mean"`,
#'   `"pr_mean"` or `"mean_pr_diff"`. Default `"mean_pr_diff"`. See Details.
#' @param fill_prefix Character. Prefix for the spatial-plot fill legend title
#'   (`type = "spatial"`), e.g. `"Biomass density"` or `"CPUE"`. If `NULL`
#'   (default), the legend title is `"Percent anomaly"`; otherwise
#'   `paste(fill_prefix, "percent anomaly", sep = "\n")`. Surveys don't
#'   necessarily share a response variable, so this isn't inferred automatically.
#' @param transform_color_scale Logical. Apply a signed square-root colour scale
#'   for spatial plots? Default `TRUE`.
#' @param limit_rounding,break_rounding Numeric rounding for map fill limits and
#'   breaks. Defaults `10` and `5`.
#' @param base_size Numeric. Base font size. Default `11`.
#' @param ... Currently ignored.
#'
#' @return A `ggplot` object (`type = "index"`/`"scatter"`) or a `cowplot` grid
#'   (`type = "spatial"`).
#'
#' @section AI assistance:
#' AI-assisted (model not recorded); not yet reviewed in full by the current
#' model.
#'
#' @author Mikko Vihtakari
#' @seealso [compare_surveys()]
#' @import ggplot2
#' @importFrom rlang .data
#' @examples
#' \donttest{
#' data(sebastes)
#' sub <- subset(sebastes, cruiseseries %in% c("EcoS", "WinterS") & year >= 2020)
#' compiled_mesh <- sdmTMB::make_mesh(sub, c("X", "Y"), cutoff = 50)
#' # `biomass` (raw catch), not `density`, is the response: `density` is
#' # already swept_area-normalised, so pairing it with the swept_area offset
#' # below would double-correct for effort.
#' compiled_model <- sdmTMB::sdmTMB(
#'   biomass ~ 0 + as.factor(year), data = sub, time = "year",
#'   mesh = compiled_mesh, family = sdmTMB::tweedie(), spatiotemporal = "off",
#'   offset = log(sub$swept_area)
#' )
#' full_region <- make_survey_prediction_region(sub, crs = 32633, concavity = 5)
#' full_grid <- sdmTMB::replicate_df(
#'   make_prediction_grid(full_region, resolution = 20), "year", unique(sub$year)
#' )
#' # swept_area is in square nautical miles, so cell area must be too: convert
#' # the 20 km grid resolution to nautical miles before squaring.
#' cell_area <- (20 / 1.852)^2
#' compiled_index <- sdmTMB::get_index_split(
#'   compiled_model, newdata = full_grid, area = cell_area, nsplit = 3, silent = TRUE
#' )
#' sc <- compare_surveys(
#'   data = sub, compiled_index = compiled_index, compiled_model = compiled_model,
#'   surveys = c("EcoS", "WinterS"), newdata = full_grid, object_crs = 32633,
#'   mesh_cutoff = 50, offset_col = "swept_area", area = cell_area
#' )
#' plot(sc)                                              # index time series
#' plot(sc, type = "same_area")                          # same-area indices
#' plot(sc, type = "scatter", annotate_fit = TRUE)       # survey vs compiled
#' plot(sc, type = "spatial", fill_prefix = "Biomass density") # prediction differences
#' }
#' @method plot sdmTMB_survey_comparison
#' @export
plot.sdmTMB_survey_comparison <- function(
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
) {
  surveys <- attributes(x)$surveys
  ref <- attributes(x)$reference_label
  type <- match.arg(type, c("index", "same_area", "scatter", "spatial"))

  # Objects from versions before the same-area comparison have no domain
  if (!"domain" %in% names(x$index)) {
    x$index$domain <- ifelse(x$index$model == ref, "full", "survey")
    x$index$survey <- ifelse(x$index$model == ref, NA_character_, x$index$model)
  }
  scale_index <- function(dat) {
    if (is.null(index_divisor)) return(dat)
    dplyr::mutate(
      dat, est = .data$est / index_divisor,
      lwr = .data$lwr / index_divisor, upr = .data$upr / index_divisor
    )
  }

  survey_colors <- stats::setNames(
    .series_colors(length(surveys), viridis), surveys
  )

  if (type == "index") {
    dat <- scale_index(dplyr::filter(x$index, .data$domain %in% c("full", "survey")))
    index_colors <- c(stats::setNames("black", ref), survey_colors)
    fill_colors <- dplyr::recode(index_colors, "black" = "grey")

    return(
      dat |>
        dplyr::mutate(model = factor(.data$model, levels = c(ref, surveys))) |>
        ggplot2::ggplot(ggplot2::aes(
          x = .data$year, y = .data$est, ymin = .data$lwr, ymax = .data$upr,
          color = .data$model, fill = .data$model
        )) +
        ggplot2::geom_ribbon(color = NA, alpha = 0.2) +
        ggplot2::geom_path() +
        ggplot2::scale_color_manual(values = index_colors) +
        ggplot2::scale_fill_manual(values = fill_colors) +
        ggplot2::labs(
          y = if (!is.na(unit)) paste0("Index value (", unit, ")") else "Index value",
          x = "Year", color = "Model", fill = "Model"
        ) +
        ggplot2::expand_limits(y = 0) +
        ggplot2::scale_y_continuous(n.breaks = 6) +
        ggplot2::theme_classic(base_size = base_size) +
        .index_axis_layers() +
        ggplot2::theme(legend.position = "bottom")
    )
  }

  if (type == "same_area") {
    dat <- scale_index(dplyr::filter(x$index, .data$domain == "shared"))
    if (nrow(dat) == 0) {
      stop("No same-area indices. Re-run compare_surveys() with a compiled_model ",
           "and same_area = TRUE.")
    }
    dat$survey <- factor(dat$survey, levels = surveys)
    src_levels <- c(ref, "Survey model")
    dat$source <- factor(ifelse(dat$model == ref, ref, "Survey model"),
                         levels = src_levels)
    return(
      ggplot2::ggplot(dat, ggplot2::aes(
        x = .data$year, y = .data$est, ymin = .data$lwr, ymax = .data$upr,
        color = .data$source, fill = .data$source
      )) +
        ggplot2::geom_ribbon(color = NA, alpha = 0.2) +
        ggplot2::geom_path() +
        ggplot2::facet_wrap(~survey, scales = "free_y") +
        ggplot2::scale_color_manual(
          values = stats::setNames(c("black", "#D55E00"), src_levels)
        ) +
        ggplot2::scale_fill_manual(
          values = stats::setNames(c("grey", "#D55E00"), src_levels)
        ) +
        ggplot2::labs(
          y = if (!is.na(unit)) paste0("Index value (", unit, ")") else "Index value",
          x = "Year", color = "Model", fill = "Model"
        ) +
        ggplot2::expand_limits(y = 0) +
        ggplot2::theme_classic(base_size = base_size) +
        .index_axis_layers() +
        ggplot2::theme(legend.position = "bottom",
                       strip.background = ggplot2::element_blank())
    )
  }

  if (type == "scatter") {
    dat <- scale_index(dplyr::filter(x$index, .data$domain %in% c("full", "survey")))
    ref_dat <- dat |>
      dplyr::filter(.data$model == ref) |>
      dplyr::select("year", ref_est = "est")

    scatter_dat <- dat |>
      dplyr::filter(.data$model != ref) |>
      dplyr::left_join(ref_dat, by = "year")

    p <- ggplot2::ggplot(
        scatter_dat,
        ggplot2::aes(x = .data$ref_est, y = .data$est, color = .data$model)
      ) +
        ggplot2::geom_point() +
        ggplot2::geom_smooth(method = "lm", se = FALSE, formula = y ~ x) +
        ggplot2::scale_color_manual(values = survey_colors)

    if (isTRUE(annotate_fit)) {
      fit_labs <- lapply(surveys, function(s) {
        d <- dplyr::filter(scatter_dat, .data$model == s)
        if (sum(stats::complete.cases(d$ref_est, d$est)) < 2) return(NULL)
        m <- stats::lm(est ~ ref_est, data = d)
        cf <- stats::coef(m)
        if (anyNA(cf)) return(NULL) # e.g. a flat index
        r2 <- summary(m)$r.squared
        sign_op <- if (cf[2] < 0) "-" else "+"
        data.frame(
          model = s,
          label = sprintf(
            "y = %.3g %s %.3gx\nR\u00B2 = %.2f", cf[1], sign_op, abs(cf[2]), r2
          )
        )
      }) |>
        dplyr::bind_rows()
    }
    # No survey with two or more index years (e.g. every survey model failed):
    # nothing to annotate.
    if (isTRUE(annotate_fit) && nrow(fit_labs) > 0) {
      fit_labs$model <- factor(fit_labs$model, levels = surveys)
      fit_labs <- fit_labs[order(fit_labs$model), ]
      fit_labs$vjust <- seq_len(nrow(fit_labs)) * 2.2 - 1

      p <- p + ggplot2::geom_text(
        data = fit_labs,
        ggplot2::aes(
          x = -Inf, y = Inf, label = .data$label, color = .data$model,
          vjust = .data$vjust
        ),
        hjust = -0.08, size = base_size / 3.5, inherit.aes = FALSE,
        show.legend = FALSE
      )
    }

    return(
      p +
        ggplot2::labs(
          x = if (!is.na(unit)) paste0(ref, " index (", unit, ")") else paste0(ref, " index"),
          y = if (!is.na(unit)) paste0("Survey index (", unit, ")") else "Survey index",
          color = "Survey"
        ) +
        ggplot2::theme_classic(base_size = base_size) +
        ggplot2::theme(legend.position = "bottom")
    )
  }

  if (type == "spatial") {
    if (is.null(x$grid)) {
      stop("No spatial grid available. Re-run compare_surveys() with a compiled_model.")
    }
    # The bare "Percent anomaly" (no "Biomass density" prefix) default only
    # applies to percent-based responses; a "mean" (absolute) response keeps
    # .spatial_diff_map()'s own label so it isn't mislabelled as a percent.
    is_pct_response <- spatial_response %in% .pct_spatial_responses
    return(cowplot::plot_grid(
      plotlist = lapply(seq_along(x$grid), function(i) {
        p <- .spatial_diff_map(
          grid = x$grid[[i]], crs = attributes(x)$crs,
          spatial_response = spatial_response, unit = unit,
          transform_color_scale = transform_color_scale,
          limit_rounding = limit_rounding, break_rounding = break_rounding,
          base_size = base_size, title = paste(names(x$grid)[i], "vs", ref),
          fill_prefix = fill_prefix,
          coord_multiplier = .coord_multiplier(x)
        )
        if (is_pct_response) {
          fill_lab <- if (is.null(fill_prefix)) {
            "Percent anomaly"
          } else {
            paste(fill_prefix, "percent anomaly", sep = "\n")
          }
          p <- p + ggplot2::labs(fill = fill_lab)
        }
        p
      })
    ))
  }
}
