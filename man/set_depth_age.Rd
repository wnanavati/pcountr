\name{set_metadata}
\alias{set_metadata}
\alias{set_depth_age}
\alias{set_depth}
\title{Set or update metadata for a sample in a loaded site}
\usage{
set_metadata(
  site,
  sample,
  depth_top = NULL,
  depth_bottom = NULL,
  age_top = NULL,
  age_bottom = NULL,
  sample_name = NULL,
  sample_quantity = NULL,
  sample_units = NULL,
  spike_tablets = NULL,
  spike_density = NULL,
  spike_units = NULL
)

set_depth_age(
  site,
  sample,
  depth_top,
  depth_bottom,
  age_top = NA_real_,
  age_bottom = NA_real_
)

set_depth(
  site,
  sample,
  depth_top,
  depth_bottom,
  age_top = NA_real_,
  age_bottom = NA_real_
)
}
\arguments{
\item{site}{A \code{pollen_site} with a \code{samples} list.}

\item{sample}{The sample to update: a character key (name in
\code{site$samples}) or an integer index.}

\item{depth_top, depth_bottom}{Sample interval in cm. When both are supplied,
\code{depth_top} must be less than \code{depth_bottom}.}

\item{age_top, age_bottom}{Ages in calibrated years BP (present = 1950 CE).}

\item{sample_name}{Analyst-assigned label (e.g. \code{"KF24sh#001"}).}

\item{sample_quantity}{Amount of sediment processed (numeric).}

\item{sample_units}{Units of \code{sample_quantity}: \code{"ml"} or \code{"g"}.}

\item{spike_tablets}{Quantity of spike added — number of tablets, ml, or g
(interpretation depends on \code{spike_units}).}

\item{spike_density}{Microspheres per unit of spike (per tablet, per ml,
or per g).}

\item{spike_units}{Units of the spike: \code{"tablets"}, \code{"ml"}, or \code{"g"}.}
}
\value{
The updated \code{pollen_site} (invisibly).
}
\description{
Updates any combination of depth, age, sample identity, sample quantity, and
spike fields for a single sample, then re-sorts the site by \code{depth_top}
ascending (NA-depth samples remain at the end). Only arguments that are
explicitly supplied overwrite the existing value; omitted arguments leave the
current value unchanged.
}
\details{
For sites with many samples, fill in the package metadata template and loop
over rows (see the template for a ready-to-paste code snippet):

\if{html}{\out{<div class="sourceCode r">}}\preformatted{file.show(system.file("templates/metadata_template.csv", package = "pcountr"))
}\if{html}{\out{</div>}}

\code{set_depth_age()} and \code{set_depth()} are deprecated wrappers that call
\code{set_metadata()} with only the depth and age arguments.
}
\seealso{
\code{\link[=read_site]{read_site()}} for bulk depth/age assignment via a metadata sheet.
}
