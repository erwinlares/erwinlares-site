# ============================================================
# publish.R — dispatch layer for erwinlares.com
#
# Usage: publish()
#
# Platforms:
#   erwinlares         → git add/commit/push (local repo → Netlify)
#   brug               → GitHub Contents API → the-burrows
#   lasrubieraspottery → [STUB] Shopify API
#   aikidoofwisconsin  → [STUB] Squarespace API
#   researchci         → [STUB] WordPress REST API
#
# Credentials in .Renviron:
#   GITHUB_PAT_BRUG    (for the-burrows repo only)
# ============================================================

# --- Utilities -----------------------------------------------

read_front_matter <- function(path) {
  lines <- readLines(path, warn = FALSE)
  delimiters <- which(trimws(lines) == "---")
  if (length(delimiters) < 2) {
    return(list())
  }
  yaml_text <- paste(
    lines[(delimiters[1] + 1):(delimiters[2] - 1)],
    collapse = "\n"
  )
  yaml::yaml.load(yaml_text)
}

load_dispatch_log <- function() {
  log_path <- "dispatch_log.csv"
  if (file.exists(log_path)) {
    log <- read.csv(log_path, stringsAsFactors = FALSE)
    # Back-compat: older logs predate the section column
    if (!"section" %in% names(log)) {
      log$section <- NA_character_
    }
    log
  } else {
    data.frame(
      post_path = character(),
      platform = character(),
      section = character(),
      dispatched_at = character(),
      status = character(),
      message = character(),
      stringsAsFactors = FALSE
    )
  }
}

log_dispatch <- function(
  post_path,
  platform,
  section = NA_character_,
  status = "success",
  msg = ""
) {
  entry <- data.frame(
    post_path = post_path,
    platform = platform,
    section = section,
    dispatched_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    status = status,
    message = msg,
    stringsAsFactors = FALSE
  )
  log <- load_dispatch_log()
  write.csv(rbind(log, entry), "dispatch_log.csv", row.names = FALSE)
}

already_dispatched <- function(log, post_path, platform) {
  nrow(log[
    log$post_path == post_path &
      log$platform == platform &
      log$status == "success",
  ]) >
    0
}

# Looks up the section a post most recently landed in for a given platform.
# Returns NA if there's no successful log entry (e.g. log predates the
# section column, or this post/platform pair was never dispatched).
get_dispatched_section <- function(log, post_path, platform) {
  matches <- log[
    log$post_path == post_path &
      log$platform == platform &
      log$status == "success",
  ]
  if (nrow(matches) == 0) {
    return(NA_character_)
  }
  matches$section[nrow(matches)] # most recent match
}


# --- Hub dispatch: erwinlares.com ----------------------------
#
# Uses existing git credentials — no PAT needed since we are
# already inside the erwinlares-site repo.
#
# Idempotent: if the post is already committed and unchanged,
# git add stages nothing and we return success without
# committing. This handles posts that were manually pushed
# before publish() was in use.

dispatch_erwinlares <- function(post_path, front_matter) {
  post_dir <- dirname(post_path)
  gert::git_add(post_dir)

  staged <- gert::git_status()
  if (nrow(staged[staged$staged, ]) == 0) {
    message("erwinlares: already in repo, nothing to commit.")
    return(invisible(TRUE))
  }

  gert::git_commit(paste0("publish: ", front_matter$title))
  gert::git_push(verbose = FALSE)

  message("\u2713 Dispatched to erwinlares.com: ", front_matter$title)
  invisible(TRUE)
}


# --- Spoke dispatchers: stubs --------------------------------

dispatch_shopify <- function(post_path, front_matter) {
  message("[STUB] Shopify dispatch not yet implemented: ", front_matter$title)
  invisible(NULL)
}

dispatch_squarespace <- function(post_path, front_matter) {
  message(
    "[STUB] Squarespace dispatch not yet implemented: ",
    front_matter$title
  )
  invisible(NULL)
}

dispatch_wordpress <- function(post_path, front_matter) {
  message("[STUB] WordPress dispatch not yet implemented: ", front_matter$title)
  invisible(NULL)
}


# --- Main orchestration --------------------------------------

publish <- function() {
  # Find all nested post index files, excluding posts/index.qmd
  post_files <- list.files(
    "posts",
    pattern = "index\\.qmd$",
    recursive = TRUE,
    full.names = TRUE
  )
  post_files <- post_files[grepl("posts/[^/]+/index\\.qmd$", post_files)]

  if (length(post_files) == 0) {
    message("No posts found.")
    return(invisible(NULL))
  }

  # Parse front matter; keep only published posts
  posts <- lapply(post_files, function(f) {
    fm <- read_front_matter(f)
    fm$path <- f
    fm
  })
  posts <- Filter(function(p) identical(p$status, "published"), posts)

  if (length(posts) == 0) {
    message("No published posts to dispatch.")
    return(invisible(NULL))
  }

  log <- load_dispatch_log()

  for (post in posts) {
    if (is.null(post$publish_to)) {
      next
    }

    for (platform in post$publish_to) {
      if (already_dispatched(log, post$path, platform)) {
        message("Already dispatched: ", post$title, " \u2192 ", platform)
        next
      }

      tryCatch(
        {
          result <- switch(
            platform,
            erwinlares = dispatch_erwinlares(post$path, post),
            brug = dispatch_brug(post$path, post),
            lasrubieraspottery = dispatch_shopify(post$path, post),
            aikidoofwisconsin = dispatch_squarespace(post$path, post),
            researchci = dispatch_wordpress(post$path, post),
            message("Unknown platform: ", platform)
          )
          # dispatch_brug() returns the section it routed to; other
          # dispatchers don't have a section concept and return TRUE/NULL,
          # which is not a string, so section stays NA for them.
          section <- if (is.character(result)) result else NA_character_
          log_dispatch(post$path, platform, section, "success")
        },
        error = function(e) {
          log_dispatch(
            post$path,
            platform,
            NA_character_,
            "error",
            conditionMessage(e)
          )
          message(
            "\u2717 Failed: ",
            post$title,
            " \u2192 ",
            platform,
            "\n  ",
            conditionMessage(e)
          )
        }
      )
    }
  }

  invisible(NULL)
}
