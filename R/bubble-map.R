#' Bubble map of a response variable
#'
#' @description
#' Draws a bubble map of a response variable (e.g. catch density) over a
#' [ggOceanMaps::basemap()]: zero observations are shown as small crosses and
#' positive observations as size- and colour-scaled circles. Useful for a quick
#' overview of survey data before modelling.
#'
#' @param x A data frame with longitude/latitude columns (auto-detected by
#'   [ggOceanMaps::guess_coordinate_columns()]), a year column, and a response
#'   column (see `response`).
#' @param response Character. Name of the response column. Default `"value"`.
#' @param label Fill/size legend label. Default an expression for density.
#' @param zero_color Colour for zero observations. Default `"grey"`.
#' @param point_stroke Numeric point stroke width. Default `0.3`.
#' @param ncol Integer. Number of facet columns when `by_year = TRUE`. Default
#'   `6`.
#' @param by_year Logical. Facet by year? Default `TRUE`.
#' @param filled_circles Logical. Use filled circles (`TRUE`, default) or
#'   coloured outlines?
#' @param axis_text,axis_title Logical. Show axis text / titles? Default `FALSE`.
#' @param legend_rows Integer. Number of legend rows. Default `1`.
#' @param base_size Numeric. Base font size. Default `10`.
#'
#' @return A `ggplot` object.
#'
#' @author Mikko Vihtakari
#' @seealso [ggOceanMaps::basemap()]
#' @import ggplot2
#' @importFrom rlang .data
#' @examples
#' \donttest{
#' data(sebastes)
#' d <- subset(sebastes, year %in% 2018:2019)
#' bubble_map(d, response = "density", by_year = TRUE, ncol = 2)
#' }
#' @export
bubble_map <- function(
  x,
  response = "value",
  label = expression(paste("Density (kg ", nmi^-2, ")")),
  zero_color = "grey",
  point_stroke = 0.3,
  ncol = 6,
  by_year = TRUE,
  filled_circles = TRUE,
  axis_text = FALSE,
  axis_title = FALSE,
  legend_rows = 1,
  base_size = 10
) {
  if (!requireNamespace("ggspatial", quietly = TRUE)) {
    stop("Package 'ggspatial' is required for bubble_map().")
  }
  if (!response %in% names(x)) {
    stop("Response column '", response, "' not found in `x`.")
  }

  # Standardise coordinate + response + year columns
  tmp <- ggOceanMaps::guess_coordinate_columns(x)
  x[["lon"]] <- x[[tmp[1]]]
  x[["lat"]] <- x[[tmp[2]]]
  x[["value"]] <- x[[response]]
  year_col <- grep("year", colnames(x), ignore.case = TRUE, value = TRUE)[1]
  if (!is.na(year_col)) x[["year"]] <- x[[year_col]]

  max_val <- ceiling(max(x$value, na.rm = TRUE))
  color_breaks <- sort(unique(c(
    0,
    unname(plyr::round_any(
      stats::quantile(x$value[x$value != 0], c(seq(0, 1, 0.25), 0.99, 0.995),
                      na.rm = TRUE),
      1, floor
    )),
    max_val
  )))
  color_breaks <- color_breaks[color_breaks <= (max_val + 1)]

  pos_scale <- if (filled_circles) {
    ggplot2::binned_scale(
      aesthetics = "fill",
      palette = function(z) viridis::turbo(length(color_breaks) - 1),
      limits = c(0, max_val + 1), breaks = color_breaks, show.limits = TRUE
    )
  } else {
    ggplot2::binned_scale(
      aesthetics = "colour",
      palette = function(z) viridis::turbo(length(color_breaks) - 1),
      limits = c(0, max_val + 1), breaks = color_breaks, show.limits = TRUE
    )
  }

  pos <- x[x$value > 0, ]
  pos <- pos[order(-pos$value), ]

  pos_layer <- if (filled_circles) {
    ggspatial::geom_spatial_point(
      data = pos,
      ggplot2::aes(x = .data$lon, y = .data$lat, size = .data$value,
                   fill = .data$value, shape = .data$value == 0),
      alpha = 0.4, crs = 4326, stroke = point_stroke
    )
  } else {
    ggspatial::geom_spatial_point(
      data = pos,
      ggplot2::aes(x = .data$lon, y = .data$lat, size = .data$value,
                   colour = .data$value, shape = .data$value == 0),
      alpha = 0.4, crs = 4326, stroke = point_stroke
    )
  }

  p <- ggOceanMaps::basemap(x, base_size = base_size, expand.factor = 1.05) +
    ggspatial::geom_spatial_point(
      data = x[x$value == 0, ],
      ggplot2::aes(x = .data$lon, y = .data$lat, shape = .data$value == 0),
      color = zero_color, size = 1, crs = 4326, stroke = 2 * point_stroke
    ) +
    pos_layer +
    ggplot2::labs(fill = label, color = label, size = label) +
    ggplot2::scale_shape_manual(values = c(`TRUE` = 3, `FALSE` = 21),
                                guide = "none") +
    ggplot2::scale_size(breaks = color_breaks, limits = c(0, max_val + 1),
                        range = c(1, 14)) +
    pos_scale +
    ggplot2::theme(legend.position = "bottom")

  if (by_year && "year" %in% names(x)) {
    p <- p + ggplot2::facet_wrap(~year, ncol = ncol)
  }
  if (!axis_title) p <- p + ggplot2::theme(axis.title = ggplot2::element_blank())
  if (!axis_text) {
    p <- p + ggplot2::theme(axis.text = ggplot2::element_blank(),
                            axis.ticks = ggplot2::element_blank())
  }
  p
}
