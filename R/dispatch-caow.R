# ============================================================
# dispatch_caow.R — cross-post to github.com/erwinlares/caow-website
#
# Unlike dispatch_brug() (which cleans/re-renders content for a
# platform with no R/Quarto in CI), caow-website runs its own
# Quarto + GitHub + Netlify pipeline — the same stack as erwinlares.com.
# So dispatch_caow() pushes the .qmd source (and any sibling assets,
# e.g. post images) largely as-is via the GitHub Contents API and lets
# CAOW's own Netlify build render it.
#
# The one piece of front matter that can't be shared verbatim is
# format.html.include-before-body, which CAOW's blog template expects
# (a relative path to a repo-root partial, ../../_partials/blog-nav.html)
# but which has no meaning — and would break the erwinlares.com build —
# if it ever ended up in the hub's own posts/ copy. prepare_front_matter_caow()
# injects it only on the pushed copy. publish_to is stripped for the
# same reason, in reverse: it's hub-only bookkeeping with no meaning in
# caow-website.
#
# Uses github_get_sha() / github_put_file() from github-helpers.R.
# ============================================================

# Prepares front matter for the caow-website copy of a post:
#  - drops publish_to (hub-only bookkeeping, meaningless in caow-website)
#  - merges in format.html.include-before-body without clobbering any
#    other format.html options the source post may already carry
prepare_front_matter_caow <- function(fm) {
  fm$publish_to <- NULL
  
  partial_path <- "../../_partials/blog-nav.html"
  
  if (is.null(fm$format)) {
    fm$format <- list(html = list(`include-before-body` = partial_path))
  } else if (is.null(fm$format$html)) {
    fm$format$html <- list(`include-before-body` = partial_path)
  } else {
    fm$format$html$`include-before-body` <- partial_path
  }
  
  fm
}

make_prepared_post_text <- function(source_path, prepared_fm) {
  lines <- readLines(source_path, warn = FALSE)
  delimiters <- which(trimws(lines) == "---")
  if (length(delimiters) < 2) {
    return(paste(lines, collapse = "\n"))
  }
  content <- lines[(delimiters[2] + 1):length(lines)]
  
  # yaml::as.yaml() defaults to dumping logicals as YAML 1.1's yes/no,
  # not true/false. Quarto parses YAML 1.2 strictly and rejects yes/no
  # outright, so any execute:/format:html: boolean in the source front
  # matter (echo, toc, number-sections, etc.) would otherwise break the
  # CAOW build the moment a post carrying one got dispatched there.
  yaml_text <- trimws(
    yaml::as.yaml(
      prepared_fm,
      indent = 2,
      handlers = list(
        logical = function(x) {
          result <- ifelse(x, "true", "false")
          class(result) <- "verbatim"
          result
        }
      )
    ),
    which = "right"
  )
  paste(c("---", yaml_text, "---", content), collapse = "\n")
}

dispatch_caow <- function(post_path, front_matter) {
  pat <- Sys.getenv("GITHUB_PAT_CAOW")
  if (nchar(pat) == 0) {
    stop("GITHUB_PAT_CAOW not set in .Renviron", call. = FALSE)
  }
  
  owner <- "erwinlares"
  repo <- "caow-website"
  post_dir_name <- basename(dirname(post_path))
  commit_msg <- paste0("publish: ", front_matter$title)
  
  # caow-website has a flat blog/ target — every post lands at
  # blog/{post_dir_name}/, no routing to compute (unlike BRUG's
  # resources/ vs blog/ split).
  section <- "blog"
  
  source_files <- list.files(dirname(post_path), full.names = TRUE)
  source_files <- source_files[!dir.exists(source_files)] # skip subdirs, e.g. Quarto's index_files/
  
  for (f in source_files) {
    api_path <- paste0(section, "/", post_dir_name, "/", basename(f))
    
    # Prepare content — inject/strip front matter for index.qmd, raw bytes for everything else
    if (basename(f) == "index.qmd") {
      prepared_fm <- prepare_front_matter_caow(front_matter)
      content_raw <- charToRaw(make_prepared_post_text(f, prepared_fm))
    } else {
      content_raw <- readBin(f, "raw", n = file.size(f))
    }
    
    # Fetch existing SHA (needed if file already exists)
    sha <- github_get_sha(owner, repo, api_path, pat)
    github_put_file(owner, repo, api_path, content_raw, commit_msg, pat, sha)
    message("  ✓ ", basename(f))
  }
  
  message("✓ Dispatched to CAOW (", section, "): ", front_matter$title)
  section # returned so publish() can log where this landed
}