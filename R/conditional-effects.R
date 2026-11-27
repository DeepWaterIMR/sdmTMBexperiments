#' Conditional fixed effects of sdmTMB models on the response scale
#'
#' @description
#' Predicts the population-level response of one or more fitted sdmTMB models
#' along each fixed-effect term in turn, holding the other terms at reference
#' values, with confidence intervals. The terms of an sdmTMB formula are
#' additive on the link scale, so each term gets its own panel and the shape of
#' an effect does not depend on the references of the others, only its level
#' does. Use [plot()][plot.sdmTMB_conditional_effects] to draw the figure and
#' [effects_reference_text()] to write the references into a caption.
#'
#' Unlike [plot_fixed_effects()], which plots the coefficients on the link
#' scale, this function shows the predicted response, so smooths, factors and
#' linear terms are on one interpretable scale.
#'
#' @details
#' **Terms.** Variables are read from the right-hand side of the model formula
#' (both formulas of a delta model) and classified as:
#' * continuous: numeric variables used in smooths (`s(x)`), linear or
#'   transformed terms (`x`, `log(x)`, `poly(x, 2)`). The variable is varied
#'   over `n` values between its 0.5 % and 99.5 % quantiles (or its range when
#'   it takes `max_discrete` or fewer integer values, e.g. month);
#' * factor: factor or character variables, and numeric variables wrapped in
#'   `factor()` or `as.factor()` in the formula (e.g. `as.factor(year)`). Every
#'   level is predicted, in level order.
#'
#' Random-intercept terms (`(1 | g)`), offset terms and variables of
#' `spatial_varying` or `time_varying` formulas are not shown; they are held at
#' their references.
#'
#' **References.** Each term not being varied is held at its reference value:
#' * terms in `peak` (by default `depth` when it is in the model): the value
#'   where the term's own predicted effect peaks, e.g. the modal depth. The peak
#'   is found first by a cheap prediction without standard errors over the
#'   term's range, with the other terms at their references; peak terms are
#'   therefore shown first, because their references are used in the other
#'   panels;
#' * factors: the most common level in the data, except for a factor of the
#'   model's `time` variable, whose reference is the last level (the last year);
#' * numeric variables with `max_discrete` or fewer integer values (e.g. month):
#'   the most common value (the most sampled month);
#' * other numeric variables: the median.
#'
#' Any reference can be set through `ref`, a named list of values by variable
#' name, which also overrides the peak search.
#'
#' **Prediction.** One call to
#' `predict(fit, newdata, re_form = NA, re_form_iid = NA, se_fit = TRUE,
#' model = NA, offset = 0)` per model predicts every term without the spatial,
#' spatiotemporal and IID random effects and with a zero offset (i.e. per unit
#' of the offset, such as per unit swept area). For delta models, `model = NA`
#' combines the encounter probability and the positive-catch density on the
#' log scale, so the estimate and its confidence interval are `exp()` of the
#' log-scale prediction and its standard error. For other families the inverse
#' link is used. The confidence intervals are Wald intervals on the link scale
#' transformed to the response scale.
#'
#' **Speed.** `se_fit = TRUE` runs [TMB::sdreport()] on the prediction, which
#' takes about as long as the model's own sdreport: seconds for small models,
#' but several minutes (around 8 min for a delta model with spatiotemporal
#' fields and ~ 70 000 hauls) for large ones. The function therefore makes a
#' single `se_fit` call per model; save the result (e.g. with [saveRDS()]) in
#' reports that are re-rendered. `se_fit = FALSE` gives the estimates only, in
#' seconds.
#'
#' The time variable of a model with spatiotemporal fields is set to the
#' reference year; with `re_form = NA` it does not change the prediction
#' unless the model has `time_varying` terms. Effects of terms inside
#' interactions are shown with the interacting variables at their references.
#'
#' @param fit A fitted [sdmTMB::sdmTMB()] model, or a named list of fitted
#'   models (the names are used as model headings in the plot).
#' @param ref Named list of reference values by variable name, e.g.
#'   `list(year = 2025, geartype = "Shrimp", depth = 400)`. Variables not given
#'   get the defaults described in Details. Applies to every model in `fit`.
#' @param labels Named character vector of term labels by variable name, e.g.
#'   `c(depth = "Depth (m)", geartype = "Gear")`. Defaults to the variable name.
#' @param peak Character vector of continuous variables whose reference is the
#'   peak of their own effect. Default `"depth"` (ignored when the model has no
#'   such variable). Use `character(0)` to use medians instead.
#' @param n Integer. Number of values along each continuous variable. Default
#'   `80`.
#' @param level Numeric. Confidence level. Default `0.95`.
#' @param se_fit Logical. Compute confidence intervals? Default `TRUE`; `FALSE`
#'   is much faster on big models and returns `NA` limits.
#' @param max_discrete Integer. Numeric variables with at most this many
#'   distinct integer values (e.g. month) are treated as discrete for the
#'   default reference (most common value) and the prediction range (full
#'   range). Default `12`.
#'
#' @return A data frame of class `sdmTMB_conditional_effects` with columns
#'   `model`, `term` (variable name), `label`, `type` (`"continuous"` or
#'   `"factor"`), `x` (value as character), `xnum` (numeric position: the value
#'   for continuous terms, the level index for factors), `est`, `lwr`, `upr`
#'   (response scale), and an attribute `ref`: a data frame with the reference
#'   value of each shown term per model (`model`, `term`, `label`, `type`,
#'   `value`, `xnum`, `source`, where `source` is `"peak"`, `"mode"`, `"last"`,
#'   `"median"` or `"user"`).
#'
#' @section AI assistance:
#' Written with Claude Opus 5.5 (Anthropic); reviewed in full by Claude Opus
#' 5.5 (Anthropic), 2026-11-17.
#'
#' @author Mikko Vihtakari
#' @seealso [plot.sdmTMB_conditional_effects()], [effects_reference_text()],
#'   [plot_fixed_effects()], [sdmTMB::predict.sdmTMB()]
#' @examples
#' \donttest{
#' d <- subset(sebastes, year >= 2021 & cruiseseries %in% c("EcoS", "EggaN"))
#' d$geartype <- factor(d$geartype)
#' mesh <- sdmTMB::make_mesh(d, c("X", "Y"), cutoff = 80)
#' m <- sdmTMB::sdmTMB(
#'   density ~ s(depth, k = 5) + geartype + as.factor(year),
#'   data = d, mesh = mesh, time = "year", spatiotemporal = "off",
#'   family = sdmTMB::delta_gamma()
#' )
#' eff <- conditional_effects(m, labels = c(depth = "Depth (m)", geartype = "Gear"))
#' eff
#' plot(eff, y_lab = "Density (kg/nmi^2)")
#' effects_reference_text(eff)
#' }
#' @export
conditional_effects <- function(fit, ref = list(), labels = NULL,
                                peak = "depth", n = 80, level = 0.95,
                                se_fit = TRUE, max_discrete = 12) {
  fits <- if (inherits(fit, "sdmTMB")) list(Model = fit) else fit
  if (!is.list(fits) || !length(fits) ||
      !all(vapply(fits, inherits, logical(1), "sdmTMB"))) {
    stop("`fit` must be a fitted sdmTMB model or a list of them.")
  }
  if (is.null(names(fits)) || any(names(fits) == "")) {
    names(fits) <- paste("Model", seq_along(fits))
  }
  if (!is.list(ref)) stop("`ref` must be a named list.")
  stopifnot(n >= 2, level > 0, level < 1)

  res <- lapply(names(fits), function(nm) {
    .conditional_effects_one(
      fits[[nm]], model_name = nm, ref = ref, labels = labels, peak = peak,
      n = n, level = level, se_fit = se_fit, max_discrete = max_discrete
    )
  })
  out <- dplyr::bind_rows(lapply(res, `[[`, "effects"))
  out$model <- factor(out$model, levels = names(fits))
  refs <- dplyr::bind_rows(lapply(res, `[[`, "ref"))
  refs$model <- factor(refs$model, levels = names(fits))
  attr(out, "ref") <- refs
  attr(out, "level") <- level
  class(out) <- c("sdmTMB_conditional_effects", class(out))
  out
}

# Classify the fixed-effect variables of a fit: continuous or factor.
.effect_terms <- function(fit, max_discrete) {
  dat <- as.data.frame(fit$data)
  forms <- if (is.list(fit$formula)) fit$formula else list(fit$formula)
  vars <- character(0)
  as_factor <- character(0)
  for (f in forms) {
    rhs <- f[[length(f)]]
    tt <- stats::terms(stats::as.formula(call("~", rhs)), specials = "offset")
    labs <- attr(tt, "term.labels")
    # Drop random-intercept bars and offset terms
    labs <- labs[!grepl("\\|", labs)]
    off <- attr(tt, "offset")
    off_vars <- if (length(off)) {
      unlist(lapply(off, function(i) all.vars(attr(tt, "variables")[[i + 1]])))
    } else {
      character(0)
    }
    for (lab in labs) {
      v <- setdiff(all.vars(str2lang(lab)), off_vars)
      vars <- c(vars, v)
      fac <- regmatches(lab, regexec("^(?:as\\.)?factor\\(([^,()]+)\\)$", lab))[[1]]
      if (length(fac) == 2) as_factor <- c(as_factor, trimws(fac[2]))
    }
  }
  vars <- unique(vars[vars %in% names(dat)])
  type <- vapply(vars, function(v) {
    x <- dat[[v]]
    if (is.factor(x) || is.character(x) || is.logical(x) || v %in% as_factor) {
      "factor"
    } else {
      "continuous"
    }
  }, character(1))
  discrete <- vapply(vars, function(v) {
    x <- dat[[v]]
    is.numeric(x) && all(x == round(x), na.rm = TRUE) &&
      length(unique(stats::na.omit(x))) <= max_discrete
  }, logical(1))
  data.frame(term = vars, type = unname(type), discrete = unname(discrete),
             stringsAsFactors = FALSE)
}

.mode_value <- function(x) {
  tab <- table(x, useNA = "no")
  names(tab)[which.max(tab)]
}

# Coerce reference values to the class of a data column
.as_column_value <- function(value, column) {
  if (is.factor(column)) {
    bad <- setdiff(as.character(value), levels(column))
    if (length(bad)) {
      stop("Reference value '", bad[1], "' is not a level of the factor.")
    }
    factor(as.character(value), levels = levels(column))
  } else if (is.character(column)) {
    as.character(value)
  } else if (is.logical(column)) {
    as.logical(value)
  } else {
    value <- as.numeric(value)
    if (is.integer(column) && all(value == round(value))) as.integer(value) else value
  }
}

.conditional_effects_one <- function(fit, model_name, ref, labels, peak, n,
                                     level, se_fit, max_discrete) {
  dat <- as.data.frame(fit$data)
  terms <- .effect_terms(fit, max_discrete)
  if (!nrow(terms)) stop("No fixed-effect terms to show in model '", model_name, "'.")
  time_var <- fit$time
  if (!is.null(time_var) && identical(time_var, "_sdmTMB_time")) time_var <- NULL

  # Base row: every column of the data at a default reference value
  base <- dat[1, , drop = FALSE]
  source <- character(0)
  for (v in names(dat)) {
    x <- dat[[v]]
    if (is.numeric(x)) {
      discrete <- all(x == round(x), na.rm = TRUE) &&
        length(unique(stats::na.omit(x))) <= max_discrete
      val <- if (discrete) as.numeric(.mode_value(x)) else stats::median(x, na.rm = TRUE)
      source[v] <- if (discrete) "mode" else "median"
    } else if (is.factor(x) || is.character(x) || is.logical(x)) {
      val <- .mode_value(x)
      source[v] <- "mode"
    } else {
      next
    }
    base[[v]] <- .as_column_value(val, x)
  }
  # A factor of the time variable (e.g. as.factor(year)) defaults to the last level
  if (!is.null(time_var) && time_var %in% names(dat)) {
    base[[time_var]] <- .as_column_value(max(dat[[time_var]], na.rm = TRUE), dat[[time_var]])
    source[time_var] <- "last"
  }
  for (v in terms$term[terms$type == "factor"]) {
    x <- dat[[v]]
    if (identical(v, time_var)) next
    lv <- if (is.factor(x)) levels(droplevels(x)) else sort(unique(as.character(x)))
    if (!is.null(time_var) && time_var %in% names(dat) &&
        all(lv %in% as.character(unique(dat[[time_var]])))) {
      base[[v]] <- .as_column_value(lv[length(lv)], x)
      source[v] <- "last"
    }
  }
  # User references
  for (v in names(ref)) {
    if (!v %in% names(dat)) {
      warning("Reference variable '", v, "' is not in the data of model '",
              model_name, "'; ignored.")
      next
    }
    base[[v]] <- .as_column_value(ref[[v]], dat[[v]])
    source[v] <- "user"
  }
  # A user reference for the time variable also sets factors of it (e.g. fyear)
  if (!is.null(time_var) && time_var %in% names(ref)) {
    for (v in setdiff(names(source)[source == "last"], c(time_var, names(ref)))) {
      base[[v]] <- .as_column_value(ref[[time_var]], dat[[v]])
      source[v] <- "user"
    }
  }

  # Values to predict along a term
  term_values <- function(v, type) {
    x <- dat[[v]]
    if (type == "factor") {
      if (is.factor(x)) return(levels(droplevels(x)))
      return(as.character(sort(unique(x))))
    }
    if (terms$discrete[terms$term == v]) {
      return(seq(min(x, na.rm = TRUE), max(x, na.rm = TRUE), length.out = n))
    }
    q <- stats::quantile(x, c(0.005, 0.995), na.rm = TRUE, names = FALSE)
    seq(q[1], q[2], length.out = n)
  }
  vary <- function(v, type, values) {
    nd <- base[rep(1, length(values)), , drop = FALSE]
    nd[[v]] <- .as_column_value(values, dat[[v]])
    nd$.term <- v
    nd$.x <- if (type == "factor") as.character(values) else as.character(signif(values, 6))
    nd$.xnum <- if (type == "factor") seq_along(values) else values
    nd
  }
  pred <- function(nd, se) {
    stats::predict(fit, newdata = nd, re_form = NA, re_form_iid = NA,
                   se_fit = se, model = NA, offset = rep(0, nrow(nd)))
  }

  # Peak references, found without standard errors
  peak <- intersect(peak, terms$term[terms$type == "continuous"])
  peak <- setdiff(peak, names(ref))
  for (v in peak) {
    values <- term_values(v, "continuous")
    p0 <- pred(vary(v, "continuous", values), se = FALSE)
    base[[v]] <- .as_column_value(values[which.max(p0$est)], dat[[v]])
    source[v] <- "peak"
  }

  # Panel order: peak terms first, then formula order
  ord <- c(intersect(peak, terms$term), setdiff(terms$term, peak))
  terms <- terms[match(ord, terms$term), , drop = FALSE]

  nd <- do.call(rbind, lapply(seq_len(nrow(terms)), function(i) {
    vary(terms$term[i], terms$type[i], term_values(terms$term[i], terms$type[i]))
  }))
  p <- pred(nd, se = se_fit)

  delta <- isTRUE(fit$family$delta)
  linkinv <- if (delta) exp else fit$family$linkinv
  if (!is.function(linkinv)) linkinv <- exp
  z <- stats::qnorm(1 - (1 - level) / 2)
  se <- if (se_fit) p$est_se else NA_real_
  lab <- function(v) if (!is.null(labels) && v %in% names(labels)) labels[[v]] else v

  effects <- data.frame(
    model = model_name,
    term = p$.term,
    label = vapply(p$.term, lab, character(1), USE.NAMES = FALSE),
    type = terms$type[match(p$.term, terms$term)],
    x = p$.x,
    xnum = p$.xnum,
    est = linkinv(p$est),
    lwr = linkinv(p$est - z * se),
    upr = linkinv(p$est + z * se),
    stringsAsFactors = FALSE
  )

  refs <- data.frame(
    model = model_name,
    term = terms$term,
    label = vapply(terms$term, lab, character(1), USE.NAMES = FALSE),
    type = terms$type,
    value = vapply(terms$term, function(v) as.character(base[[v]]), character(1),
                   USE.NAMES = FALSE),
    source = unname(source[terms$term]),
    stringsAsFactors = FALSE
  )
  refs$xnum <- vapply(seq_len(nrow(refs)), function(i) {
    if (refs$type[i] == "continuous") return(as.numeric(refs$value[i]))
    e <- effects[effects$term == refs$term[i], ]
    k <- e$xnum[e$x == refs$value[i]]
    if (length(k)) k[1] else NA_real_
  }, numeric(1))
  refs$source[is.na(refs$source)] <- "median"

  list(effects = effects, ref = refs)
}

#' @export
print.sdmTMB_conditional_effects <- function(x, ...) {
  refs <- attr(x, "ref")
  cat("Conditional effects of", length(unique(x$model)), "model(s):",
      paste(unique(as.character(x$model)), collapse = ", "), "\n")
  cat("Terms:", paste(unique(x$label), collapse = ", "), "\n")
  cat("References:\n")
  r <- refs
  cont <- r$type == "continuous"
  r$value[cont] <- format(signif(as.numeric(r$value[cont]), 4), trim = TRUE)
  print(as.data.frame(r[, c("model", "label", "value", "source")]), row.names = FALSE)
  invisible(x)
}

#' Plot conditional effects of sdmTMB models
#'
#' @description
#' Draws the output of [conditional_effects()]: one row per model (with the
#' model name as a heading when there are several) and one panel per term, on
#' the response scale with free y axes. Continuous terms are a line with a
#' confidence ribbon and a rug of the values at observations with a positive
#' response; factors (e.g. gear type or year) are point ranges. A grey vertical
#' line marks the reference value of each term. Panel slots are aligned across
#' models, so the same term lines up in every row; a model without a term
#' leaves its slot empty.
#'
#' @param x An `sdmTMB_conditional_effects` object from [conditional_effects()].
#' @param fit Optional. The fitted model, or the list of models passed to
#'   [conditional_effects()], for the rug. The rug is drawn only when `data` or
#'   `fit` is given.
#' @param data Optional data frame for the rug, with the continuous variables
#'   and the response. Overrides `fit`.
#' @param response Character. Name of the response column in `data` for the
#'   rug (positive values only). Taken from the model formula when `fit` is
#'   given.
#' @param y_lab Character. y-axis label. Default `"Predicted response"`.
#' @param base_size Numeric. Base font size. Default `9`.
#' @param widths Optional named numeric vector of relative panel widths by
#'   term (variable name). By default continuous panels are 1.3 wide and factor
#'   panels grow with the number of levels. Factor labels longer than four
#'   characters are slanted when together they would crowd the axis.
#' @param ... Not used.
#'
#' @return A `cowplot` grid (a `ggplot` object).
#'
#' @section AI assistance:
#' Written with Claude Opus 5.5 (Anthropic); reviewed in full by Claude Opus
#' 5.5 (Anthropic), 2026-11-17.
#'
#' @author Mikko Vihtakari
#' @seealso [conditional_effects()], [effects_reference_text()]
#' @examples
#' \donttest{
#' d <- subset(sebastes, year >= 2021 & cruiseseries %in% c("EcoS", "EggaN"))
#' mesh <- sdmTMB::make_mesh(d, c("X", "Y"), cutoff = 80)
#' m <- sdmTMB::sdmTMB(
#'   density ~ s(depth, k = 5) + geartype,
#'   data = d, mesh = mesh, family = sdmTMB::tweedie()
#' )
#' eff <- conditional_effects(m, se_fit = FALSE)
#' plot(eff, fit = m, y_lab = "Density (kg/nmi^2)")
#' }
#' @method plot sdmTMB_conditional_effects
#' @export
plot.sdmTMB_conditional_effects <- function(x, fit = NULL, data = NULL,
                                            response = NULL,
                                            y_lab = "Predicted response",
                                            base_size = 9, widths = NULL, ...) {
  refs <- attr(x, "ref")
  models <- levels(factor(x$model))

  # Rug data per model: observations with a positive response
  rug_data <- function(model) {
    if (!is.null(data)) {
      if (is.null(response)) return(data)
      return(data[!is.na(data[[response]]) & data[[response]] > 0, , drop = FALSE])
    }
    if (is.null(fit)) return(NULL)
    f <- if (inherits(fit, "sdmTMB")) fit else fit[[model]] %||% fit[[1]]
    if (!inherits(f, "sdmTMB")) return(NULL)
    d <- as.data.frame(f$data)
    form <- if (is.list(f$formula)) f$formula[[1]] else f$formula
    resp <- response %||% all.vars(form[[2]])[1]
    if (!resp %in% names(d)) return(d)
    d[!is.na(d[[resp]]) & d[[resp]] > 0, , drop = FALSE]
  }

  slots <- unique(x$term)
  slot_type <- x$type[match(slots, x$term)]
  slot_n <- vapply(slots, function(v) length(unique(x$x[x$term == v])), numeric(1))
  default_w <- ifelse(slot_type == "continuous", 1.3,
                      pmax(0.6, pmin(2.4, 0.3 + 0.08 * slot_n)))
  names(default_w) <- slots
  if (!is.null(widths)) default_w[intersect(names(widths), slots)] <-
    widths[intersect(names(widths), slots)]

  rows <- lapply(models, function(mod) {
    e <- x[x$model == mod, , drop = FALSE]
    r <- refs[refs$model == mod, , drop = FALSE]
    rd <- rug_data(mod)
    first <- slots[slots %in% e$term][1]
    panels <- lapply(slots, function(v) {
      if (!v %in% e$term) return(NULL)
      d <- as.data.frame(e[e$term == v, , drop = FALSE])
      ref_x <- r$xnum[r$term == v]
      p <- ggplot2::ggplot(d, ggplot2::aes(x = .data$xnum, y = .data$est))
      if (length(ref_x) && !is.na(ref_x)) {
        p <- p + ggplot2::geom_vline(xintercept = ref_x, colour = "grey70")
      }
      if (d$type[1] == "continuous") {
        if (!all(is.na(d$lwr))) {
          p <- p + ggplot2::geom_ribbon(
            ggplot2::aes(ymin = .data$lwr, ymax = .data$upr), alpha = 0.2
          )
        }
        p <- p + ggplot2::geom_line()
        if (!is.null(rd) && v %in% names(rd)) {
          rx <- rd[[v]]
          rx <- rx[!is.na(rx) & rx >= min(d$xnum) & rx <= max(d$xnum)]
          if (length(rx)) {
            p <- p + ggplot2::geom_rug(
              data = data.frame(rx = rx), ggplot2::aes(x = .data$rx),
              inherit.aes = FALSE, sides = "b", alpha = 0.1,
              length = ggplot2::unit(0.02, "npc")
            )
          }
        }
      } else {
        if (all(is.na(d$lwr))) {
          p <- p + ggplot2::geom_point(size = 1)
        } else {
          p <- p + ggplot2::geom_pointrange(
            ggplot2::aes(ymin = .data$lwr, ymax = .data$upr), size = 0.15
          )
        }
        k <- nrow(d)
        step <- if (k > 10) ceiling(k / 6) else 1
        idx <- seq(1, k, by = step)
        if (k > 10 && idx[length(idx)] != k) idx <- c(idx[idx <= k - step / 2], k)
        p <- p + ggplot2::scale_x_continuous(
          breaks = d$xnum[idx], labels = d$x[idx],
          expand = ggplot2::expansion(add = 0.5)
        )
        # Long level names (e.g. trawl models) are slanted so that they do not
        # overlap; short ones (years, months, "Cod") stay horizontal.
        lab_n <- nchar(d$x[idx])
        if (max(lab_n) > 4 && sum(lab_n) > 12) {
          p <- p + ggplot2::guides(x = ggplot2::guide_axis(angle = 45))
        }
      }
      p + ggplot2::labs(x = d$label[1], y = if (v == first) y_lab else NULL) +
        ggplot2::theme_bw(base_size = base_size)
    })
    grid <- cowplot::plot_grid(plotlist = panels, nrow = 1,
                               rel_widths = unname(default_w), align = "h")
    if (length(models) == 1) return(grid)
    heading <- cowplot::ggdraw() +
      cowplot::draw_label(mod, x = 0.01, hjust = 0, size = base_size + 1)
    cowplot::plot_grid(heading, grid, ncol = 1, rel_heights = c(0.08, 1))
  })
  if (length(rows) == 1) return(rows[[1]])
  cowplot::plot_grid(plotlist = rows, ncol = 1)
}

#' Caption text stating the reference values of conditional effects
#'
#' @description
#' Writes the reference value of every term of a [conditional_effects()]
#' output as text for a figure caption, e.g. "depth 412 (peak of the depth
#' effect; Model A), 389 (Model B); geartype Shrimp (most common level); year
#' 2025 (last level)". References that differ between models are listed per
#' model.
#'
#' @param x An `sdmTMB_conditional_effects` object.
#' @param digits Integer. Significant digits for continuous references.
#'   Default `3`.
#'
#' @return A character string.
#'
#' @section AI assistance:
#' Written with Claude Opus 5.5 (Anthropic); reviewed in full by Claude Opus
#' 5.5 (Anthropic), 2026-11-17.
#'
#' @author Mikko Vihtakari
#' @seealso [conditional_effects()]
#' @examples
#' \donttest{
#' d <- subset(sebastes, year >= 2021 & cruiseseries %in% c("EcoS", "EggaN"))
#' mesh <- sdmTMB::make_mesh(d, c("X", "Y"), cutoff = 80)
#' m <- sdmTMB::sdmTMB(
#'   density ~ s(depth, k = 5) + geartype,
#'   data = d, mesh = mesh, family = sdmTMB::tweedie()
#' )
#' effects_reference_text(conditional_effects(m, se_fit = FALSE))
#' }
#' @export
effects_reference_text <- function(x, digits = 3) {
  if (!inherits(x, "sdmTMB_conditional_effects")) {
    stop("`x` must be an sdmTMB_conditional_effects object.")
  }
  refs <- attr(x, "ref")
  multi <- length(unique(refs$model)) > 1
  why <- c(peak = "at the peak of its effect", mode = "the most common value",
           last = "the last level", median = "the median", user = "set by the user")
  fmt <- function(r) {
    if (r$type[1] != "continuous") return(r$value)
    format(signif(as.numeric(r$value), digits), trim = TRUE, scientific = FALSE)
  }
  parts <- vapply(unique(refs$term), function(v) {
    r <- refs[refs$term == v, , drop = FALSE]
    r$shown <- fmt(r)
    label <- r$label[1]
    reason <- unique(why[r$source])
    if (r$type[1] == "factor" && all(r$source == "mode")) reason <- "the most common level"
    reason <- paste(reason, collapse = "/")
    if (!multi || length(unique(r$shown)) == 1) {
      paste0(label, " ", r$shown[1], " (", reason, ")")
    } else {
      paste0(label, " ", paste0(r$shown, " (", r$model, ")", collapse = ", "),
             " (", reason, ")")
    }
  }, character(1))
  paste(parts, collapse = "; ")
}
