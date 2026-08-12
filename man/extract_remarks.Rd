\name{extract_remarks}
\alias{extract_remarks}
\title{Extract remarks from a pollen site}
\usage{
extract_remarks(site, id = c("before", "after"))
}
\arguments{
\item{site}{A \code{pollen_site} object.}

\item{id}{\code{"before"} (default) returns the grain counted immediately
\emph{before} the remark; \code{"after"} returns the grain counted
immediately \emph{after} it.  The ID is the taxon code concatenated with
the preservation string (e.g. \code{"I1"} for Picea, well-preserved), or
just the code when preservation was not recorded (e.g. \code{"I"}).
\code{NA} when no adjacent grain exists or when a sample lacks a full
event stream (format version 1 YAML).}
}
\value{
A data frame with columns:
\tabular{ll}{
  \code{sample_name} \tab Sample identifier from count metadata. \cr
  \code{slide}       \tab The slide active when the remark was written: the analyst's name for it, or its ordinal within the sample (1, 2, …) if never named. \cr
  \code{traverse}    \tab Traverse label active when the remark was made. \cr
  \code{id}          \tab Taxon ID of the adjacent grain (see \code{id}). \cr
  \code{remark}      \tab Remark text, verbatim. \cr
}
An empty data frame with the same columns is returned when no remarks
exist in any sample.
}
\description{
Returns a data frame of every inline remark recorded during counting across
all samples in a \code{pollen_site}, along with the taxon ID of the
immediately adjacent grain.
}
\details{
The adjacent grain is identified by event stream position.  For
\code{id = "before"}, the grain with the largest position number still
less than the remark's position is returned; for \code{id = "after"}, the
grain with the smallest position number greater than the remark's position.

Slides are tracked per sample, not per site. Every sample begins on slide 1;
each \code{slide_desc} event begins the next slide. In a legacy \code{.CNT}
file these are the \code{\{SLIDE NAME\}} tokens — the leading one names slide 1
and each subsequent one starts a new slide. In the counting app they are
created by the New Slide button.

Samples saved in the legacy format (YAML \code{format_version: 1}) do not
carry a full event stream, so slide transitions cannot be recovered: the
whole sample is reported against its recorded slide name (or slide 1), and
the \code{id} column is \code{NA}. Convert such samples with
\code{write_site()} to upgrade them to format version 2.
}
\examples{
\dontrun{
site <- read_site("path/to/yamls", dic = "path/to/dict.csv")

# Default: grain immediately before the remark
extract_remarks(site)

# Grain immediately after the remark
extract_remarks(site, id = "after")
}
}
\seealso{
\code{\link{extract_metadata}}, \code{\link{read_site}}
}
