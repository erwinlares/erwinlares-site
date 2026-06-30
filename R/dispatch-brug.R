# ============================================================
# dispatch_brug.R — cross-post to github.com/erwinlares/the-burrows
# Uses the GitHub Contents API — no local clone needed.
# ============================================================

strip_front_matter_brug <- function(fm) {
  clean <- list()
  
  if (!is.null(fm$title))       clean$title       <- fm$title
  if (!is.null(fm$author)) {
    if (is.list(fm$author) && !is.null(fm$author[[1]]$name)) {
      clean$author <- fm$author[[1]]$name
    } else {
      clean$author <- as.character(fm$author)
    }
  }
  if (!is.null(fm$date))        clean$date        <- format(as.Date(as.character(fm$date)), "%Y-%m-%d")
  if (!is.null(fm$categories))  clean$categories  <- fm$categories
  if (!is.null(fm$description)) clean$description <- fm$description
  
  # Prevent R execution on BRUG's GitHub Actions CI
  # Code blocks render as static syntax-highlighted code, no R needed
  clean$engine <- "markdown"
  
  clean
}

make_cleaned_post_text <- function(source_path, clean_fm) {
  lines      <- readLines(source_path, warn = FALSE)
  delimiters <- which(trimws(lines) == "---")
  
  if (length(delimiters) < 2) {
    return(paste(lines, collapse = "\n"))
  }
  
  content   <- lines[(delimiters[2] + 1):length(lines)]
  yaml_text <- trimws(yaml::as.yaml(clean_fm, indent = 2), which = "right")
  
  paste(c("---", yaml_text, "---", content), collapse = "\n")
}

# Returns the SHA of a file if it exists, NULL on 404
github_get_sha <- function(owner, repo, path, pat) {
  url  <- paste0("https://api.github.com/repos/", owner, "/", repo, "/contents/", path)
  resp <- tryCatch(
    httr2::request(url) |>
      httr2::req_headers(
        Authorization        = paste("Bearer", pat),
        Accept               = "application/vnd.github+json",
        `X-GitHub-Api-Version` = "2022-11-28"
      ) |>
      httr2::req_perform(),
    httr2_http_404 = function(e) NULL
  )
  if (is.null(resp)) return(NULL)
  httr2::resp_body_json(resp)$sha
}

# Create or update a single file via the Contents API
github_put_file <- function(owner, repo, path, content_raw, commit_msg, pat, sha = NULL) {
  url  <- paste0("https://api.github.com/repos/", owner, "/", repo, "/contents/", path)
  b64  <- gsub("\n", "", openssl::base64_encode(content_raw))  # clean line breaks
  
  body <- list(message = commit_msg, content = b64)
  if (!is.null(sha)) body$sha <- sha  # required for updates
  
  httr2::request(url) |>
    httr2::req_headers(
      Authorization        = paste("Bearer", pat),
      Accept               = "application/vnd.github+json",
      `X-GitHub-Api-Version` = "2022-11-28"
    ) |>
    httr2::req_method("PUT") |>
    httr2::req_body_json(body) |>
    httr2::req_perform()
}

dispatch_brug <- function(post_path, front_matter) {
  pat <- Sys.getenv("GITHUB_PAT_BRUG")
  if (nchar(pat) == 0) stop("GITHUB_PAT_BRUG not set in .Renviron", call. = FALSE)
  
  owner         <- "erwinlares"
  repo          <- "the-burrows"
  post_dir_name <- basename(dirname(post_path))
  commit_msg    <- paste0("publish: ", front_matter$title)
  
  # resources/ is the default landing section for BRUG posts — most content
  # is reference/tutorial material. blog/ is reserved for posts explicitly
  # tagged as announcement- or journal-style updates.
  blog_categories <- c("announcement", "journal")
  is_blog_post    <- any(tolower(front_matter$categories) %in% blog_categories)
  section         <- if (is_blog_post) "blog" else "resources"
  
  source_files  <- list.files(dirname(post_path), full.names = TRUE)
  source_files  <- source_files[!dir.exists(source_files)]  # skip subdirs, e.g. Quarto's index_files/
  
  for (f in source_files) {
    api_path <- paste0(section, "/", post_dir_name, "/", basename(f))
    
    # Prepare content — clean front matter for index.qmd, raw bytes for everything else
    if (basename(f) == "index.qmd") {
      clean_fm     <- strip_front_matter_brug(front_matter)
      content_raw  <- charToRaw(make_cleaned_post_text(f, clean_fm))
    } else {
      content_raw  <- readBin(f, "raw", n = file.size(f))
    }
    
    # Fetch existing SHA (needed if file already exists)
    sha <- github_get_sha(owner, repo, api_path, pat)
    
    github_put_file(owner, repo, api_path, content_raw, commit_msg, pat, sha)
    
    message("  \u2713 ", basename(f))
  }
  
  message("\u2713 Dispatched to BRUG (", section, "): ", front_matter$title)
  section  # returned so publish() can log where this landed
}

# Deletes a single file via the Contents API. Requires the current SHA,
# which is why it always calls github_get_sha() first rather than trusting
# a cached value — the file may have changed since dispatch.
github_delete_file <- function(owner, repo, path, commit_msg, pat) {
  sha <- github_get_sha(owner, repo, path, pat)
  if (is.null(sha)) {
    message("  \u26a0 not found, skipping: ", path)
    return(invisible(FALSE))
  }
  
  url <- paste0("https://api.github.com/repos/", owner, "/", repo, "/contents/", path)
  
  httr2::request(url) |>
    httr2::req_headers(
      Authorization        = paste("Bearer", pat),
      Accept               = "application/vnd.github+json",
      `X-GitHub-Api-Version` = "2022-11-28"
    ) |>
    httr2::req_method("DELETE") |>
    httr2::req_body_json(list(message = commit_msg, sha = sha)) |>
    httr2::req_perform()
  
  message("  \u2717 removed: ", basename(path))
  invisible(TRUE)
}

# Removes a previously-dispatched post from a GitHub-hosted destination.
# Mirrors the local source_files list rather than discovering remote folder
# contents — this assumes local and remote stayed in sync, which holds as
# long as files are only ever added to a post locally and re-dispatched,
# never edited by hand on the remote side.
#
# owner, repo:  the GitHub repo to delete from (e.g. "erwinlares", "the-burrows")
# section:      subfolder the post currently lives in at the destination
#               (e.g. "blog" or "resources"). Optional — if omitted,
#               retract_gh() looks it up from dispatch_log.csv via the
#               "brug" platform entry. Only needed explicitly for posts
#               dispatched before the section column existed in the log.
# platform:     which platform's log entry to consult when section is
#               omitted (default "brug", the only GitHub-backed platform
#               so far).
#
# Also clears the matching dispatch_log.csv row for this post/platform so
# a subsequent publish() will redispatch rather than skipping it as
# already-dispatched.
retract_gh <- function(post_path, owner, repo, section = NULL, platform = "brug") {
  pat <- Sys.getenv("GITHUB_PAT_BRUG")
  if (nchar(pat) == 0) stop("GITHUB_PAT_BRUG not set in .Renviron", call. = FALSE)
  
  log <- load_dispatch_log()
  
  if (is.null(section)) {
    section <- get_dispatched_section(log, post_path, platform)
    if (is.na(section)) {
      stop(
        "No section found in dispatch_log.csv for this post/platform, ",
        "and none was provided explicitly. Pass section = \"blog\" or ",
        "section = \"resources\" directly.",
        call. = FALSE
      )
    }
    message("  (section \"", section, "\" found in dispatch_log.csv)")
  }
  
  post_dir_name <- basename(dirname(post_path))
  commit_msg    <- paste0("retract: ", post_dir_name)
  
  source_files <- list.files(dirname(post_path), full.names = TRUE)
  
  for (f in source_files) {
    api_path <- paste0(section, "/", post_dir_name, "/", basename(f))
    github_delete_file(owner, repo, api_path, commit_msg, pat)
  }
  
  # Clear the log row so publish() treats this post as un-dispatched
  log <- log[!(log$post_path == post_path & log$platform == platform), ]
  write.csv(log, "dispatch_log.csv", row.names = FALSE)
  
  message("\u2713 Retracted (", owner, "/", repo, ", ", section, "): ", post_dir_name)
  invisible(TRUE)
}