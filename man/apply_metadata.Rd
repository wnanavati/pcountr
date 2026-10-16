\name{apply_metadata}
\alias{apply_metadata}
\title{Apply an edited metadata CSV back to a loaded site}
\usage{
apply_metadata(site, csv, write = TRUE)
}
\arguments{
\item{site}{A \code{pollen_site} with samples loaded.}

\item{csv}{Path to a CSV file (as produced by \code{\link[=extract_metadata]{extract_metadata()}}), or a
data frame with the same column structure.}

\item{write}{If \code{TRUE} (default), write each modified sample back to its
source YAML file. Samples without a resolvable YAML path are updated in
memory only (a message is emitted).}
}
\value{
The updated \code{pollen_site} (invisibly).
}
\description{
Reads the CSV produced by \code{\link[=extract_metadata]{extract_metadata()}}, matches each row to a
sample in the site, applies every non-NA column via \code{\link[=set_metadata]{set_metadata()}}, and
optionally writes the updated samples back to their source YAML files.
This makes \code{extract_metadata()} + edit + \code{apply_metadata()} a complete
round-trip edit workflow for any metadata field.
}
\section{Row matching}{
Rows are matched to samples first by \code{source_file} (exact path stored in
\code{meta$source_file}), then by \code{sample_name} for rows where \code{source_file} is
absent or does not match any sample. Rows that cannot be matched by either
key produce a warning and are skipped.
}
\section{Columns applied}{
All editable columns present in the CSV are applied when non-NA:
\code{depth_top}, \code{depth_bottom}, \code{age_top}, \code{age_bottom}, \code{sample_name},
\code{sample_quantity}, \code{units}, \code{spike_tablets}, \code{spike_density},
\code{spike_units}, \code{conc_method}, \code{title}, and the per-sample
\code{latitude}, \code{longitude}, \code{elevation}, \code{collection_date}, \code{device} and
\code{event_label}. The \code{source_file} column is used for matching only and is
never written back.

The six provenance columns carry one value per row, because provenance is
recorded per sample. Editing them here is the supported way to add positions
to a site counted before they were known: for a single core, set the same
value in every row and \code{\link[=read_site]{read_site()}} will report it on the site; for a
transect, give each row its own, and the site reports how many distinct
positions it holds rather than a single one.
}
\examples{
\dontrun{
# Extract metadata to CSV for review/editing
extract_metadata(my_site, file = "metadata.csv")

# ... edit metadata.csv in Excel ...

# Push edits back — updates in memory and saves YAMLs to disk
my_site <- apply_metadata(my_site, "metadata.csv")
}
}
\seealso{
\code{\link[=extract_metadata]{extract_metadata()}}, \code{\link[=set_metadata]{set_metadata()}}
}
