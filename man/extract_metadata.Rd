\name{extract_metadata}
\alias{extract_metadata}
\title{Extract sample metadata from a site or folder of YAML files}
\usage{
extract_metadata(x, file = NULL)
}
\arguments{
\item{x}{A \code{pollen_site} object, or a character path to a folder containing
\code{.yaml}/\code{.yml}/\code{.cnt} count files. If a path is given, \code{\link{read_site}()} is
called internally.}

\item{file}{Optional path to a \code{.csv} file to write. If \code{NULL} (default)
the data frame is returned but not written.}
}
\value{
A data frame with columns: \code{sample_name}, \code{depth_top},
\code{depth_bottom}, \code{age_top}, \code{age_bottom}, \code{sample_quantity}, \code{units},
\code{spike_tablets}, \code{spike_density}, \code{spike_units}, \code{conc_method},
\code{title}, \code{source_file}.
}
\description{
Creates a data frame with one row per sample, containing all metadata
fields found in the loaded samples. The output matches the CSV format
accepted by the \code{metadata} argument of \code{\link{read_site}()}, making this the
reverse of \code{\link{set_metadata}()}: use it to bootstrap a metadata file from
counts that were saved without one.

Fields absent from a sample are left \code{NA}.
}
\seealso{
\code{\link{set_metadata}()}, \code{\link{read_site}()}
}
