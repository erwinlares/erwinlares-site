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
  
  source_files  <- list.files(dirname(post_path), full.names = TRUE)
  
  for (f in source_files) {
    api_path <- paste0("blog/", post_dir_name, "/", basename(f))
    
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
  
  message("\u2713 Dispatched to BRUG: ", front_matter$title)
  invisible(TRUE)
}