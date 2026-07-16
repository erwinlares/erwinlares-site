# init-post.R
# Scaffolding helpers for erwinlares.com (the hub in the hub-and-spoke
# publishing system). Source this file (or load via .Rprofile) to make
# the functions available.
#
# Functions
#   init_post(slug, date = NULL, image = NULL, yaml_data = NULL, with_code = TRUE,
#             categories = NULL, publish_to = NULL, ...)
#     -> posts/YYYY-MM-DD-slug/index.qmd
#   set_thumbnail(slug, image = NULL, ...)
#     -> generate/regenerate a post's thumbnail after the fact
#
# This is an expansion of the original single-function init_post(),
# picking up scaffolding capabilities that were built out separately
# for the Capital Aikikai of Wisconsin (CAOW) spoke site: a `date`
# argument, image/thumbnail handling via magick, and a `with_code`
# switch so posts without embedded R output don't carry an unused
# `execute:` block. A few things were deliberately NOT ported over:
#
#   - No `section` argument / blog-vs-events split. erwinlares.com has
#     a single `posts/` directory, unlike CAOW's blog/ + events/. If
#     that changes, .find_post_dir() and the dir_path construction in
#     init_post() are the two places to generalize.
#   - No event-date/event-end fields, for the same reason -- there's no
#     event listing on this site to feed them to.
#   - No include-before-body / nav-partial wiring. CAOW's per-post nav
#     partial is a spoke-site concern; erwinlares.com's format block
#     just carries `css: styles.css` instead.
#   - No retract_post(). CAOW's retract_post() flips a post's local
#     `status:` field directly. This hub already has retract() in
#     R/retract.R, which does something different -- it clears the
#     post's row(s) from dispatch_log.csv across platforms. Adding a
#     second, differently-behaved "retract" here would be confusing;
#     unpublishing on this site goes through retract() instead.
#
# Notes on the date argument
#   `date` is the publication date and controls both the front-matter
#   `date:` field and the YYYY-MM-DD prefix on the post's directory. If
#   omitted, it defaults to today, matching the original behavior.
#
# Notes on categories / publish_to
#   Both are now arguments rather than hardcoded, but default to the
#   same full lists the original function always wrote -- the workflow
#   is still "scaffold, then trim what doesn't apply," just overridable
#   per call if you already know a post is e.g. aikido-only.
#
# Two ways to set a thumbnail
#   1. At scaffold time: init_post() takes an `image` argument pointing
#      at a photo that already exists somewhere on disk. It gets copied
#      into the new post directory, and a cropped/resized "-thumb"
#      derivative is generated and wired into the `image:` front-matter
#      field.
#   2. After the fact: if you scaffold the post first and drop a photo
#      into its folder by hand afterward, call set_thumbnail(slug) with
#      no `image` argument -- it looks inside the post's own folder for
#      a candidate photo and generates the thumbnail from whatever it
#      finds.
#   Either way, the original photo is never modified in place.


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

.resolve_slug <- function(slug) {
  is_code  <- grepl("^`.*`$", slug)
  is_words <- grepl(" ", slug) && !is_code
  
  if (is_code) {
    raw      <- gsub("^`|`$", "", slug)
    dir_slug <- gsub(" ", "-", raw)
    title    <- paste0("`", raw, "`")
    
  } else if (is_words) {
    dir_slug <- gsub(" ", "-", tolower(slug))
    title    <- tools::toTitleCase(slug)
    
  } else {
    dir_slug <- slug
    title    <- tools::toTitleCase(gsub("-", " ", slug))
  }
  
  list(dir_slug = dir_slug, title = title)
}

# Validates and normalizes a date argument to "YYYY-MM-DD".
# NULL falls back to today. Anything unparseable raises an informative error.
.resolve_date <- function(date, label = "date") {
  if (is.null(date)) {
    return(format(Sys.Date(), "%Y-%m-%d"))
  }
  
  parsed <- tryCatch(as.Date(date), error = function(e) NA)
  
  if (is.na(parsed)) {
    stop(
      "Invalid ", label, ": '", date, "'. ",
      "Expected a string R can parse as a date, e.g. '2026-03-14'.",
      call. = FALSE
    )
  }
  
  format(parsed, "%Y-%m-%d")
}

# Full pass-through of whatever's in the yaml file's `author` key --
# preserves affiliation/orcid/email (or any other fields present),
# unlike a name-only pluck. When no yaml_data is supplied, falls back
# to the site's full author scaffold.
.resolve_author <- function(yaml_data) {
  if (!is.null(yaml_data)) {
    yaml_path <- if (grepl("\\.ya?ml$", yaml_data)) yaml_data else paste0(yaml_data, ".yml")
    if (!file.exists(yaml_path)) {
      stop("yaml_data file not found: ", yaml_path, call. = FALSE)
    }
    author_data <- yaml::read_yaml(yaml_path)
    if (is.null(author_data$author)) {
      stop("yaml_data file must contain an 'author' key.", call. = FALSE)
    }
    yaml::as.yaml(list(author = author_data$author))
  } else {
    paste0(
      "author:\n",
      "  - name: \"\"\n",
      "    affiliation: \"\"\n",
      "    orcid: \"\"\n",
      "    email: \"\"\n"
    )
  }
}

# Finds a post's directory under posts/, fuzzy-matching against the
# <date>-<slug> naming convention. Used by set_thumbnail().
.find_post_dir <- function(slug) {
  dir_slug <- .resolve_slug(slug)$dir_slug
  
  candidates <- list.dirs("posts", full.names = TRUE, recursive = FALSE)
  matches <- candidates[grepl(paste0("-", dir_slug, "$"), basename(candidates))]
  
  if (length(matches) == 0) {
    stop("No post found matching slug '", slug, "' in posts/.", call. = FALSE)
  }
  if (length(matches) > 1) {
    stop(
      "Slug '", slug, "' matches more than one post:\n",
      paste0("  - ", basename(matches), collapse = "\n"),
      "\nBe more specific.", call. = FALSE
    )
  }
  
  matches[1]
}

# Replaces the first line matching `key_pattern` in a post's front
# matter with `new_line`. Returns TRUE if a matching line was found and
# replaced, FALSE otherwise -- callers decide whether that's an error.
.replace_front_matter_line <- function(post_path, key_pattern, new_line) {
  lines <- readLines(post_path)
  line_idx <- grep(key_pattern, lines)
  
  if (length(line_idx) == 0) {
    return(FALSE)
  }
  
  lines[line_idx[1]] <- new_line
  writeLines(lines, post_path)
  TRUE
}

# Generates a resized, center-cropped "-thumb" derivative of
# `source_path` inside `dest_dir`. Does NOT touch or copy the original.
# Returns the thumbnail's filename (not a full path) -- what belongs in
# the front-matter `image:` field.
.generate_thumbnail <- function(source_path, dest_dir, thumb_width = 1000, thumb_height = 750,
                                mode = c("cover", "contain"), bg_color = "white") {
  mode <- match.arg(mode)
  
  if (!requireNamespace("magick", quietly = TRUE)) {
    stop(
      "The magick package is required for thumbnail generation. ",
      "Install it with install.packages(\"magick\").",
      call. = FALSE
    )
  }
  if (!file.exists(source_path)) {
    stop("Image not found: ", source_path, call. = FALSE)
  }
  
  img <- magick::image_read(source_path)
  
  if (mode == "cover") {
    # "widthxheight^" resizes so the image *covers* the target box,
    # preserving aspect ratio and overflowing on one dimension; the
    # subsequent center crop trims that overflow. Right for
    # photographs, where losing a sliver off an edge is harmless.
    img <- magick::image_resize(img, paste0(thumb_width, "x", thumb_height, "^"))
    img <- magick::image_crop(img, paste0(thumb_width, "x", thumb_height), gravity = "center")
  } else {
    # "widthxheight" (no modifier) resizes so the image *fits within*
    # the target box -- nothing cropped -- and image_extent() pads
    # out to the exact canvas size. Right for flyers/posters, where
    # a crop-to-fill would otherwise cut off text.
    img <- magick::image_resize(img, paste0(thumb_width, "x", thumb_height))
    img <- magick::image_extent(img, paste0(thumb_width, "x", thumb_height),
                                gravity = "center", color = bg_color)
  }
  
  base_name  <- tools::file_path_sans_ext(basename(source_path))
  ext        <- tools::file_ext(source_path)
  thumb_name <- paste0(base_name, "-thumb.", ext)
  thumb_path <- file.path(dest_dir, thumb_name)
  
  magick::image_write(img, thumb_path)
  thumb_name
}

# Builds the YAML front matter + trailing blank line for a new post.
# `with_code` controls whether the format block carries toc/
# number-sections plus a matching execute: block, or stays minimal.
.build_template <- function(title, author_block, date, image, category_lines,
                            publish_to_lines, with_code) {
  format_block <- if (with_code) {
    paste0(
      "format:\n",
      "  html:\n",
      "    toc: true\n",
      "    toc-depth: 3\n",
      "    toc-title: Contents\n",
      "    number-sections: true\n",
      "    embed-resources: false\n",
      "    css: styles.css\n",
      "execute:\n",
      "  include: true\n",
      "  echo: true\n",
      "  message: false\n",
      "  error: false\n"
    )
  } else {
    paste0(
      "format:\n",
      "  html:\n",
      "    css: styles.css\n"
    )
  }
  
  paste0(
    "---\n",
    'title: "', title, '"\n',
    'subtitle: ""\n',
    'description: "One or two sentences."\n',
    'abstract: ""\n',
    'image: "', image, '"\n',
    author_block,
    "date: ", date, "\n",
    "date-modified: last-modified\n",
    "categories:\n",
    category_lines, "\n",
    "status: draft\n",
    "publish_to:\n",
    publish_to_lines, "\n",
    format_block,
    "---\n",
    "\n"
  )
}


# ---------------------------------------------------------------------------
# Public functions
# ---------------------------------------------------------------------------

#' Scaffold a new post
#'
#' Creates posts/YYYY-MM-DD-<slug>/index.qmd with front matter matching
#' erwinlares.com's hub-and-spoke publishing conventions (categories,
#' status, publish_to). Optionally attaches a photo, generating a
#' cropped/resized thumbnail alongside the original.
#'
#' @param slug  Post identifier. Accepts three forms:
#'   - "word-slug"         -> dir: word-slug,       title: Word Slug
#'   - "natural language"  -> dir: natural-language, title: Natural Language
#'   - "`code term`"       -> dir: code-term,        title: `code term`
#' @param date  Publication date, e.g. "2026-03-14". Defaults to today.
#'   Also sets the YYYY-MM-DD prefix on the post's directory.
#' @param image  Optional path to a source photo that already exists
#'   somewhere on disk. Copied untouched into the post directory; a
#'   cropped/resized "-thumb" derivative is generated alongside it and
#'   used as the `image:` front-matter field. If you'd rather scaffold
#'   the post first and drop a photo in afterward, leave this NULL and
#'   call set_thumbnail() once the photo is in place.
#' @param yaml_data  Optional path to a .yml file containing an `author`
#'   key. All fields present (name, affiliation, orcid, email, ...) are
#'   passed through as-is.
#' @param with_code  If TRUE (default, matches prior behavior), the
#'   format block includes toc/number-sections and a matching
#'   `execute:` block, for posts that embed R output. If FALSE, writes
#'   a minimal format block (just `css: styles.css`) and no `execute:`
#'   block.
#' @param categories  Character vector written to the front-matter
#'   `categories:` field. Defaults to the site's full canonical tag
#'   list -- trim to what's relevant to this post.
#' @param publish_to  Character vector written to the front-matter
#'   `publish_to:` field, controlling which spokes this post dispatches
#'   to. Defaults to all configured spokes -- trim to the platforms
#'   this post is actually relevant to.
#' @param thumb_width,thumb_height  Target thumbnail dimensions, in
#'   pixels. Default 1000x750 (4:3).
#' @param thumb_mode  "cover" (default) crops the image to fill the
#'   canvas -- right for photographs, where losing a sliver off an edge
#'   is harmless. "contain" shrinks the whole image to fit within the
#'   canvas with nothing cropped, padding the rest -- right for flyers
#'   and posters, where a crop-to-fill would otherwise cut off text.
#' @param bg_color  Padding color used in "contain" mode. Default
#'   "white". Only matters when thumb_mode = "contain".
#'
#' @return Invisibly, the path to the newly created index.qmd.
#'
#' @seealso set_thumbnail() for attaching a photo after the post has
#'   already been scaffolded; retract() in R/retract.R for unpublishing.
#'
#' @examples
#' init_post("First Trip to Japan")
#' init_post("summer-gasshuku-recap", date = "2025-08-02", image = "~/Photos/mat-work.jpg")
#' init_post("quick-note", with_code = FALSE, categories = c("personal"))
#' init_post("dojo-attendance-2026", publish_to = c("erwinlares", "caow"))
init_post <- function(slug, date = NULL, image = NULL, yaml_data = NULL, with_code = TRUE,
                      categories = NULL, publish_to = NULL,
                      thumb_width = 1000, thumb_height = 750,
                      thumb_mode = "cover", bg_color = "white") {
  
  default_categories <- c(
    "data-science", "r", "linguistics", "pottery", "aikido",
    "brug", "personal", "reproducibility", "productivity", "coding"
  )
  default_publish_to <- c(
    "erwinlares", "lasrubieraspottery", "caow", "researchci", "brug"
  )
  if (is.null(categories)) categories <- default_categories
  if (is.null(publish_to)) publish_to <- default_publish_to
  
  parsed   <- .resolve_slug(slug)
  dir_slug <- parsed$dir_slug
  title    <- parsed$title
  date     <- .resolve_date(date, "date")
  
  if (!is.null(image) && !file.exists(image)) {
    stop("image not found: ", image, call. = FALSE)
  }
  
  dir_path     <- file.path("posts", paste0(date, "-", dir_slug))
  post_path    <- file.path(dir_path, "index.qmd")
  author_block <- .resolve_author(yaml_data)
  
  if (dir.exists(dir_path)) {
    stop("Directory already exists: ", dir_path, call. = FALSE)
  }
  
  dir.create(dir_path, recursive = TRUE)
  
  image_field <- ""
  if (!is.null(image)) {
    dest_original <- file.path(dir_path, basename(image))
    file.copy(image, dest_original, overwrite = FALSE)
    image_field <- .generate_thumbnail(dest_original, dir_path, thumb_width, thumb_height,
                                       mode = thumb_mode, bg_color = bg_color)
  }
  
  category_lines   <- paste0("  - ", categories, collapse = "\n")
  publish_to_lines <- paste0("  - ", publish_to, collapse = "\n")
  
  template <- .build_template(title, author_block, date, image_field,
                              category_lines, publish_to_lines, with_code)
  
  writeLines(template, post_path)
  rstudioapi::navigateToFile(post_path)
  
  message("Created: ", post_path)
  if (!is.null(image)) {
    message("  + copied original: ", basename(image))
    message("  + generated thumbnail: ", image_field)
  }
  invisible(post_path)
}


#' Set or regenerate a post's thumbnail
#'
#' Handles the workflow where a post already exists -- scaffolded by
#' init_post() -- and a photo gets dropped into its folder by hand
#' afterward, rather than being handed to init_post() up front.
#' Generates a cropped/resized "-thumb" derivative and writes it into
#' the post's front-matter `image:` field. Safe to re-run: each call
#' regenerates the thumbnail from the original.
#'
#' @param slug  The post's slug, matched fuzzily against the
#'   <date>-<slug> directory name.
#' @param image  Optional path to a source photo. If omitted,
#'   set_thumbnail() looks inside the post's own directory for a
#'   candidate: if exactly one non-thumbnail image file is found, it's
#'   used automatically; if none or more than one are found, you'll
#'   need to pass image explicitly to disambiguate.
#' @param thumb_width,thumb_height  Target thumbnail dimensions, in
#'   pixels. Default 1000x750 (4:3), matching init_post().
#' @param thumb_mode  "cover" (default) crops the image to fill the
#'   canvas. "contain" shrinks the whole image to fit within the canvas
#'   with nothing cropped, padding the rest.
#' @param bg_color  Padding color used in "contain" mode. Default
#'   "white". Only matters when thumb_mode = "contain".
#'
#' @return Invisibly, the generated thumbnail's filename.
#'
#' @seealso init_post(), which can also set a thumbnail at scaffold time.
#'
#' @examples
#' # Photo already sitting in the post's own folder:
#' set_thumbnail("summer-gasshuku-recap")
#'
#' # A flyer, where cropping would cut off text:
#' set_thumbnail("grand-opening-seminar", thumb_mode = "contain")
set_thumbnail <- function(slug, image = NULL, thumb_width = 1000, thumb_height = 750,
                          thumb_mode = "cover", bg_color = "white") {
  dir_path  <- .find_post_dir(slug)
  post_path <- file.path(dir_path, "index.qmd")
  
  if (!file.exists(post_path)) {
    stop("Expected index.qmd not found in ", dir_path, call. = FALSE)
  }
  
  if (!is.null(image)) {
    # Source lives elsewhere -- copy it in, same as init_post().
    if (!file.exists(image)) {
      stop("image not found: ", image, call. = FALSE)
    }
    source_path <- file.path(dir_path, basename(image))
    if (!file.exists(source_path)) {
      file.copy(image, source_path, overwrite = FALSE)
    }
    
  } else {
    # No path given -- look for a photo already dropped into the
    # post's own folder by hand. Exclude existing "-thumb" files so
    # re-running this on a post that already has a thumbnail
    # doesn't pick up its own derivative as a second candidate.
    thumb_pattern <- "-thumb\\.[a-zA-Z0-9]+$"
    image_pattern <- "\\.(jpe?g|png|webp|gif|tiff?)$"
    
    candidates <- list.files(dir_path, pattern = image_pattern,
                             ignore.case = TRUE, full.names = TRUE)
    candidates <- candidates[!grepl(thumb_pattern, candidates, ignore.case = TRUE)]
    
    if (length(candidates) == 0) {
      stop(
        "No image found in ", dir_path, ". ",
        "Drop a photo into the post's folder, or pass image = \"path/to/photo.jpg\".",
        call. = FALSE
      )
    }
    if (length(candidates) > 1) {
      stop(
        "More than one candidate image found in ", dir_path, ":\n",
        paste0("  - ", basename(candidates), collapse = "\n"),
        "\nPass image = \"...\" to specify which one.", call. = FALSE
      )
    }
    
    source_path <- candidates[1]
  }
  
  thumb_name <- .generate_thumbnail(source_path, dir_path, thumb_width, thumb_height,
                                    mode = thumb_mode, bg_color = bg_color)
  
  found <- .replace_front_matter_line(
    post_path,
    key_pattern = "^image:\\s*",
    new_line    = paste0('image: "', thumb_name, '"')
  )
  
  if (!found) {
    stop("No 'image:' field found in ", post_path, ". Front matter may be malformed.", call. = FALSE)
  }
  
  message("Thumbnail set: ", thumb_name)
  invisible(thumb_name)
}