# Centralised importFrom declarations so R CMD check does not flag base
# functions (setNames, quantile, read.csv, etc.) as undefined globals.

#' @importFrom stats setNames quantile
#' @importFrom utils read.csv read.table write.csv
NULL
