#' Spatial cross-validation across mesh cutoff values
#'
#' @description
#' Compares alternative mesh resolutions for an sdmTMB model using spatial
#' block cross-validation. Spatial folds are created with
#' [blockCV::cv_spatial()] and each mesh is evaluated with
#' [sdmTMB::sdmTMB_cv()] using the same folds, so that predictive performance
#' (sum of hold-out log-likelihoods and AIC) can be compared on an equal
#' footing.
#'
#' This is a parameterised version of an exploratory workflow: all model
#' settings are inherited from the fitted `object`, and nothing about the data
#' is assumed beyond the coordinate and response columns.
#'
#' @param object A fitted [sdmTMB::sdmTMB()] model. Model settings (formula,
#'   family, spatial and spatiotemporal structure, time column) are inherited.
#' @param mesh_cutoffs Numeric vector of mesh cutoff values to compare.
#' @param k Integer. Number of cross-validation folds. Default `3`.
#' @param block_size Numeric. Spatial block size in CRS units (e.g. metres). If
#'   `NULL` (default) a heuristic based on the data extent is used.
#' @param response Character. Name of the response column used to build
#'   presence/absence blocks for [blockCV::cv_spatial()]. If `NULL` (default),
#'   taken from the model formula's left-hand side.
#' @param xy_cols Character vector of the coordinate columns. Default
#'   `c("X", "Y")`.
#' @param coord_multiplier Numeric factor to convert `xy_cols` to CRS units.
#'   Default `1000`.
#' @param object_crs Coordinate reference system. If `NULL`, taken from the
#'   model mesh.
#' @param control An [sdmTMB::sdmTMBcontrol()] object for the CV fits. If `NULL`,
#'   inherited from `object`.
#' @param n_workers Integer. Number of parallel workers. Default `1`.
#' @param future_seed Logical or integer. Future-compatible random seed.
#' @param silent Logical. Suppress fitting output? Default `TRUE`.
#'
#' @return A data frame (tibble) of class `sdmTMB_mesh_cv` with one row per
#'   cutoff: `cutoff`, `crashed`, `converged`, `sanity`, `sum_loglik` (the
#'   summed hold-out log-likelihood from [sdmTMB::sdmTMB_cv()]; higher is
#'   better), `mean_aic`, and the derived `deltaNLL`, `deltaNLL_pr`,
#'   `deltaAIC`, `deltaAIC_pr`. `deltaNLL`/`deltaAIC` are relative to the
#'   best-fitting cutoff (`0` = best; lower is better, mirroring AIC). The
#'   list of [sdmTMB::sdmTMB_cv()] objects is attached as the `"cv"`
#'   attribute.
#'
#' @author Mikko Vihtakari
#' @seealso [sdmTMB::sdmTMB_cv()], [blockCV::cv_spatial()], [compare_meshes()]
#'
#' @importFrom rlang .data
#' @examples
#' \donttest{
#' # Requires the 'blockCV' package.
#' mesh <- sdmTMB::make_mesh(sdmTMB::pcod, c("X", "Y"), cutoff = 20)
#' fit <- sdmTMB::sdmTMB(
#'   data = sdmTMB::pcod, formula = density ~ 0 + as.factor(year),
#'   time = "year", mesh = mesh, family = sdmTMB::tweedie(link = "log")
#' )
#' cv <- sdmTMB_mesh_cv(fit, mesh_cutoffs = c(15, 30), k = 3)
#' cv
#' plot(cv)
#' }
#' @export
sdmTMB_mesh_cv <- function(
  object,
  mesh_cutoffs,
  k = 3,
  block_size = NULL,
  response = NULL,
  xy_cols = c("X", "Y"),
  coord_multiplier = 1000,
  object_crs = NULL,
  control = NULL,
  n_workers = 1,
  future_seed = TRUE,
  silent = TRUE
) {
  if (!inherits(object, "sdmTMB")) {
    stop("`object` must be a fitted sdmTMB model.")
  }
  if (!requireNamespace("blockCV", quietly = TRUE)) {
    stop("Package 'blockCV' is required for sdmTMB_mesh_cv().")
  }

  dt <- object$data
  if (!all(xy_cols %in% names(dt))) {
    stop("The model data must contain the coordinate columns ",
         paste(xy_cols, collapse = ", "), ".")
  }

  if (is.null(object_crs)) {
    if (is.null(object$spde$mesh$crs)) {
      stop("Model CRS not found in the mesh object. Specify `object_crs`.")
    }
    object_crs <- sf::st_crs(object$spde$mesh$crs)
  }
  if (is.null(control)) control <- object$control

  model_formula <- if (length(object$formula) > 1) {
    object$formula
  } else {
    object$formula[[1]]
  }
  if (is.null(response)) {
    response <- all.vars(if (is.list(model_formula)) model_formula[[1]] else model_formula)[1]
  }
  if (!response %in% names(dt)) {
    stop("Response column '", response, "' not found in the model data.")
  }

  # Heuristic default block size: roughly the data extent divided by 2k.
  if (is.null(block_size)) {
    ext <- c(diff(range(dt[[xy_cols[1]]])), diff(range(dt[[xy_cols[2]]])))
    block_size <- max(ext) * coord_multiplier / (2 * k)
  }

  # Meshes --------------------------------------------------------------------
  meshes <- lapply(mesh_cutoffs, function(cut) {
    sdmTMB::make_mesh(dt, xy_cols = xy_cols, cutoff = cut)
  })
  names(meshes) <- mesh_cutoffs

  # Spatial folds -------------------------------------------------------------
  dt_sf <- dt
  dt_sf[[xy_cols[1]]] <- dt_sf[[xy_cols[1]]] * coord_multiplier
  dt_sf[[xy_cols[2]]] <- dt_sf[[xy_cols[2]]] * coord_multiplier
  dt_sf$presence <- dt[[response]] > 0
  dt_sf <- sf::st_as_sf(
    dt_sf, coords = xy_cols, crs = suppressWarnings(sf::st_crs(object_crs))
  )

  cvb <- blockCV::cv_spatial(
    x = dt_sf, column = "presence", k = k, size = block_size,
    progress = FALSE, report = FALSE, plot = FALSE
  )

  old_plan <- .setup_parallel(n_workers)
  on.exit(future::plan(old_plan), add = TRUE)

  # Cross-validated fits per mesh ---------------------------------------------
  mcvs <- future.apply::future_lapply(
    seq_along(meshes),
    function(j) {
      try(
        sdmTMB::sdmTMB_cv(
          formula = model_formula,
          data = dt,
          mesh = meshes[[j]],
          time = object$time,
          family = object$family,
          spatial = lapply(object$spatial, function(g) g),
          spatiotemporal = lapply(object$spatiotemporal, function(g) g),
          control = control,
          fold_ids = cvb$folds_ids
        ),
        silent = TRUE
      )
    },
    future.seed = future_seed
  )
  names(mcvs) <- mesh_cutoffs

  # Metrics table -------------------------------------------------------------
  tab <- lapply(seq_along(mcvs), function(i) {
    if (inherits(mcvs[[i]], "try-error")) {
      tibble::tibble(
        cutoff = as.integer(names(mcvs)[i]), crashed = TRUE,
        converged = FALSE, sanity = FALSE, sum_loglik = NA_real_,
        mean_aic = NA_real_
      )
    } else {
      tibble::tibble(
        cutoff = as.integer(names(mcvs)[i]),
        crashed = FALSE,
        converged = isTRUE(mcvs[[i]]$converged),
        sanity = all(vapply(
          mcvs[[i]]$models,
          function(m) all(unlist(sdmTMB::sanity(m, silent = TRUE))),
          logical(1)
        )),
        sum_loglik = mcvs[[i]]$sum_loglik,
        mean_aic = mean(vapply(mcvs[[i]]$models, stats::AIC, numeric(1)))
      )
    }
  }) |>
    dplyr::bind_rows() |>
    dplyr::arrange(dplyr::desc(.data$sum_loglik)) |>
    dplyr::mutate(
      # sum_loglik is a log-likelihood (higher = better); NLL flips the sign
      # so that, like AIC, lower (0 = best) indicates the better-fitting mesh.
      deltaNLL = -.data$sum_loglik - min(-.data$sum_loglik, na.rm = TRUE),
      deltaNLL_pr = 100 * (-.data$sum_loglik / min(-.data$sum_loglik, na.rm = TRUE) - 1),
      deltaAIC = .data$mean_aic - min(.data$mean_aic, na.rm = TRUE),
      deltaAIC_pr = 100 * (.data$mean_aic / min(.data$mean_aic, na.rm = TRUE) - 1)
    )

  class(tab) <- c("sdmTMB_mesh_cv", class(tab))
  attr(tab, "cv") <- mcvs
  tab
}

#' Plot mesh cross-validation results
#'
#' @param x An object of class `sdmTMB_mesh_cv` from [sdmTMB_mesh_cv()].
#' @param metric Character. Which metric to plot: `"deltaNLL"` (default),
#'   `"sum_loglik"`, or `"deltaAIC"`.
#' @param base_size Numeric. Base font size. Default `11`.
#' @param ... Currently ignored.
#'
#' @return A `ggplot` object.
#' @author Mikko Vihtakari
#' @seealso [sdmTMB_mesh_cv()]
#' @import ggplot2
#' @importFrom rlang .data
#' @examples
#' \donttest{
#' # Requires the 'blockCV' package.
#' mesh <- sdmTMB::make_mesh(sdmTMB::pcod, c("X", "Y"), cutoff = 20)
#' fit <- sdmTMB::sdmTMB(
#'   data = sdmTMB::pcod, formula = density ~ 0 + as.factor(year),
#'   time = "year", mesh = mesh, family = sdmTMB::tweedie(link = "log")
#' )
#' cv <- sdmTMB_mesh_cv(fit, mesh_cutoffs = c(15, 30), k = 3)
#' plot(cv)
#' plot(cv, metric = "deltaAIC")
#' }
#' @method plot sdmTMB_mesh_cv
#' @export
plot.sdmTMB_mesh_cv <- function(x, metric = "deltaNLL", base_size = 11, ...) {
  metric <- match.arg(metric, c("deltaNLL", "sum_loglik", "deltaAIC"))
  ggplot2::ggplot(
    x, ggplot2::aes(x = factor(.data$cutoff), y = .data[[metric]])
  ) +
    ggplot2::geom_col() +
    ggplot2::labs(x = "Mesh cutoff", y = metric) +
    ggplot2::theme_classic(base_size = base_size)
}
