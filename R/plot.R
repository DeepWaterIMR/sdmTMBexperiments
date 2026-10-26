## Diagnostic and result plotting helpers for fitted sdmTMB models -------------
## All map-producing helpers render onto a ggOceanMaps::basemap() by default,
## which is the package's default map-plotting tool. Model coordinates are
## assumed to be in the units given by `coord_multiplier` (km by default), and
## are multiplied to CRS units (m) for plotting.

#' Plot an sdmTMB mesh on a map
#'
#' @description
#' Draws a [sdmTMB::make_mesh()] mesh over a [ggOceanMaps::basemap()], optionally
#' overlaying the sampling positions as red points. When a barrier mesh is
#' present (e.g. from `sdmTMBextra::add_barrier_mesh()`, from the GitHub-only
#' [sdmTMBextra](https://github.com/pbs-assess/sdmTMBextra) package), the
#' barrier ("land") triangles are marked with an `X`.
#'
#' @param mesh An sdmTMB mesh object (from [sdmTMB::make_mesh()], optionally with
#'   a barrier mesh added).
#' @param crs Coordinate reference system (projected, in metres) used for the
#'   basemap.
#' @param data Optional data frame of sampling positions with coordinate columns
#'   (see `xy_cols`), plotted as red points.
#' @param value Optional character naming a column in `data` used to scale the
#'   point sizes. Note that [ggplot2::scale_size_area()] maps a zero to zero
#'   area, so stations with no catch become invisible; see `zero_col`.
#' @param zero_col Optional colour for stations where `value` is zero, drawn as
#'   small crosses beneath the sized points. `NULL` (default) omits them, which
#'   preserves the behaviour of earlier versions. Zeros usually outnumber the
#'   positive stations by an order of magnitude, so they are drawn small and
#'   faint (see `zero_size` and `zero_alpha`) to avoid burying the response.
#' @param zero_size,zero_alpha Size and alpha of the `zero_col` crosses.
#' @param land_col Optional land fill passed to [ggOceanMaps::basemap()].
#'   `NULL` (default) uses the basemap default.
#' @param lon_interval,lat_interval Optional graticule intervals in degrees,
#'   passed to [ggOceanMaps::basemap()]. `NULL` (default) lets basemap decide.
#' @param utm_axes Logical. If `TRUE`, label the axes in projected kilometres
#'   (the units the model actually uses) rather than in degrees. Default
#'   `FALSE`, which preserves the behaviour of earlier versions.
#' @param xy_cols Character vector of the coordinate columns in `data`. Default
#'   `c("X", "Y")`.
#' @param coord_multiplier Numeric factor to convert model coordinates to CRS
#'   units. Default `1000`.
#' @param base_size Numeric. Base font size. Default `11`.
#'
#' @return A `ggplot` object.
#'
#' @author Mikko Vihtakari
#' @seealso [sdmTMB::make_mesh()], [ggOceanMaps::basemap()]
#' @import ggplot2
#' @examples
#' \donttest{
#' mesh <- sdmTMB::make_mesh(sdmTMB::pcod, c("X", "Y"), cutoff = 15)
#' plot_mesh(mesh, crs = 32609, data = sdmTMB::pcod, value = "density")
#' }
#' @export
plot_mesh <- function(
  mesh,
  crs,
  data = NULL,
  value = NULL,
  zero_col = NULL,
  zero_size = 0.25,
  zero_alpha = 0.1,
  land_col = NULL,
  lon_interval = NULL,
  lat_interval = NULL,
  utm_axes = FALSE,
  xy_cols = c("X", "Y"),
  coord_multiplier = 1000,
  base_size = 11
) {
  if (!requireNamespace("inlabru", quietly = TRUE)) {
    stop("Package 'inlabru' is required for plot_mesh().")
  }
  if (is.null(mesh$mesh)) {
    stop("`mesh` does not look like an sdmTMB make_mesh() object.")
  }

  # A km-unit version of the CRS so the mesh (stored in km) lines up with the
  # basemap and the sampling points.
  mesh_crs <- suppressWarnings(sf::st_crs(crs))
  if (!is.na(mesh_crs$proj4string)) {
    mesh_crs <- suppressWarnings(
      sf::st_crs(sub("units=m", "units=km", mesh_crs$proj4string))
    )
  }

  loc <- as.data.frame(mesh$mesh$loc)
  nodes_sf <- sf::st_as_sf(
    data.frame(X = loc[, 1] * coord_multiplier, Y = loc[, 2] * coord_multiplier),
    coords = c("X", "Y"), crs = suppressWarnings(sf::st_crs(crs))
  )

  basemap_args <- list()
  if (!is.null(land_col)) basemap_args$land.col <- land_col
  if (!is.null(lon_interval)) basemap_args$lon.interval <- lon_interval
  if (!is.null(lat_interval)) basemap_args$lat.interval <- lat_interval
  p <- do.call(.basemap, c(
    list(nodes_sf, crs = mesh_crs, base_size = base_size), basemap_args
  ))

  if (!is.null(data)) {
    if (!is.null(value) && !is.null(zero_col)) {
      zero <- data[!is.na(data[[value]]) & data[[value]] <= 0, , drop = FALSE]
      data <- data[is.na(data[[value]]) | data[[value]] > 0, , drop = FALSE]
      if (nrow(zero) > 0) {
        p <- p + ggplot2::geom_point(
          data = zero,
          mapping = ggplot2::aes(x = .data[[xy_cols[1]]], y = .data[[xy_cols[2]]]),
          shape = 4, size = zero_size, alpha = zero_alpha, color = zero_col
        )
      }
    }
    aes_pts <- if (!is.null(value)) {
      ggplot2::aes(x = .data[[xy_cols[1]]], y = .data[[xy_cols[2]]],
                   size = .data[[value]])
    } else {
      ggplot2::aes(x = .data[[xy_cols[1]]], y = .data[[xy_cols[2]]])
    }
    p <- p +
      ggplot2::geom_point(data = data, mapping = aes_pts, alpha = 0.3,
                          color = "red", shape = 21) +
      ggplot2::scale_size_area()
  }

  p <- p + inlabru::gg(mesh$mesh, edge.color = "black")

  if (!is.null(mesh$barrier_triangles) && length(mesh$barrier_triangles) > 0 &&
      !is.null(mesh$mesh_sf)) {
    barrier_sf <- mesh$mesh_sf[mesh$barrier_triangles, ]
    p <- p + ggplot2::geom_sf(
      data = barrier_sf, shape = 4, size = 2, inherit.aes = FALSE
    )
  }

  if (utm_axes) {
    # `mesh_crs` is the km-unit twin of `crs`, so a graticule on that datum labels the axes in
    # the same kilometres the model fits in. The breaks must be given as explicit numeric values
    # in those kilometres: a breaks *function* is evaluated against the panel range rather than
    # the graticule, which bunches every label into one corner.
    p <- p +
      ggplot2::coord_sf(datum = mesh_crs, expand = FALSE) +
      ggplot2::scale_x_continuous(
        "Easting (UTM, km)", breaks = pretty(range(loc[, 1]), n = 6)
      ) +
      ggplot2::scale_y_continuous(
        "Northing (UTM, km)", breaks = pretty(range(loc[, 2]), n = 6)
      )
  }

  p + ggplot2::theme(legend.position = "none")
}

#' Map predicted densities from an sdmTMB model
#'
#' @description
#' Maps predicted response values from [stats::predict()] output on a
#' [ggOceanMaps::basemap()], either averaged over time (`type = "mean"`) or
#' faceted by time (`type = "annual"`).
#'
#' @param pred A prediction data frame from `predict(fit, newdata = ...)`,
#'   containing coordinate columns and the response column. If the response
#'   column is on the link scale (the default `predict()` output, e.g. log
#'   density for a log-link family), it can be negative; combine with a
#'   suitable `fill_limits` if you want to floor the colour scale, or use
#'   `predict(fit, newdata = ..., type = "response")` for density-scale values.
#' @param crs Coordinate reference system (projected, in metres).
#' @param column Character. Name of the response column. Default `"est"`.
#' @param type Character. `"mean"` (default) or `"annual"`.
#' @param time_col Character. Name of the time column (for `type = "annual"`).
#'   Default `"year"`.
#' @param transform Character. Fill-scale transformation, passed to
#'   `transform` in [ggplot2::continuous_scale()] (the successor to the
#'   now-deprecated `trans` argument). Default `"identity"`.
#' @param fill_limits Numeric vector of length two (either element may be
#'   `NA`), passed to `limits` in [ggplot2::continuous_scale()]. Values outside
#'   the limits are mapped to `NA` by ggplot2 and rendered as blank/grey cells.
#'   Default `NULL`: the scale's range is taken from the data, so no cells are
#'   dropped. Set e.g. `c(0, NA)` to floor a response-scale plot at zero.
#' @param xy_cols Character vector of the coordinate columns. Default
#'   `c("X", "Y")`.
#' @param coord_multiplier Numeric factor to convert coordinates to CRS units.
#'   Default `1000`.
#' @param base_size Numeric. Base font size. Default `11`.
#'
#' @return A `ggplot` object.
#'
#' @author Mikko Vihtakari
#' @seealso [ggOceanMaps::basemap()], [ggplot2::continuous_scale()]
#' @import ggplot2
#' @importFrom rlang .data
#' @examples
#' \donttest{
#' mesh <- sdmTMB::make_mesh(sdmTMB::pcod, c("X", "Y"), cutoff = 20)
#' m <- sdmTMB::sdmTMB(
#'   density ~ 0 + as.factor(year), data = sdmTMB::pcod, time = "year",
#'   mesh = mesh, family = sdmTMB::tweedie()
#' )
#' nd <- sdmTMB::replicate_df(sdmTMB::qcs_grid, "year", unique(sdmTMB::pcod$year))
#' pred <- predict(m, newdata = nd, type = "response")
#' plot_prediction_map(pred, crs = 32609)
#' }
#' @export
plot_prediction_map <- function(
  pred,
  crs,
  column = "est",
  type = c("mean", "annual"),
  time_col = "year",
  transform = "identity",
  fill_limits = NULL,
  xy_cols = c("X", "Y"),
  coord_multiplier = 1000,
  base_size = 11
) {
  type <- match.arg(type)

  d <- pred
  if (type == "mean") {
    d <- d |>
      dplyr::group_by(.data[[xy_cols[1]]], .data[[xy_cols[2]]]) |>
      dplyr::reframe(value = mean(.data[[column]], na.rm = TRUE))
  } else {
    d <- data.frame(
      X = pred[[xy_cols[1]]],
      Y = pred[[xy_cols[2]]],
      value = pred[[column]],
      time = pred[[time_col]]
    )
    names(d)[1:2] <- xy_cols
  }

  if (!is.null(fill_limits)) {
    below <- if (!is.na(fill_limits[1])) d$value < fill_limits[1] else FALSE
    above <- if (!is.na(fill_limits[2])) d$value > fill_limits[2] else FALSE
    if (any(below | above, na.rm = TRUE)) {
      warning(
        "`",
        column,
        "` has values outside `fill_limits` (",
        paste(fill_limits, collapse = ", "),
        "); those cells will render ",
        "as blank/grey.",
        call. = FALSE
      )
    }
  }

  d$.X <- d[[xy_cols[1]]] * coord_multiplier
  d$.Y <- d[[xy_cols[2]]] * coord_multiplier
  d_sf <- sf::st_as_sf(
    d,
    coords = c(".X", ".Y"),
    crs = suppressWarnings(sf::st_crs(crs)),
    remove = FALSE
  )

  p <- .basemap(d_sf, crs = crs, base_size = base_size) +
    ggplot2::geom_raster(
      data = d_sf,
      ggplot2::aes(x = .data$.X, y = .data$.Y, fill = .data$value)
    ) +
    ggplot2::scale_fill_viridis_c(
      transform = transform,
      limits = fill_limits,
      n.breaks = 4
    ) +
    ggplot2::labs(fill = column) +
    ggplot2::theme(
      legend.position = "bottom",
      axis.text = ggplot2::element_blank(),
      axis.title = ggplot2::element_blank(),
      axis.ticks = ggplot2::element_blank()
    )

  if (type == "annual") {
    p <- p + ggplot2::facet_wrap(~time)
  }
  p
}

#' Map spatial or spatiotemporal random fields
#'
#' @description
#' Maps the spatial (`omega`) or spatiotemporal (`epsilon`) random field columns
#' returned by `predict(fit, newdata = ...)` on a [ggOceanMaps::basemap()], using
#' a diverging colour scale. Handles delta models (multiple field columns) by
#' faceting.
#'
#' @param pred A prediction data frame from `predict(fit, newdata = ...)`.
#' @param crs Coordinate reference system (projected, in metres).
#' @param field Character. `"omega"` (spatial, default) or `"epsilon"`
#'   (spatiotemporal).
#' @param time_col Character. Time column for spatiotemporal fields. Default
#'   `"year"`.
#' @param xy_cols Character vector of the coordinate columns. Default
#'   `c("X", "Y")`.
#' @param coord_multiplier Numeric factor to convert coordinates to CRS units.
#'   Default `1000`.
#' @param base_size Numeric. Base font size. Default `11`.
#'
#' @return A `ggplot` object.
#'
#' @author Mikko Vihtakari
#' @seealso [ggOceanMaps::basemap()]
#' @import ggplot2
#' @importFrom rlang .data
#' @examples
#' \donttest{
#' mesh <- sdmTMB::make_mesh(sdmTMB::pcod, c("X", "Y"), cutoff = 20)
#' m <- sdmTMB::sdmTMB(
#'   density ~ 0 + as.factor(year), data = sdmTMB::pcod, time = "year",
#'   mesh = mesh, family = sdmTMB::tweedie()
#' )
#' nd <- sdmTMB::replicate_df(sdmTMB::qcs_grid, "year", unique(sdmTMB::pcod$year))
#' pred <- predict(m, newdata = nd)
#' plot_random_field(pred, crs = 32609, field = "omega")
#' plot_random_field(pred, crs = 32609, field = "epsilon")
#' }
#' @export
plot_random_field <- function(
  pred,
  crs,
  field = c("omega", "epsilon"),
  time_col = "year",
  xy_cols = c("X", "Y"),
  coord_multiplier = 1000,
  base_size = 11
) {
  field <- match.arg(field)
  cols <- grep(paste0("^", field), names(pred), value = TRUE)
  if (length(cols) == 0) {
    stop("No '", field, "' columns found in `pred`. Was the model fitted with ",
         "the corresponding random field, and predicted without `re_form = NA`?")
  }

  keep <- c(xy_cols, cols, if (field == "epsilon") time_col)
  d <- pred[, intersect(keep, names(pred)), drop = FALSE]
  if (field == "omega") {
    d <- unique(d)
  }

  long <- tidyr_pivot_longer(d, cols, xy_cols,
                             time = if (field == "epsilon") time_col else NULL)

  long$.X <- long[[xy_cols[1]]] * coord_multiplier
  long$.Y <- long[[xy_cols[2]]] * coord_multiplier
  d_sf <- sf::st_as_sf(
    long, coords = c(".X", ".Y"), crs = suppressWarnings(sf::st_crs(crs)),
    remove = FALSE
  )

  p <- .basemap(d_sf, crs = crs, base_size = base_size) +
    ggplot2::geom_raster(
      data = d_sf,
      ggplot2::aes(x = .data$.X, y = .data$.Y, fill = .data$value)
    ) +
    ggplot2::scale_fill_gradient2() +
    ggplot2::labs(fill = field) +
    ggplot2::theme(
      legend.position = "bottom",
      axis.text = ggplot2::element_blank(),
      axis.title = ggplot2::element_blank(),
      axis.ticks = ggplot2::element_blank()
    )

  facets <- c(if (length(cols) > 1) "name",
              if (field == "epsilon") "time")
  if (length(facets) > 0) {
    p <- p + ggplot2::facet_wrap(stats::as.formula(
      paste("~", paste(facets, collapse = " + "))
    ))
  }
  p
}

# Minimal long-reshape that avoids a hard tidyr dependency.
tidyr_pivot_longer <- function(d, value_cols, xy_cols, time = NULL) {
  id_cols <- c(xy_cols, time)
  do.call(rbind, lapply(value_cols, function(cn) {
    out <- d[, id_cols, drop = FALSE]
    out$name <- cn
    out$value <- d[[cn]]
    if (!is.null(time)) names(out)[names(out) == time] <- "time"
    out
  }))
}

#' Plot an sdmTMB survey index
#'
#' @description
#' Plots one or more index time series (each from [sdmTMB::get_index()] /
#' [sdmTMB::get_index_split()]) with confidence ribbons. A named list of indices
#' is faceted or coloured by name.
#'
#' @param index A data frame with `year`, `est`, `lwr`, `upr`, or a named list of
#'   such data frames.
#' @param facet Logical. If `index` is a list, facet by name (`TRUE`, default)
#'   rather than colour by name.
#' @param index_unit Optional character for the y-axis label. Default `NA`.
#' @param base_size Numeric. Base font size. Default `11`.
#'
#' @return A `ggplot` object.
#'
#' @author Mikko Vihtakari
#' @import ggplot2
#' @importFrom rlang .data
#' @examples
#' idx <- data.frame(year = 2000:2010, est = runif(11, 5, 9))
#' idx$lwr <- idx$est * 0.8
#' idx$upr <- idx$est * 1.2
#' plot_index(idx)
#' @export
plot_index <- function(index, facet = TRUE, index_unit = NA, base_size = 11) {
  if (!is.data.frame(index) && is.list(index)) {
    index <- dplyr::bind_rows(
      lapply(names(index), function(nm) {
        dplyr::mutate(index[[nm]], index = nm)
      })
    )
    grouped <- TRUE
  } else {
    grouped <- FALSE
  }

  has_ci <- all(c("lwr", "upr") %in% names(index)) && any(!is.na(index$lwr))

  p <- ggplot2::ggplot(index, ggplot2::aes(x = .data$year, y = .data$est))
  if (has_ci) {
    p <- p + ggplot2::geom_ribbon(
      ggplot2::aes(ymin = .data$lwr, ymax = .data$upr),
      alpha = 0.3, fill = "grey", color = NA
    )
  }
  p <- p +
    ggplot2::geom_path() +
    ggplot2::expand_limits(y = 0) +
    ggplot2::labs(
      x = "Year",
      y = if (!is.na(index_unit)) paste0("Index (", index_unit, ")") else "Index value"
    ) +
    ggplot2::theme_bw(base_size = base_size) +
    .index_axis_layers()

  if (grouped && facet) {
    p <- p + ggplot2::facet_wrap(~index, scales = "free_y")
  } else if (grouped) {
    p <- p + ggplot2::aes(color = .data$index) +
      ggplot2::labs(color = NULL) +
      ggplot2::theme(legend.position = "bottom")
  }
  p
}

#' Coefficient plot of sdmTMB fixed effects
#'
#' @description
#' A tidy coefficient plot of the fixed-effect estimates and confidence
#' intervals from [sdmTMB::tidy()]. This is the generic equivalent of a
#' conditional-effects figure: it summarises the fitted parameters rather than
#' predicting over covariate ranges.
#'
#' @param fit A fitted [sdmTMB::sdmTMB()] model.
#' @param base_size Numeric. Base font size. Default `11`.
#'
#' @return A `ggplot` object.
#'
#' @author Mikko Vihtakari
#' @seealso [sdmTMB::tidy()]
#' @import ggplot2
#' @importFrom rlang .data
#' @examples
#' \donttest{
#' mesh <- sdmTMB::make_mesh(sdmTMB::pcod, c("X", "Y"), cutoff = 20)
#' m <- sdmTMB::sdmTMB(
#'   density ~ 0 + as.factor(year) + depth_scaled, data = sdmTMB::pcod,
#'   time = "year", mesh = mesh, family = sdmTMB::tweedie()
#' )
#' plot_fixed_effects(m)
#' }
#' @export
plot_fixed_effects <- function(fit, base_size = 11) {
  if (!inherits(fit, "sdmTMB")) stop("`fit` must be a fitted sdmTMB model.")

  n_models <- length(fit$family$family)
  tab <- dplyr::bind_rows(lapply(seq_len(n_models), function(m) {
    tt <- sdmTMB::tidy(fit, effects = "fixed", conf.int = TRUE, model = m)
    if (nrow(tt) == 0) return(NULL)
    tt$model <- fit$family$family[m]
    tt
  }))
  if (is.null(tab) || nrow(tab) == 0) {
    stop("No fixed effects to plot for this model.")
  }

  p <- ggplot2::ggplot(
    tab,
    ggplot2::aes(x = .data$estimate, y = .data$term)
  ) +
    ggplot2::geom_vline(xintercept = 0, linetype = 2, color = "grey60") +
    ggplot2::geom_pointrange(
      ggplot2::aes(xmin = .data$conf.low, xmax = .data$conf.high)
    ) +
    ggplot2::labs(x = "Estimate (link scale)", y = NULL) +
    ggplot2::theme_bw(base_size = base_size)

  if (n_models > 1) p <- p + ggplot2::facet_wrap(~model, scales = "free_x")
  p
}

#' Variance partitioning of an sdmTMB model
#'
#' @description
#' Partitions the link-scale variance of a fitted sdmTMB model among its
#' random components using [sdmTMB::tidy()], and plots the proportion of that
#' variance from each. This is an approximate, descriptive summary, not a
#' formal variance decomposition.
#'
#' @details
#' Only components whose standard deviation is a marginal SD on the link scale
#' are included:
#' * the spatial field (`sigma_O`) and spatiotemporal field (`sigma_E`);
#' * random intercepts (`sd__(Intercept)`, one per grouping factor);
#' * observation error, only for a `gaussian()` family with an identity link
#'   or a `lognormal()` family, where `phi` is an SD on the link scale.
#'
#' Left out are observation error for other families (for e.g. Tweedie, Gamma
#' or NB2, `phi` is a dispersion or shape parameter, and binomial has none),
#' smooth-term SDs (`sd__s(...)`, the SD of penalised spline coefficients,
#' not of the fitted smooth) and spatially varying coefficient SDs
#' (`sigma_Z`, whose contribution scales with the covariate). The proportions
#' are therefore of the variance of the included components only.
#'
#' @param fit A fitted [sdmTMB::sdmTMB()] model.
#' @param base_size Numeric. Base font size. Default `11`.
#'
#' @return A `ggplot` object.
#'
#' @author Mikko Vihtakari
#' @seealso [sdmTMB::tidy()]
#' @import ggplot2
#' @importFrom rlang .data
#' @examples
#' \donttest{
#' mesh <- sdmTMB::make_mesh(sdmTMB::pcod, c("X", "Y"), cutoff = 20)
#' m <- sdmTMB::sdmTMB(
#'   density ~ 0 + as.factor(year), data = sdmTMB::pcod, time = "year",
#'   mesh = mesh, family = sdmTMB::tweedie()
#' )
#' plot_variance_partitioning(m)
#' }
#' @export
plot_variance_partitioning <- function(fit, base_size = 11) {
  if (!inherits(fit, "sdmTMB")) stop("`fit` must be a fitted sdmTMB model.")

  n_models <- length(fit$family$family)
  tab <- dplyr::bind_rows(lapply(seq_len(n_models), function(m) {
    rp <- sdmTMB::tidy(fit, effects = "ran_pars", model = m)
    fam <- fit$family$family[m]
    link <- fit$family$link[m]
    phi_on_link <- (fam == "gaussian" && link == "identity") ||
      fam == "lognormal"
    keep <- rp$term %in% c("sigma_O", "sigma_E", "sd__(Intercept)") |
      (rp$term == "phi" & phi_on_link)
    rp <- rp[keep & !is.na(rp$estimate), , drop = FALSE]
    if (nrow(rp) == 0) return(NULL)
    rp$variance <- rp$estimate^2
    rp$family <- fam
    # only present when the model has random intercepts
    grp <- if ("group_name" %in% names(rp)) rp$group_name else NA_character_
    rp$component <- ifelse(
      rp$term == "sigma_O", "Spatial (sigma_O)",
      ifelse(rp$term == "sigma_E", "Spatiotemporal (sigma_E)",
             ifelse(rp$term == "phi", "Observation error (phi)",
                    paste0("Random intercept (", grp, ")"))))
    rp$proportion <- rp$variance / sum(rp$variance)
    rp
  }))
  if (is.null(tab) || nrow(tab) == 0) {
    stop("No link-scale random-effect variances found to partition. ",
         "See Details in ?plot_variance_partitioning.")
  }

  p <- ggplot2::ggplot(
    tab, ggplot2::aes(x = .data$component, y = .data$proportion)
  ) +
    ggplot2::geom_col(fill = "grey70", color = "black", linewidth = 0.3) +
    ggplot2::scale_y_continuous(labels = scales::percent_format()) +
    ggplot2::labs(x = "Model component",
                  y = "Approx. proportion of link-scale variance") +
    ggplot2::theme_bw(base_size = base_size) +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 20, hjust = 1))

  if (n_models > 1) p <- p + ggplot2::facet_wrap(~family)
  p
}

#' Histograms of observed and predicted response
#'
#' @description
#' Compares the distribution of the observed response with the distribution of
#' predicted values over the prediction grid, on a `log1p` x-axis, with the means
#' marked. Blue lines indicate mean values.
#'
#' If the model has an offset, the observed response is divided by
#' `exp(offset)` (e.g. catch per unit swept area), so it is on the same scale
#' as predictions made without an offset (as for a prediction grid).
#'
#' @param fit A fitted [sdmTMB::sdmTMB()] model (for the observed response).
#' @param pred A prediction data frame from `predict(fit, newdata = ...)`.
#' @param response Character. Name of the response column in the model data. If
#'   `NULL` (default), taken from the model formula.
#' @param column Character. Predicted column in `pred`. Default `"est"`.
#' @param base_size Numeric. Base font size. Default `11`.
#'
#' @return A `cowplot` grid of two `ggplot` panels.
#'
#' @author Mikko Vihtakari
#' @import ggplot2
#' @importFrom rlang .data
#' @examples
#' \donttest{
#' mesh <- sdmTMB::make_mesh(sdmTMB::pcod, c("X", "Y"), cutoff = 20)
#' m <- sdmTMB::sdmTMB(
#'   density ~ 0 + as.factor(year), data = sdmTMB::pcod, time = "year",
#'   mesh = mesh, family = sdmTMB::tweedie()
#' )
#' nd <- sdmTMB::replicate_df(sdmTMB::qcs_grid, "year", unique(sdmTMB::pcod$year))
#' pred <- predict(m, newdata = nd, type = "response")
#' plot_prediction_histogram(m, pred)
#' }
#' @export
plot_prediction_histogram <- function(fit, pred, response = NULL,
                                       column = "est", base_size = 11) {
  if (!inherits(fit, "sdmTMB")) stop("`fit` must be a fitted sdmTMB model.")
  if (is.null(response)) response <- all.vars(fit$formula[[1]])[1]
  if (!response %in% names(fit$data)) {
    stop("Response column '", response, "' not found in the model data.")
  }

  obs <- data.frame(value = fit$data[[response]])
  has_offset <- !is.null(fit$offset) && any(fit$offset != 0)
  if (has_offset) obs$value <- obs$value / exp(fit$offset)
  prd <- data.frame(value = pred[[column]])

  common <- list(
    ggplot2::scale_x_continuous(
      transform = "log1p",
      breaks = c(1, 10, 100, 1e3, 1e4, 1e5, 1e6),
      expand = ggplot2::expansion(mult = 0.01)
    ),
    ggplot2::theme_bw(base_size = base_size)
  )

  p_obs <- ggplot2::ggplot(obs, ggplot2::aes(x = .data$value)) +
    ggplot2::geom_histogram(bins = 30) +
    ggplot2::geom_vline(xintercept = mean(obs$value, na.rm = TRUE), color = "blue") +
    ggplot2::scale_y_continuous(transform = "log1p", expand = c(0.01, 0)) +
    common +
    ggplot2::labs(
      x = if (has_offset) {
        "log(observed response / exp(offset) + 1)"
      } else {
        "log(observed response + 1)"
      },
      y = "Count"
    )

  p_prd <- ggplot2::ggplot(prd, ggplot2::aes(x = .data$value)) +
    ggplot2::geom_histogram(bins = 30) +
    ggplot2::geom_vline(xintercept = mean(prd$value, na.rm = TRUE), color = "blue") +
    common +
    ggplot2::labs(x = "log(predicted response + 1)", y = "Count")

  cowplot::plot_grid(p_obs, p_prd, ncol = 1, align = "v", labels = "AUTO")
}

#' Quantile-quantile plot of sdmTMB randomized quantile residuals
#'
#' @description
#' Computes randomized quantile residuals for each family component of a fitted
#' sdmTMB model and draws a Q-Q plot. Delta models are faceted by component.
#'
#' @param fit A fitted [sdmTMB::sdmTMB()] model.
#' @param type Character. Residual type passed to [stats::residuals()] (falls
#'   back to `"mle-eb"` if the requested type fails). Default `"mle-mvn"`.
#' @param base_size Numeric. Base font size. Default `11`.
#'
#' @return A `ggplot` object.
#'
#' @author Mikko Vihtakari
#' @seealso [stats::residuals()], `sdmTMB::residuals.sdmTMB()`
#' @import ggplot2
#' @importFrom rlang .data
#' @examples
#' \donttest{
#' mesh <- sdmTMB::make_mesh(sdmTMB::pcod, c("X", "Y"), cutoff = 20)
#' m1 <- sdmTMB::sdmTMB(
#'   density ~ 0 + as.factor(year),
#'   data = sdmTMB::pcod,
#'   time = "year",
#'   mesh = mesh,
#'   family = sdmTMB::delta_lognormal()
#' )
#' # Automatically plots all components of the delta model
#' plot_residual_qq(m1)
#' }
#' @export
plot_residual_qq <- function(fit, type = "mle-mvn", base_size = 11) {
  if (!inherits(fit, "sdmTMB")) stop("`fit` must be a fitted sdmTMB model.")

  fams <- fit$family$family
  res <- dplyr::bind_rows(lapply(seq_along(fams), function(j) {
    r <- try(stats::residuals(fit, type = type, model = j), silent = TRUE)
    if (inherits(r, "try-error")) {
      r <- try(stats::residuals(fit, type = "mle-eb", model = j), silent = TRUE)
    }
    if (inherits(r, "try-error")) return(NULL)
    r <- r[is.finite(r)]
    data.frame(model = fams[j], x = r)
  }))
  if (is.null(res) || nrow(res) == 0) {
    stop("Could not compute residuals for this model.")
  }

  p <- ggplot2::ggplot(res, ggplot2::aes(sample = .data$x)) +
    ggplot2::geom_qq_line() +
    ggplot2::geom_qq(shape = 21, color = "grey60") +
    ggplot2::labs(x = "Theoretical quantiles", y = "Sample quantiles") +
    ggplot2::theme_bw(base_size = base_size)

  if (length(fams) > 1) p <- p + ggplot2::facet_wrap(~model)
  p
}
