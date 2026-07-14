#' Retract a post from a publishing platform
#'
#' Removes a previously-dispatched post from the given platform and clears
#' its corresponding row from \code{dispatch_log.csv}, so a subsequent
#' \code{\link{publish}()} call treats the post as un-dispatched and will
#' redispatch it if it's still marked \code{publish_to} that platform.
#'
#' \code{retract()} is the retraction counterpart to \code{\link{publish}()}:
#' where \code{publish()} routes each post to a \code{dispatch_*()} function
#' per platform, \code{retract()} routes to a matching \code{retract_*()}
#' function. Log-row clearing lives here rather than in the individual
#' retract functions, so every platform gets it uniformly.
#'
#' @param post_path Path to the post's \code{index.qmd}, e.g.
#'   \code{"posts/2026-07-01-my-post/index.qmd"}. Used to locate the post's
#'   directory and to match the correct row in \code{dispatch_log.csv}.
#' @param platform Character string naming the platform to retract from.
#'   One of \code{"erwinlares"}, \code{"brug"}, \code{"caow"},
#'   \code{"lasrubieraspottery"}, or \code{"researchci"}.
#'
#' @return Invisibly, the return value of the underlying \code{retract_*()}
#'   call (typically \code{TRUE} on success).
#'
#' @details
#' \code{platform = "brug"} and \code{platform = "caow"} both call
#' \code{\link{retract_gh}()}, with \code{owner}/\code{repo} hardcoded per
#' platform (\code{erwinlares/the-burrows} and \code{erwinlares/caow-website}
#' respectively) — these are currently the only two GitHub-backed spokes.
#' \code{retract_gh()} derives which credential to use from \code{platform}
#' itself (\code{GITHUB_PAT_BRUG}, \code{GITHUB_PAT_CAOW}), so adding a
#' third GitHub-backed spoke later only needs a new \code{switch()} branch
#' here plus the matching PAT in \code{.Renviron} — nothing in
#' \code{retract_gh()} itself. The stub platforms (\code{lasrubieraspottery},
#' \code{researchci}) currently just message that retraction isn't
#' implemented yet, mirroring the \code{dispatch_*()} stubs in
#' \code{publish.R}.
#'
#' @seealso \code{\link{publish}}, \code{\link{retract_gh}},
#'   \code{\link{retract_erwinlares}}
#'
#' @examples
#' \dontrun{
#' retract("posts/2026-06-16-less-maintenance-more-science/index.qmd", "brug")
#' retract("posts/2026-07-01-buildout-week-1/index.qmd", "caow")
#' }
#'
#' @export
retract <- function(post_path, platform) {
  result <- switch(
    platform,
    erwinlares = retract_erwinlares(post_path),
    brug = retract_gh(
      post_path,
      owner = "erwinlares",
      repo = "the-burrows",
      platform = platform
    ),
    caow = retract_gh(
      post_path,
      owner = "erwinlares",
      repo = "caow-website",
      platform = platform
    ),
    lasrubieraspottery = retract_shopify(post_path),
    researchci = retract_wordpress(post_path),
    stop("Unknown platform: ", platform, call. = FALSE)
  )
  
  log <- load_dispatch_log()
  log <- log[!(log$post_path == post_path & log$platform == platform), ]
  write.csv(log, "dispatch_log.csv", row.names = FALSE)
  
  invisible(result)
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
#               platform entry. Only needed explicitly for posts dispatched
#               before the section column existed in the log.
# platform:     which platform's log entry to consult when section is
#               omitted, AND which credential to use — the PAT is read
#               from Sys.getenv(paste0("GITHUB_PAT_", toupper(platform))),
#               so "brug" reads GITHUB_PAT_BRUG and "caow" reads
#               GITHUB_PAT_CAOW. Defaults to "brug" for backward
#               compatibility when calling this directly, but retract()
#               always passes it explicitly.
#
# Also clears the matching dispatch_log.csv row for this post/platform so
# a subsequent publish() will redispatch rather than skipping it as
# already-dispatched.
retract_gh <- function(
    post_path,
    owner,
    repo,
    section = NULL,
    platform = "brug"
) {
  pat_env_var <- paste0("GITHUB_PAT_", toupper(platform))
  pat <- Sys.getenv(pat_env_var)
  if (nchar(pat) == 0) {
    stop(pat_env_var, " not set in .Renviron", call. = FALSE)
  }
  
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
  commit_msg <- paste0("retract: ", post_dir_name)
  
  source_files <- list.files(dirname(post_path), full.names = TRUE)
  
  for (f in source_files) {
    api_path <- paste0(section, "/", post_dir_name, "/", basename(f))
    github_delete_file(owner, repo, api_path, commit_msg, pat)
  }
  
  # Clear the log row so publish() treats this post as un-dispatched
  log <- log[!(log$post_path == post_path & log$platform == platform), ]
  write.csv(log, "dispatch_log.csv", row.names = FALSE)
  
  message(
    "✓ Retracted (",
    owner,
    "/",
    repo,
    ", ",
    section,
    "): ",
    post_dir_name
  )
  invisible(TRUE)
}