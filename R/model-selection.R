#' Complete-case frame for a set of model-selection candidates
#'
#' @description
#' Drops every row that is missing a variable used by *any* candidate, so that
#' all candidates are fitted to identical records.
#'
#' @details
#' This is the precondition that makes a selection table mean anything.
#' Information criteria and cross-validated log-likelihoods are only comparable
#' between models fitted to the same response data; if one candidate carries
#' `s(depth)` and another does not, and `depth` has gaps, `sdmTMB()` silently
#' drops different rows for each and the resulting AIC column compares two
#' different quantities.
#'
#' Build the selection frame once, select on it, then fit the *chosen*
#' specification to the full data: there is no reason to keep discarding records
#' because a covariate that did not enter the model is missing for them.
#'
#' @param data A data frame.
#' @param candidates A named list of candidates, as accepted by
#'   [sdmTMB_selection()]: each element a formula, or a list that may contain a
#'   `formula` element.
#' @param formula Optional default formula for candidates that do not carry one.
#' @param extra Character vector of further columns that must also be complete
#'   (e.g. the coordinate columns, the time column, or an offset column).
#'
#' @return `data` with incomplete rows removed. The number of dropped rows and
#'   the columns that were checked are attached as the `"dropped"` and
#'   `"columns"` attributes.
#'
#' @author Mikko Vihtakari
#' @seealso [sdmTMB_selection()]
#'
#' @examples
#' cands <- list(
#'   "Full" = density ~ 0 + as.factor(year) + depth_scaled,
#'   "No depth" = density ~ 0 + as.factor(year)
#' )
#' d <- selection_frame(sdmTMB::pcod, cands, extra = c("X", "Y"))
#' attr(d, "dropped")
#' @export
selection_frame <- function(data, candidates, formula = NULL, extra = NULL) {
  if (!is.data.frame(data)) stop("`data` must be a data frame.")
  candidates <- .as_candidate_list(candidates)

  vars <- unlist(lapply(candidates, function(k) {
    f <- if (is.null(k$formula)) formula else k$formula
    if (is.null(f)) character(0) else all.vars(f)
  }))
  vars <- unique(c(vars, extra))
  vars <- vars[vars %in% names(data)]

  if (!length(vars)) {
    attr(data, "dropped") <- 0L
    attr(data, "columns") <- character(0)
    return(data)
  }

  keep <- stats::complete.cases(data[, vars, drop = FALSE])
  out <- data[keep, , drop = FALSE]
  out <- droplevels(out)
  attr(out, "dropped") <- sum(!keep)
  attr(out, "columns") <- vars
  out
}


#' Add delta-AIC and Akaike weights to a comparison table
#'
#' @description
#' Adds `deltaAIC` and `AICweight` columns to a data frame that carries an `AIC`
#' column, and sorts the result so the best-supported model comes first.
#'
#' @details
#' **Akaike weights are only meaningful among models fitted to the same response
#' data.** A table that mixes fits on different subsets — a Tweedie over all
#' hauls beside a Gamma over the positive ones, say, or a biomass model beside an
#' abundance model — has no common likelihood scale, and weights computed across
#' it would invite exactly the comparison the table should be warning against.
#' `group` exists for that case: weights are computed within each group, and left
#' `NA` for groups with a single member.
#'
#' @param x A data frame with an `AIC` column.
#' @param group Optional column name whose levels delimit comparable sets.
#' @param aic_col Name of the AIC column. Default `"AIC"`.
#'
#' @return `x` with `deltaAIC` and `AICweight` columns, sorted by AIC within
#'   group.
#'
#' @author Mikko Vihtakari
#' @seealso [sdmTMB_selection()]
#' @importFrom rlang .data
#'
#' @examples
#' tab <- data.frame(
#'   model = c("a", "b", "c"),
#'   AIC = c(1002, 1000, 1010)
#' )
#' add_aic_weights(tab)
#' @export
add_aic_weights <- function(x, group = NULL, aic_col = "AIC") {
  if (!aic_col %in% names(x)) {
    stop("`x` must contain an `", aic_col, "` column.")
  }

  x$.grp <- if (is.null(group)) "all" else as.character(x[[group]])

  out <- x |>
    dplyr::group_by(.data$.grp) |>
    dplyr::mutate(
      deltaAIC = .data[[aic_col]] - .min_or_na(.data[[aic_col]]),
      # A single-member group has nothing to be weighted against.
      AICweight = if (sum(!is.na(.data[[aic_col]])) < 2) {
        NA_real_
      } else {
        exp(-0.5 * .data$deltaAIC) /
          sum(exp(-0.5 * .data$deltaAIC), na.rm = TRUE)
      }
    ) |>
    dplyr::arrange(.data$.grp, .data[[aic_col]], .by_group = FALSE) |>
    dplyr::ungroup()

  out$.grp <- NULL
  out
}


#' Summarise an sdmTMB cross-validation on a per-observation scale
#'
#' @description
#' Turns an [sdmTMB::sdmTMB_cv()] object into a one-row summary whose
#' log-likelihood is expressed **per held-out observation**, together with the
#' fold-level diagnostics needed to tell a clean comparison from a fragile one.
#'
#' @details
#' A summed hold-out log-likelihood is not comparable between candidates that
#' held out different numbers of observations. That happens more easily than it
#' looks: candidates fitted to different complete-case subsets (see
#' [selection_frame()]) hold out different numbers of rows, and a candidate that
#' sums fewer terms scores *higher*, which inverts the ranking exactly where the
#' comparison is least reliable. Dividing by the number of contributing
#' observations removes the artefact; `n_heldout` is reported alongside so a row
#' assembled from a different number of points is visible as such.
#'
#' `folds_pdhess` counts the folds whose Hessian was positive definite. A fold
#' with a non-positive-definite Hessian still yields point predictions, so it
#' contributes to all three criteria while signalling that its optimum is not
#' trustworthy — the count has to be shown or the reader cannot see it.
#'
#' @param x An object of class `sdmTMB_cv` from [sdmTMB::sdmTMB_cv()], or a
#'   `try-error`/`NULL` from a crashed run.
#' @param label Optional character label carried into the `model` column.
#' @param response Name of the response column, used for `cv_RMSE`/`cv_MAE`. If
#'   `NULL` (default), taken from the left-hand side of the fitted formula.
#'
#' @return A one-row tibble with `model`, `folds`, `folds_pdhess`, `n_heldout`,
#'   `cv_loglik` (per held-out observation; higher is better), `cv_RMSE`,
#'   `cv_MAE` and `cv_crashed`.
#'
#' @author Mikko Vihtakari
#' @seealso [sdmTMB::sdmTMB_cv()], [sdmTMB_selection()]
#'
#' @examples
#' \donttest{
#' mesh <- sdmTMB::make_mesh(sdmTMB::pcod, c("X", "Y"), cutoff = 25)
#' cv <- sdmTMB::sdmTMB_cv(
#'   density ~ 0 + as.factor(year), data = sdmTMB::pcod, mesh = mesh,
#'   family = sdmTMB::tweedie(), k_folds = 2
#' )
#' sdmTMB_cv_summary(cv, label = "Year only")
#' }
#' @export
sdmTMB_cv_summary <- function(x, label = NA_character_, response = NULL) {
  crashed <- tibble::tibble(
    model = label, folds = NA_integer_, folds_pdhess = NA_integer_,
    n_heldout = NA_integer_, cv_loglik = NA_real_, cv_RMSE = NA_real_,
    cv_MAE = NA_real_, cv_crashed = TRUE
  )
  if (is.null(x) || inherits(x, "try-error")) return(crashed)
  if (!inherits(x, "sdmTMB_cv")) {
    stop("`x` must be an sdmTMB_cv object, a try-error or NULL.")
  }

  dat <- x$data
  if (is.null(response)) {
    f <- x$models[[1]]$formula
    f <- if (is.list(f)) f[[1]] else f
    response <- all.vars(f)[1]
  }

  # Rows the CV actually scored. In k-fold every row is held out exactly once,
  # but leave-future-out scores only the forecast years, and a fold that failed
  # to produce a prediction leaves NAs behind.
  scored <- !is.na(dat$cv_loglik)
  n_heldout <- sum(scored)

  err <- if (response %in% names(dat) && "cv_predicted" %in% names(dat)) {
    dat[[response]][scored] - dat$cv_predicted[scored]
  } else {
    NA_real_
  }

  tibble::tibble(
    model = label,
    folds = length(x$fold_loglik),
    folds_pdhess = sum(x$pdHess, na.rm = TRUE),
    n_heldout = n_heldout,
    # Per held-out observation, NOT summed over folds. See Details.
    cv_loglik = if (n_heldout > 0) {
      sum(dat$cv_loglik[scored]) / n_heldout
    } else {
      NA_real_
    },
    cv_RMSE = sqrt(mean(err^2, na.rm = TRUE)),
    cv_MAE = mean(abs(err), na.rm = TRUE),
    cv_crashed = FALSE
  )
}


#' Compare a set of sdmTMB model-selection candidates
#'
#' @description
#' Fits a named list of candidate specifications to identical records and
#' returns a tidy selection table: the full specification of each candidate, its
#' convergence and sanity status, in-sample NLL/AIC with delta-AIC and Akaike
#' weights, and — when `cv` is on — cross-validated predictive skill expressed
#' per held-out observation. One function covers the usual selection stages
#' (component ranking, dropping fixed effects, family, spatiotemporal structure,
#' mesh resolution), because each is the same operation with a different thing
#' varied.
#'
#' @details
#' ## Identical records
#' With `complete_cases = TRUE` (the default) the data are passed through
#' [selection_frame()] first, so every candidate sees the same rows and the
#' likelihood-based columns are comparable. Fit the *selected* specification to
#' the full data afterwards.
#'
#' ## What the table is sorted by, and why you should not rely on it
#' Rows are ordered by `cv_deltaNLL` when cross-validation ran and by
#' `deltaAIC` otherwise. Never read the winner off the first row in downstream
#' code — use [best_candidate()], which looks the value up in the column and
#' skips rows that are not comparable.
#'
#' ## Comparability
#' The `comparable` column is `TRUE` only for a candidate that fitted, whose
#' Hessian was positive definite, that saw the modal number of records, and —
#' under CV — had every fold resolve and score the modal number of held-out
#' points. **Compare only those rows**, and do not quote a delta between two
#' candidates unless both are comparable: a likelihood from a fit that has not
#' resolved is not a basis for a comparison, and neither is one computed over a
#' different set of observations.
#'
#' [sdmTMB::sanity()] is reported in its own column but does not gate
#' comparability. It is a broader battery of warnings — a range longer than the
#' survey domain, a random-field SD collapsing to zero, a large gradient — that
#' flags a model worth thinking about rather than one whose likelihood is
#' meaningless; gating on it would quietly drop the best-fitting candidate from
#' the comparison. Read it, and treat a `sanity = FALSE` winner as a reason to
#' simplify rather than as a row to ignore.
#'
#' ## Cost
#' A cross-validated candidate costs `k` fits (plus one more when
#' `fit_full = TRUE`, which is needed for AIC, sanity and per-candidate indices).
#' Cross-validating a long ladder is therefore usually the wrong order of work:
#' rank all candidates by AIC first (`cv = FALSE`), then cross-validate a
#' shortlist taken from that ranking with [best_candidate()]. With `cache_dir`
#' set and the same `cache_prefix`, the second call reuses the whole-frame fits
#' from the first and pays only for the folds.
#'
#' ## Caching and resumability
#' `cache_dir` writes **two files per candidate** — the whole-frame fit and the
#' cross-validation separately — so an interrupted run resumes instead of
#' starting over, and a cross-validated call under the same `cache_prefix`
#' reuses the fits an earlier AIC ladder already paid for instead of repeating
#' them. `only` restricts a call to named candidates so a long ladder can be
#' spread over several R sessions (a large spatiotemporal fit can exhaust memory
#' when a dozen of them accumulate in one process).
#'
#' @param candidates A named list of candidates. Each element is either a
#'   formula, or a list with any of `formula`, `family`, `spatial`,
#'   `spatiotemporal`, `mesh`, `cutoff` and `time`; anything not set falls back
#'   to the corresponding argument below. Names become the `model` column. A
#'   candidate that sets its own `cutoff` overrides a shared `mesh`, so a
#'   mesh-resolution stage is just another candidate list.
#' @param data A data frame with the response, predictors and coordinates.
#' @param formula Default formula for candidates that do not carry one.
#' @param mesh A [sdmTMB::make_mesh()] mesh shared by all candidates. If `NULL`,
#'   a mesh is built per candidate from `cutoff` and `xy_cols`.
#' @param cutoff Default mesh cutoff (km) used when `mesh` is `NULL`.
#' @param xy_cols Coordinate columns used to build meshes. Default
#'   `c("X", "Y")`.
#' @param family Default [sdmTMB::sdmTMB()] family. No default: supply it here or
#'   per candidate, so the choice is deliberate.
#' @param spatial,spatiotemporal,time Defaults passed to [sdmTMB::sdmTMB()].
#' @param control An [sdmTMB::sdmTMBcontrol()] object.
#' @param ... Further arguments passed to both [sdmTMB::sdmTMB()] and
#'   [sdmTMB::sdmTMB_cv()]. Pass an `offset` as the *name* of a column in `data`,
#'   not as a vector — a vector would misalign when `complete_cases = TRUE`
#'   removes rows.
#' @param cv Cross-validation: `FALSE` (default) for none, or `TRUE`/an integer
#'   number of folds.
#' @param fold_ids Optional fold assignment (a vector, or the name of a column in
#'   `data`) passed to [sdmTMB::sdmTMB_cv()]. Use it to hold out spatial blocks
#'   (e.g. from [blockCV::cv_spatial()]) instead of scattered points: random
#'   folds measure interpolation, spatially clustered folds measure
#'   extrapolation into unsampled ground, which is the harder and more relevant
#'   test for a model whose purpose is to integrate over space.
#' @param lfo,lfo_forecast,lfo_validations Leave-future-out cross-validation,
#'   passed to [sdmTMB::sdmTMB_cv()]. `lfo = TRUE` scores the model on years it
#'   has not seen, which is the question an assessment update actually asks.
#' @param fit_full Fit each candidate once on the whole frame, in addition to any
#'   CV? Default `TRUE`. Needed for `AIC`, [sdmTMB::sanity()] and the
#'   per-candidate indices in `plot(type = "index")`.
#' @param complete_cases Restrict the data to rows complete for every candidate?
#'   Default `TRUE`. See [selection_frame()].
#' @param cache_dir Directory for per-candidate `.rds` caches. `NULL` (default)
#'   disables caching.
#' @param cache_prefix Prefix for cache file names, so several selection stages
#'   can share one directory. Default `"selection"`.
#' @param refit Recompute cached candidates? Default `FALSE`.
#' @param only Optional character vector of candidate names to compute in this
#'   call. Candidates outside it are read from the cache if present and skipped
#'   otherwise.
#' @param n_workers,future_seed Parallel settings for the CV fits.
#' @param silent Suppress model fitting output? Default `TRUE`.
#' @param verbose Report progress? Default `TRUE`.
#'
#' @return An object of class `sdmTMB_selection`: a list with `table` (the tidy
#'   selection table), `fits` (named list of fitted models or `NULL`s), `cv`
#'   (named list of [sdmTMB::sdmTMB_cv()] objects, or `NULL`) and `candidates`
#'   (the resolved specifications). Print it, plot it with
#'   [plot.sdmTMB_selection()], and query it with [best_candidate()].
#'
#' @author Mikko Vihtakari
#' @seealso [selection_frame()], [best_candidate()],
#'   [plot.sdmTMB_selection()], [sdmTMB_cv_summary()], [compare_models()]
#'
#' @importFrom rlang .data
#'
#' @examples
#' \donttest{
#' cands <- list(
#'   "Year only" = density ~ 0 + as.factor(year),
#'   "+ depth" = density ~ 0 + as.factor(year) + depth_scaled,
#'   "No spatiotemporal" = list(spatiotemporal = "off")
#' )
#' sel <- sdmTMB_selection(
#'   cands, data = sdmTMB::pcod,
#'   formula = density ~ 0 + as.factor(year) + depth_scaled,
#'   cutoff = 25, family = sdmTMB::tweedie(), time = "year",
#'   spatial = "on", spatiotemporal = "iid"
#' )
#' sel
#' plot(sel)
#' best_candidate(sel)
#' }
#' @export
sdmTMB_selection <- function(
  candidates,
  data,
  formula = NULL,
  mesh = NULL,
  cutoff = NULL,
  xy_cols = c("X", "Y"),
  family = NULL,
  spatial = "on",
  spatiotemporal = "iid",
  time = NULL,
  control = sdmTMB::sdmTMBcontrol(newton_loops = 1),
  ...,
  cv = FALSE,
  fold_ids = NULL,
  lfo = FALSE,
  lfo_forecast = 1,
  lfo_validations = 5,
  fit_full = TRUE,
  complete_cases = TRUE,
  cache_dir = NULL,
  cache_prefix = "selection",
  refit = FALSE,
  only = NULL,
  n_workers = 1,
  future_seed = TRUE,
  silent = TRUE,
  verbose = TRUE
) {
  candidates <- .as_candidate_list(candidates)
  if (!length(candidates)) stop("`candidates` is empty.")
  if (is.null(names(candidates)) || any(!nzchar(names(candidates)))) {
    stop("`candidates` must be fully named; the names become the model labels.")
  }
  if (is.null(mesh) && is.null(cutoff) &&
        !all(vapply(candidates, function(k) {
          !is.null(k$mesh) || !is.null(k$cutoff)
        }, logical(1)))) {
    stop("Supply `mesh`, `cutoff`, or a `mesh`/`cutoff` for every candidate.")
  }

  if (!fit_full && !isTRUE(cv) && !is.numeric(cv) && !isTRUE(lfo)) {
    stop("`fit_full = FALSE` with no cross-validation computes nothing. Set ",
         "`fit_full = TRUE`, or ask for `cv`/`lfo`.")
  }

  dots <- list(...)
  if (!is.null(dots$offset) && !is.character(dots$offset) && complete_cases) {
    stop(
      "Pass `offset` as the name of a column in `data`. A numeric offset ",
      "vector misaligns when `complete_cases = TRUE` drops rows."
    )
  }

  n_before <- nrow(data)
  if (complete_cases) {
    data <- selection_frame(
      data, candidates, formula = formula,
      extra = c(xy_cols, time, if (is.character(dots$offset)) dots$offset)
    )
    if (verbose && attr(data, "dropped") > 0) {
      message(
        "selection_frame(): dropped ", attr(data, "dropped"), " of ", n_before,
        " rows incomplete for at least one candidate, so all candidates are ",
        "fitted to identical records."
      )
    }
  }

  # Resolve each candidate against the shared defaults, once, up front, so the
  # specification string in the table is what was actually fitted.
  specs <- lapply(names(candidates), function(nm) {
    .resolve_candidate(
      candidates[[nm]], name = nm, formula = formula, family = family,
      spatial = spatial, spatiotemporal = spatiotemporal, time = time,
      mesh = mesh, cutoff = cutoff
    )
  })
  names(specs) <- names(candidates)

  k_folds <- if (isTRUE(cv)) 8L else if (is.numeric(cv)) as.integer(cv) else 0L
  do_cv <- k_folds > 0L || isTRUE(lfo)
  if (isTRUE(lfo) && k_folds == 0L) k_folds <- lfo_validations

  if (!is.null(cache_dir) && !dir.exists(cache_dir)) {
    dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  }

  results <- lapply(names(specs), function(nm) {
    spec <- specs[[nm]]
    # Two cache entries per candidate, not one: the whole-frame fit and the
    # cross-validation are separate pieces of work, and separating them lets a
    # CV stage reuse the fits an AIC ladder already paid for, provided both are
    # run under the same `cache_prefix`. One combined file would either refit
    # everything or, worse, satisfy a CV request from a fit-only cache entry.
    slug <- .selection_slug(nm)
    fit_file <- if (is.null(cache_dir)) NULL else {
      file.path(cache_dir, paste0(cache_prefix, "-", slug, ".rds"))
    }
    cv_file <- if (is.null(cache_dir)) NULL else {
      file.path(cache_dir, paste0(cache_prefix, "-", slug, "-cv.rds"))
    }
    read_cache <- function(f) {
      if (!refit && !is.null(f) && file.exists(f)) readRDS(f) else NULL
    }

    fit_cached <- read_cache(fit_file)
    cv_cached <- if (do_cv) read_cache(cv_file) else NULL
    need_fit <- fit_full && is.null(fit_cached)
    need_cv <- do_cv && is.null(cv_cached)

    if (!need_fit && !need_cv) {
      if (verbose) message("Candidate '", nm, "': cached.")
      return(list(
        fit = fit_cached$fit, cv = cv_cached$cv,
        error = fit_cached$error %||% cv_cached$error %||% NA_character_,
        minutes = fit_cached$minutes %||% NA_real_, skipped = FALSE
      ))
    }
    if (!is.null(only) && !nm %in% only) {
      if (verbose) message("Candidate '", nm, "': skipped (not in `only`).")
      return(list(fit = fit_cached$fit, cv = cv_cached$cv,
                  error = NA_character_, minutes = NA_real_, skipped = TRUE))
    }

    if (verbose) {
      message("Candidate '", nm, "': ",
              paste(c(if (need_fit) "fitting", if (need_cv) "cross-validating"),
                    collapse = " + "), ".")
    }
    cand_mesh <- spec$mesh %||%
      sdmTMB::make_mesh(data, xy_cols = xy_cols, cutoff = spec$cutoff)
    fit_args <- list(
      formula = spec$formula, data = data, mesh = cand_mesh,
      time = spec$time, family = spec$family, spatial = spec$spatial,
      spatiotemporal = spec$spatiotemporal, control = control
    )

    t0 <- Sys.time()
    fit <- if (need_fit) {
      try(do.call(sdmTMB::sdmTMB, c(fit_args, list(silent = silent), dots)),
          silent = TRUE)
    } else {
      fit_cached$fit
    }
    if (need_fit && !is.null(fit_file)) {
      saveRDS(list(
        fit = if (inherits(fit, "try-error")) NULL else fit,
        error = if (inherits(fit, "try-error")) {
          conditionMessage(attr(fit, "condition"))
        } else {
          NA_character_
        },
        minutes = as.numeric(difftime(Sys.time(), t0, units = "mins"))
      ), fit_file)
    }

    t1 <- Sys.time()
    cvout <- if (need_cv) {
      old_plan <- .setup_parallel(n_workers)
      on.exit(future::plan(old_plan), add = TRUE)
      try(do.call(sdmTMB::sdmTMB_cv, c(fit_args, list(
        k_folds = k_folds, fold_ids = fold_ids, lfo = lfo,
        lfo_forecast = lfo_forecast, lfo_validations = lfo_validations,
        parallel = n_workers > 1
      ), dots)), silent = TRUE)
    } else {
      cv_cached$cv
    }
    if (need_cv && !is.null(cv_file)) {
      saveRDS(list(
        cv = if (inherits(cvout, "try-error")) NULL else cvout,
        error = if (inherits(cvout, "try-error")) {
          conditionMessage(attr(cvout, "condition"))
        } else {
          NA_character_
        },
        minutes = as.numeric(difftime(Sys.time(), t1, units = "mins"))
      ), cv_file)
    }

    list(
      fit = if (inherits(fit, "try-error")) NULL else fit,
      cv = if (inherits(cvout, "try-error")) NULL else cvout,
      error = if (inherits(fit, "try-error")) {
        conditionMessage(attr(fit, "condition"))
      } else if (inherits(cvout, "try-error")) {
        conditionMessage(attr(cvout, "condition"))
      } else {
        NA_character_
      },
      minutes = as.numeric(difftime(Sys.time(), t0, units = "mins")),
      skipped = FALSE
    )
  })
  names(results) <- names(specs)

  tab <- .selection_table(results, specs, do_cv = do_cv, fit_full = fit_full)

  out <- list(
    table = tab,
    fits = lapply(results, function(k) k$fit),
    cv = if (do_cv) lapply(results, function(k) k$cv) else NULL,
    candidates = specs
  )
  class(out) <- "sdmTMB_selection"
  # Deliberately no copy of `data` here: each fit already carries its own, and attaching the
  # whole selection frame again would double the size of every saved selection object.
  attr(out, "cv") <- do_cv
  attr(out, "n_data") <- nrow(data)
  out
}


#' The best candidate in a selection table
#'
#' @description
#' Looks the best-supported candidate up **in the metric column**, not by row
#' position, and by default considers only rows the table marks as comparable.
#'
#' @details
#' Reading the winner off the first row couples downstream code to how the table
#' happens to be sorted; a later change of sort key then silently changes which
#' model the document claims to have selected. Use this instead — including to
#' build a cross-validation shortlist from an AIC ladder, via `n`.
#'
#' @param x An `sdmTMB_selection` object, or its `table`.
#' @param n Number of candidates to return. Default `1`.
#' @param by Metric to rank by: `"cv"` (per-observation hold-out
#'   log-likelihood), `"aic"`, or `NULL` (default) to use CV when it is present
#'   and AIC otherwise.
#' @param comparable_only Consider only rows with `comparable == TRUE`? Default
#'   `TRUE`.
#'
#' @return A character vector of candidate names, best first.
#'
#' @author Mikko Vihtakari
#' @seealso [sdmTMB_selection()]
#'
#' @examples
#' tab <- data.frame(
#'   model = c("a", "b", "c"), AIC = c(1002, 1000, 1010),
#'   comparable = c(TRUE, TRUE, FALSE)
#' )
#' best_candidate(tab, n = 2, by = "aic")
#' @export
best_candidate <- function(x, n = 1, by = NULL, comparable_only = TRUE) {
  tab <- if (inherits(x, "sdmTMB_selection")) x$table else x
  if (!"model" %in% names(tab)) stop("`x` must carry a `model` column.")

  if (is.null(by)) by <- if ("cv_loglik" %in% names(tab)) "cv" else "aic"
  by <- match.arg(by, c("cv", "aic"))

  if (comparable_only && "comparable" %in% names(tab)) {
    tab <- tab[.is_true(tab$comparable), , drop = FALSE]
  }
  if (!nrow(tab)) {
    warning("No comparable candidates; returning NA.")
    return(NA_character_)
  }

  if (by == "cv") {
    if (!"cv_loglik" %in% names(tab)) {
      stop("No `cv_loglik` column; run sdmTMB_selection() with `cv`.")
    }
    ord <- order(-tab$cv_loglik, na.last = NA)
  } else {
    if (!"AIC" %in% names(tab)) {
      stop("No `AIC` column; run sdmTMB_selection() with `fit_full = TRUE`.")
    }
    ord <- order(tab$AIC, na.last = NA)
  }
  ranked <- tab$model[ord]
  ranked[seq_len(min(n, length(ranked)))]
}


#' @export
print.sdmTMB_selection <- function(x, ...) {
  cv <- isTRUE(attr(x, "cv"))
  cols <- c(
    "model", "n", "crashed", "converged", "sanity", "AIC", "deltaAIC",
    "AICweight",
    if (cv) c("folds_pdhess", "n_heldout", "cv_loglik", "cv_deltaNLL"),
    "comparable"
  )
  cols <- cols[cols %in% names(x$table)]

  cat("<sdmTMB_selection>", nrow(x$table), "candidates,",
      if (cv) "cross-validated" else "AIC only", "\n\n")
  print(as.data.frame(x$table[, cols, drop = FALSE]), row.names = FALSE)

  n_ok <- sum(.is_true(x$table$comparable))
  cat("\n", n_ok, " of ", nrow(x$table), " rows are comparable.\n", sep = "")
  if (n_ok > 0) {
    best <- tryCatch(best_candidate(x), error = function(e) NA_character_)
    if (!is.na(best)) {
      cat("Best (", if (cv) "cv_loglik" else "AIC", "): ", best, "\n", sep = "")
    }
  }
  if (n_ok < nrow(x$table)) {
    cat("Compare only comparable rows: a delta computed against a crashed, ",
        "non-converged\nor differently-sized fit is not evidence.\n", sep = "")
  }
  n_insane <- sum(.is_true(x$table$comparable) & !.is_true(x$table$sanity))
  if (n_insane > 0) {
    cat(n_insane, " comparable row(s) fail sanity(): they are still compared, ",
        "but check\nthem before trusting the winner.\n", sep = "")
  }
  invisible(x)
}


#' Plot an sdmTMB selection table
#'
#' @description
#' `type = "selection"` draws the ranking as a status-coded dot plot: one point
#' per candidate, positioned by how far it is from the best, coloured and shaped
#' by whether it crashed, failed to converge or failed [sdmTMB::sanity()].
#' `type = "index"` computes and overlays the survey index each candidate
#' produces, which answers the question a selection table cannot: *does this
#' choice actually move the index?*
#'
#' @param x An object of class `sdmTMB_selection`.
#' @param type Character. `"selection"` (default) or `"index"`.
#' @param metric Metric for `type = "selection"`: `"cv_deltaNLL"`, `"deltaAIC"`
#'   or `"deltaNLL"`. `NULL` (default) picks the cross-validated metric when it
#'   is available and `deltaAIC` otherwise.
#' @param newdata Prediction grid, required for `type = "index"`.
#' @param index_divisor Optional numeric divisor applied to index values.
#' @param unit Character. Unit label for the index axis.
#' @param bias_correct,level,area,nsplit,silent Passed to
#'   [sdmTMB::get_index_split()] for `type = "index"`.
#' @param base_size Numeric. Base font size. Default `11`.
#' @param ... Currently ignored.
#'
#' @return A `ggplot` object.
#'
#' @author Mikko Vihtakari
#' @seealso [sdmTMB_selection()]
#' @import ggplot2
#' @importFrom rlang .data
#'
#' @examples
#' \donttest{
#' cands <- list(
#'   "Year only" = density ~ 0 + as.factor(year),
#'   "+ depth" = density ~ 0 + as.factor(year) + depth_scaled
#' )
#' sel <- sdmTMB_selection(
#'   cands, data = sdmTMB::pcod, cutoff = 25, family = sdmTMB::tweedie(),
#'   time = "year", spatial = "on", spatiotemporal = "iid"
#' )
#' plot(sel)
#' nd <- sdmTMB::replicate_df(sdmTMB::qcs_grid, "year", unique(sdmTMB::pcod$year))
#' plot(sel, type = "index", newdata = nd)
#' }
#' @method plot sdmTMB_selection
#' @export
plot.sdmTMB_selection <- function(
  x,
  type = "selection",
  metric = NULL,
  newdata = NULL,
  index_divisor = NULL,
  unit = NA,
  bias_correct = FALSE,
  level = 0.95,
  area = 1,
  nsplit = 3,
  silent = TRUE,
  base_size = 11,
  ...
) {
  type <- match.arg(type, c("selection", "index"))

  if (type == "selection") {
    if (is.null(metric)) {
      metric <- if ("cv_deltaNLL" %in% names(x$table)) "cv_deltaNLL" else "deltaAIC"
    }
    if (!metric %in% names(x$table)) {
      stop("Metric '", metric, "' is not a column of the selection table.")
    }

    dat <- x$table
    dat$status <- .selection_status(dat)
    # Best at the top: the metrics are all "lower is better, 0 = best".
    dat$model <- factor(dat$model, levels = rev(dat$model[order(dat[[metric]])]))

    status_levels <- c("All OK", "Sanity test issues", "Nonconvergent",
                       "Crashed")
    dat$status <- factor(dat$status, levels = status_levels)
    dat$status <- droplevels(dat$status)
    cols <- c("All OK" = "black", "Sanity test issues" = "grey50",
              "Nonconvergent" = "grey50", "Crashed" = "grey70")
    shapes <- c("All OK" = 16, "Sanity test issues" = 15,
                "Nonconvergent" = 17, "Crashed" = 4)

    lab <- switch(
      metric,
      cv_deltaNLL = "Hold-out negative log-likelihood difference\n(per observation; 0 = best)",
      deltaAIC = "AIC difference (0 = best)",
      deltaNLL = "In-sample negative log-likelihood difference (0 = best)",
      metric
    )

    return(
      ggplot2::ggplot(
        dat,
        ggplot2::aes(
          x = .data$model, y = .data[[metric]],
          shape = .data$status, colour = .data$status
        )
      ) +
        ggplot2::geom_point(size = 3) +
        ggplot2::coord_flip() +
        ggplot2::scale_colour_manual(values = cols[levels(dat$status)]) +
        ggplot2::scale_shape_manual(values = shapes[levels(dat$status)]) +
        ggplot2::labs(
          x = "Candidate", y = lab, colour = "Model diagnostics",
          shape = "Model diagnostics"
        ) +
        ggplot2::theme_classic(base_size = base_size) +
        ggplot2::theme(legend.position = "bottom")
    )
  }

  # type == "index" --------------------------------------------------------
  if (is.null(newdata)) {
    stop("`newdata` (a prediction grid) is required for type = \"index\".")
  }
  fits <- x$fits[!vapply(x$fits, is.null, logical(1))]
  if (!length(fits)) {
    stop("No fitted models to predict from; run with `fit_full = TRUE`.")
  }

  dat <- dplyr::bind_rows(lapply(names(fits), function(nm) {
    idx <- .safe_index(
      mod = fits[[nm]], newdata = newdata, time_col = fits[[nm]]$time,
      nsplit = nsplit, bias_correct = bias_correct, level = level,
      area = area, silent = silent, label = nm
    )
    tibble::add_column(idx, model = nm, .before = 1)
  }))

  if (!is.null(index_divisor)) {
    dat <- dplyr::mutate(
      dat, est = .data$est / index_divisor,
      lwr = .data$lwr / index_divisor, upr = .data$upr / index_divisor
    )
  }

  ggplot2::ggplot(
    dat,
    ggplot2::aes(
      x = .data$year, y = .data$est, ymin = .data$lwr, ymax = .data$upr,
      colour = .data$model, fill = .data$model
    )
  ) +
    ggplot2::geom_ribbon(colour = NA, alpha = 0.15) +
    ggplot2::geom_path() +
    ggplot2::scale_colour_manual(
      values = .safe_brewer(length(unique(dat$model)))
    ) +
    ggplot2::scale_fill_manual(
      values = .safe_brewer(length(unique(dat$model)))
    ) +
    ggplot2::labs(
      x = "Year",
      y = if (!is.na(unit)) paste0("Index value (", unit, ")") else "Index value",
      colour = "Candidate", fill = "Candidate"
    ) +
    ggplot2::expand_limits(y = 0) +
    ggplot2::scale_y_continuous(n.breaks = 6) +
    ggplot2::theme_classic(base_size = base_size) +
    .index_axis_layers() +
    ggplot2::theme(legend.position = "bottom")
}


## Internals -------------------------------------------------------------------

#' Coerce the candidate argument into a list of candidate specifications
#'
#' A bare formula is shorthand for `list(formula = <formula>)`.
#'
#' @keywords internal
#' @noRd
.as_candidate_list <- function(candidates) {
  if (inherits(candidates, "formula")) candidates <- list(candidates)
  lapply(candidates, function(k) {
    if (inherits(k, "formula")) list(formula = k) else k
  })
}

#' Merge one candidate against the shared defaults
#'
#' @keywords internal
#' @noRd
.resolve_candidate <- function(
  candidate, name, formula, family, spatial, spatiotemporal, time, mesh, cutoff
) {
  out <- list(
    name = name,
    formula = candidate$formula %||% formula,
    family = candidate$family %||% family,
    spatial = candidate$spatial %||% spatial,
    spatiotemporal = candidate$spatiotemporal %||% spatiotemporal,
    time = candidate$time %||% time,
    # A candidate that names its own `cutoff` overrides a shared `mesh`: that is
    # what makes the mesh-resolution stage expressible in the same machinery.
    # Without this precedence a shared mesh would silently win and every row of
    # a mesh comparison would be the same fit.
    mesh = if (!is.null(candidate$cutoff)) candidate$mesh else {
      candidate$mesh %||% mesh
    },
    cutoff = candidate$cutoff %||% cutoff
  )
  if (is.null(out$formula)) {
    stop("Candidate '", name, "' has no formula, and no default `formula` ",
         "was supplied.")
  }
  if (is.null(out$family)) {
    stop("Candidate '", name, "' has no family. Supply `family` (shared) or ",
         "set it per candidate - the choice should be deliberate.")
  }
  # The full specification, carried with the candidate so a table row states
  # what was fitted instead of relying on its label.
  out$spec <- paste0(
    paste(trimws(format(out$formula)), collapse = " "),
    " | family = ", .family_label(out$family),
    " | spatial = ", out$spatial,
    " | spatiotemporal = ", out$spatiotemporal
  )
  out
}

#' One readable label for an sdmTMB family
#'
#' A delta family stores one `family` entry per component (e.g.
#' `c("binomial", "Gamma")`), so `family$family` used as a table cell recycles
#' the row, and its first element alone mislabels the fit as "binomial". Use
#' sdmTMB's `clean_name` (which also carries the links and the Poisson-link
#' type) when present, otherwise join the components with "/".
#'
#' @keywords internal
#' @noRd
.family_label <- function(family) {
  if (is.character(family$clean_name) && length(family$clean_name) == 1L) {
    return(family$clean_name)
  }
  paste(family$family, collapse = "/")
}

#' File-name-safe slug for a candidate name
#'
#' Normalising a name to letters and digits collides more often than it looks
#' ("+ depth" and "depth" both become "depth"), and a collision silently serves
#' one candidate's cached fit as another's. A short hash of the exact name is
#' appended to make the file unique; it is derived from the name alone, so
#' reordering the candidate list still reuses the cache.
#'
#' @keywords internal
#' @noRd
.selection_slug <- function(x) {
  x <- as.character(x)
  slug <- gsub("(^-|-$)", "", gsub("[^a-z0-9]+", "-", tolower(x)))
  if (!nzchar(slug)) slug <- "candidate"
  paste0(slug, "-", substr(rlang::hash(x), 1, 6))
}

#' Vectorised isTRUE(), NA-safe
#'
#' @keywords internal
#' @noRd
.is_true <- function(x) !is.na(x) & x

#' Diagnostic status label for the selection dot plot
#'
#' @keywords internal
#' @noRd
.selection_status <- function(tab) {
  ifelse(
    .is_true(tab$crashed), "Crashed",
    ifelse(
      !.is_true(tab$converged), "Nonconvergent",
      ifelse(!.is_true(tab$sanity), "Sanity test issues", "All OK")
    )
  )
}

#' Build the tidy selection table from the per-candidate results
#'
#' @keywords internal
#' @noRd
.selection_table <- function(results, specs, do_cv, fit_full = TRUE) {
  tab <- dplyr::bind_rows(lapply(names(results), function(nm) {
    res <- results[[nm]]
    # With fit_full = FALSE there is no whole-frame fit, so the status columns
    # are read off the cross-validation instead: `converged` becomes "every
    # fold's Hessian was positive definite", and `AIC` the median across the
    # fold models (they are fitted to k-1 folds each, so it is an approximation
    # -- the column is still comparable between candidates because every one of
    # them is approximated the same way).
    from_cv <- !fit_full && inherits(res$cv, "sdmTMB_cv")
    cv_models <- if (from_cv) res$cv$models else NULL
    # NB `cand`, not `spec`: tibble() evaluates its arguments sequentially and
    # lets later ones refer to columns created earlier, so a local named `spec`
    # would be shadowed by the `spec` column from the line below onwards.
    cand <- specs[[nm]]
    fit <- res$fit
    ok <- if (from_cv) length(cv_models) > 0 else {
      !is.null(fit) && inherits(fit, "sdmTMB")
    }
    ref <- if (from_cv) cv_models[[1]] else fit

    base <- tibble::tibble(
      model = nm,
      spec = cand$spec,
      formula = paste(trimws(format(cand$formula)), collapse = " "),
      family = .family_label(cand$family),
      spatial = paste(unlist(cand$spatial), collapse = "/"),
      spatiotemporal = paste(unlist(cand$spatiotemporal), collapse = "/"),
      knots = if (ok) ref$spde$mesh$n else NA_integer_,
      n = if (ok) nrow(ref$data) else NA_integer_,
      crashed = !ok,
      converged = if (!ok) {
        FALSE
      } else if (from_cv) {
        isTRUE(res$cv$converged)
      } else {
        isTRUE(fit$sd_report$pdHess)
      },
      # suppressMessages(): sanity(silent = TRUE) still emits cli notes
      # explaining its parameter names, which would repeat for every candidate.
      sanity = if (!ok) FALSE else .all_sane(if (from_cv) cv_models else list(fit)),
      NLL = if (!ok || from_cv) NA_real_ else fit$model$objective,
      AIC = if (!ok) {
        NA_real_
      } else if (from_cv) {
        stats::median(vapply(
          cv_models,
          function(m) tryCatch(stats::AIC(m), error = function(e) NA_real_),
          numeric(1)
        ), na.rm = TRUE)
      } else {
        tryCatch(stats::AIC(fit), error = function(e) NA_real_)
      },
      minutes = res$minutes %||% NA_real_,
      error = res$error %||% NA_character_
    )

    if (!do_cv) return(base)

    cvs <- sdmTMB_cv_summary(res$cv, label = nm)
    dplyr::bind_cols(base, cvs[, setdiff(names(cvs), "model"), drop = FALSE])
  }))

  tab <- tab |>
    dplyr::mutate(
      deltaNLL = .data$NLL - .min_or_na(.data$NLL),
      deltaNLL_pr = 100 * (.data$NLL / .min_or_na(.data$NLL) - 1)
    ) |>
    add_aic_weights() |>
    dplyr::mutate(
      deltaAIC_pr = 100 * (.data$AIC / .min_or_na(.data$AIC) - 1)
    )

  # Comparability: a row may only be compared with the others if it fitted, its
  # Hessian resolved, and it saw the same number of records as the rest. A
  # likelihood from a fit that did not resolve is not a basis for a comparison,
  # and neither is one computed over a different set of observations.
  #
  # `sanity` is deliberately NOT part of this. It is a broader battery of
  # warnings (a range longer than the survey domain, a random-field SD near
  # zero, a large gradient) that flags a model worth thinking about rather than
  # one whose likelihood is meaningless — gating on it would silently drop the
  # best-fitting candidate from every comparison. It is reported in its own
  # column and drives the status colouring in plot(type = "selection").
  modal_n <- .modal(tab$n)
  tab$comparable <- !tab$crashed & .is_true(tab$converged) &
    !is.na(tab$n) & tab$n == modal_n

  if (do_cv) {
    tab <- tab |>
      dplyr::mutate(
        cv_deltaNLL = -.min_or_na(-.data$cv_loglik) - .data$cv_loglik,
        cv_deltaNLL_pr = 100 *
          (-.data$cv_loglik / .min_or_na(-.data$cv_loglik) - 1)
      )
    modal_heldout <- .modal(tab$n_heldout)
    tab$comparable <- tab$comparable & !.is_true(tab$cv_crashed) &
      .is_true(tab$folds_pdhess == tab$folds) &
      !is.na(tab$n_heldout) & tab$n_heldout == modal_heldout
    tab <- dplyr::arrange(tab, .data$cv_deltaNLL)
  } else {
    tab <- dplyr::arrange(tab, .data$deltaAIC)
  }

  dplyr::relocate(tab, "comparable", .after = "sanity")
}

#' The most common non-missing value, returned in the input's own type
#'
#' @keywords internal
#' @noRd
.modal <- function(x) {
  x <- x[!is.na(x)]
  if (!length(x)) return(x[NA_integer_])
  ux <- unique(x)
  ux[which.max(tabulate(match(x, ux)))]
}

#' Did every model pass sdmTMB::sanity()?
#'
#' `sanity(silent = TRUE)` still emits cli notes explaining its parameter names,
#' which would repeat once per candidate (or once per fold), hence the
#' suppression.
#'
#' @keywords internal
#' @noRd
.all_sane <- function(models) {
  isTRUE(all(vapply(models, function(m) {
    isTRUE(all(unlist(suppressMessages(sdmTMB::sanity(m, silent = TRUE)))))
  }, logical(1))))
}

#' `min(x, na.rm = TRUE)` that returns `NA` instead of `Inf` for an all-NA input
#'
#' An all-NA column happens when every candidate crashed. Base R's `min()` then
#' warns and returns `Inf`, which propagates a plausible-looking `-Inf` delta
#' into the table instead of an obvious `NA`.
#'
#' @keywords internal
#' @noRd
.min_or_na <- function(x) {
  if (all(is.na(x))) return(NA_real_)
  min(x, na.rm = TRUE)
}

#' Null-coalescing operator
#'
#' @keywords internal
#' @noRd
`%||%` <- function(x, y) if (is.null(x)) y else x
