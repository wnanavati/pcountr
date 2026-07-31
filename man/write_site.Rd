\name{write_site}
\alias{write_site}
\title{Write all samples in a site to YAML files}
\usage{
write_site(site, folder, overwrite = FALSE)
}
\arguments{
\item{site}{A \code{pollen_site} with samples loaded.}

\item{folder}{Path to the output folder. Created if it does not exist.}

\item{overwrite}{If \code{FALSE} (default), existing \code{.yaml} files are skipped
with a message. Set \code{TRUE} to overwrite.}
}
\value{
The updated \code{pollen_site} (invisibly), with \code{meta$source_file} for
each written sample pointing to its new YAML path. Samples skipped due to
\code{overwrite = FALSE} retain their previous \code{source_file} value.
}
\description{
Converts every sample in a loaded \code{pollen_site} to a native YAML file in
\code{folder} using \code{\link[=write_pollen_count]{write_pollen_count()}}. This is the primary route for
migrating a folder of legacy \code{.CNT} files to the modern YAML format, and the
necessary first step before \code{\link[=apply_metadata]{apply_metadata()}} can write metadata back to
disk (\code{.CNT} files are read-only; \code{apply_metadata()} only writes to YAML).
}
\details{
After writing, each sample's \code{meta$source_file} is updated in the returned
site to the full normalised path of its new YAML, so the result can be
passed directly to \code{\link[=extract_metadata]{extract_metadata()}} or \code{\link[=apply_metadata]{apply_metadata()}} without
reloading from disk.
}
\section{CNT migration workflow}{

\preformatted{# 1. Load legacy CNT files (attach depths/ages from a sheet if available)
site <- read_site(cnt_dir, dic = "ECG.csv", metadata = "depths.csv")

# 2. Convert to YAML -- source_file is stamped on every sample
site <- write_site(site, "yaml_output/")

# 3. Export metadata, correct any errors, apply edits back to YAMLs
extract_metadata(site, file = "metadata.csv")
# ... edit metadata.csv ...
site <- apply_metadata(site, "metadata.csv")

# 4. Add new counts in the same folder and reload
count_app()
site <- read_site("yaml_output/", dic = "ECG.csv")
}
}

\seealso{
\code{\link[=read_site]{read_site()}}, \code{\link[=write_pollen_count]{write_pollen_count()}}, \code{\link[=extract_metadata]{extract_metadata()}},
\code{\link[=apply_metadata]{apply_metadata()}}
}
