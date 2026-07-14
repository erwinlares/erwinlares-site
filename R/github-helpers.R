# ============================================================
# github-helpers.R — shared GitHub Contents API primitives
#
# Used by any dispatcher that pushes files to a GitHub-hosted spoke
# via the Contents API (currently dispatch-brug.R and dispatch-caow.R).
# Kept platform-agnostic on purpose — no BRUG- or CAOW-specific
# knowledge belongs here. Extracted out of dispatch-brug.R when
# dispatch-caow.R was added, since both need the same two primitives.
# ============================================================

# Returns the SHA of a file if it exists, NULL on 404.
# Needed by github_put_file() below (updates require the current SHA),
# and by retract.R's github_delete_file() (deletions require it too).
github_get_sha <- function(owner, repo, path, pat) {
  url <- paste0(
    "https://api.github.com/repos/",
    owner,
    "/",
    repo,
    "/contents/",
    path
  )
  
  resp <- tryCatch(
    httr2::request(url) |>
      httr2::req_headers(
        Authorization = paste("Bearer", pat),
        Accept = "application/vnd.github+json",
        `X-GitHub-Api-Version` = "2022-11-28"
      ) |>
      httr2::req_perform(),
    httr2_http_404 = function(e) NULL
  )
  
  if (is.null(resp)) {
    return(NULL)
  }
  
  httr2::resp_body_json(resp)$sha
}

# Create or update a single file via the Contents API.
github_put_file <- function(
    owner,
    repo,
    path,
    content_raw,
    commit_msg,
    pat,
    sha = NULL
) {
  url <- paste0(
    "https://api.github.com/repos/",
    owner,
    "/",
    repo,
    "/contents/",
    path
  )
  
  b64 <- gsub("\n", "", openssl::base64_encode(content_raw)) # clean line breaks
  body <- list(message = commit_msg, content = b64)
  if (!is.null(sha)) {
    body$sha <- sha
  } # required for updates
  
  httr2::request(url) |>
    httr2::req_headers(
      Authorization = paste("Bearer", pat),
      Accept = "application/vnd.github+json",
      `X-GitHub-Api-Version` = "2022-11-28"
    ) |>
    httr2::req_method("PUT") |>
    httr2::req_body_json(body) |>
    httr2::req_perform()
}

# Deletes a single file via the Contents API.
#
# Idempotent by design: if the file is already gone (github_get_sha()
# returns NULL, i.e. a 404), this is treated as success rather than an
# error, since the end state — file absent — already holds. Used by
# retract_gh() in retract.R, once per file in a post's directory.
github_delete_file <- function(owner, repo, path, commit_msg, pat) {
  sha <- github_get_sha(owner, repo, path, pat)
  
  if (is.null(sha)) {
    message("  (already absent: ", path, ")")
    return(invisible(NULL))
  }
  
  url <- paste0(
    "https://api.github.com/repos/",
    owner,
    "/",
    repo,
    "/contents/",
    path
  )
  
  body <- list(message = commit_msg, sha = sha)
  
  httr2::request(url) |>
    httr2::req_headers(
      Authorization = paste("Bearer", pat),
      Accept = "application/vnd.github+json",
      `X-GitHub-Api-Version` = "2022-11-28"
    ) |>
    httr2::req_method("DELETE") |>
    httr2::req_body_json(body) |>
    httr2::req_perform()
}