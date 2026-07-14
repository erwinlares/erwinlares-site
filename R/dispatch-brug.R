# ============================================================
# dispatch_brug.R — cross-post to github.com/erwinlares/the-burrows
# Uses the GitHub Contents API — no local clone needed.
#
# Retraction logic (retract_gh(), github_delete_file()) lives in
# retract.R. The shared Contents API primitives (github_get_sha(),
# github_put_file()) live in github-helpers.R — pulled out from here
# once dispatch-caow.R needed the same two functions.
# ============================================================

# NOTE: this list is currently boolean-free by construction (title,
# author, date, categories, description, engine — all strings/lists).
# That matters because yaml::as.yaml() dumps R logicals as yes/no by
# default, not true/false, and Quarto's strict YAML 1.2 parser rejects
# yes/no outright — see the CAOW build failure this caused in
# dispatch-caow.R (2026-07-14). If a logical field is ever added to what
# this function keeps, apply the same fix used there: pass
# handlers = list(logical = function(x) { r <- ifelse(x, "true", "false");
# class(r) <- "verbatim"; r }) to the as.yaml() call in
# make_cleaned_post_text() below.
strip_front_matter_brug <- function(fm) {
  clean <- list()
  if (!is.null(fm$title)) {
    clean$title <- fm$title
  }
  if (!is.null(fm$author)) {
    if (is.list(fm$author) && !is.null(fm$author[[1]]$name)) {
      clean$author <- fm$author[[1]]$name
    } else {
      clean$author <- as.character(fm$author)
    }
  }
  if (!is.null(fm$date)) {
    clean$date <- format(as.Date(as.character(fm$date)), "%Y-%m-%d")
  }
  if (!is.null(fm$categories)) {
    clean$categories <- fm$categories
  }
  if (!is.null(fm$description)) {
    clean$description <- fm$description
  }
  # Prevent R execution on BRUG's GitHub Actions CI
  # Code blocks render as static syntax-highlighted code, no R needed
  clean$engine <- "markdown"
  clean
}

make_cleaned_post_text <- function(source_path, clean_fm) {
  lines <- readLines(source_path, warn = FALSE)
  delimiters <- which(trimws(lines) == "---")
  if (length(delimiters) < 2) {
    return(paste(lines, collapse = "\n"))
  }
  content <- lines[(delimiters[2] + 1):length(lines)]
  yaml_text <- trimws(yaml::as.yaml(clean_fm, indent = 2), which = "right")
  paste(c("---", yaml_text, "---", content), collapse = "\n")
}

dispatch_brug <- function(post_path, front_matter) {
  pat <- Sys.getenv("GITHUB_PAT_BRUG")
  if (nchar(pat) == 0) {
    stop("GITHUB_PAT_BRUG not set in .Renviron", call. = FALSE)
  }
  
  owner <- "erwinlares"
  repo <- "the-burrows"
  post_dir_name <- basename(dirname(post_path))
  commit_msg <- paste0("publish: ", front_matter$title)
  
  # resources/ is the default landing section for BRUG posts — most content
  # is reference/tutorial material. blog/ is reserved for posts explicitly
  # tagged as announcement- or journal-style updates.
  blog_categories <- c("announcement", "journal")
  is_blog_post <- any(tolower(front_matter$categories) %in% blog_categories)
  section <- if (is_blog_post) "blog" else "resources"
  
  source_files <- list.files(dirname(post_path), full.names = TRUE)
  source_files <- source_files[!dir.exists(source_files)] # skip subdirs, e.g. Quarto's index_files/
  
  for (f in source_files) {
    api_path <- paste0(section, "/", post_dir_name, "/", basename(f))
    
    # Prepare content — clean front matter for index.qmd, raw bytes for everything else
    if (basename(f) == "index.qmd") {
      clean_fm <- strip_front_matter_brug(front_matter)
      content_raw <- charToRaw(make_cleaned_post_text(f, clean_fm))
    } else {
      content_raw <- readBin(f, "raw", n = file.size(f))
    }
    
    # Fetch existing SHA (needed if file already exists)
    sha <- github_get_sha(owner, repo, api_path, pat)
    github_put_file(owner, repo, api_path, content_raw, commit_msg, pat, sha)
    message("  ✓ ", basename(f))
  }
  
  message("✓ Dispatched to BRUG (", section, "): ", front_matter$title)
  section # returned so publish() can log where this landed
}