init_post <- function(slug) {
  
  # Detect input style and derive directory slug + YAML title accordingly
  is_code  <- grepl("^`.*`$", slug)
  is_words <- grepl(" ", slug) && !is_code
  
  if (is_code) {
    # "`git push origin me`" → dir: git-push-origin-me, title: `git push origin me`
    raw      <- gsub("^`|`$", "", slug)
    dir_slug <- gsub(" ", "-", raw)
    title    <- paste0("`", raw, "`")
    
  } else if (is_words) {
    # "title of the post" → dir: title-of-the-post, title: Title of the Post
    dir_slug <- gsub(" ", "-", tolower(slug))
    title    <- tools::toTitleCase(slug)
    
  } else {
    # "title-of-the-post" → dir: title-of-the-post, title: Title of the Post
    dir_slug <- slug
    title    <- tools::toTitleCase(gsub("-", " ", slug))
  }
  
  # Build paths
  date      <- format(Sys.Date(), "%Y-%m-%d")
  dir_path  <- file.path("posts", paste0(date, "-", dir_slug))
  post_path <- file.path(dir_path, "index.qmd")
  
  # Stop if directory already exists
  if (dir.exists(dir_path)) {
    stop("Directory already exists: ", dir_path, call. = FALSE)
  }
  
  # Create directory
  dir.create(dir_path, recursive = TRUE)
  
  # Build YAML template
  template <- paste0(
    "---\n",
    'title: "', title, '"\n',
    "date: ", date, "\n",
    'description: "One or two sentences."\n',
    "categories:\n",
    "  - data-science\n",
    "  - r\n",
    "  - linguistics\n",
    "  - pottery\n",
    "  - aikido\n",
    "  - brug\n",
    "  - personal\n",
    "  - reproducibility\n",
    "  - productivity\n",
    "  - coding\n",
    "status: draft\n",
    "publish_to:\n",
    "  - erwinlares\n",
    "  - lasrubieraspottery\n",
    "  - aikidoofwisconsin\n",
    "  - researchci\n",
    "  - brug\n",
    "---\n",
    "\n"
  )
  
  # Write index.qmd
  writeLines(template, post_path)
  
  # Open in RStudio editor
  rstudioapi::navigateToFile(post_path)
  
  message("Created: ", post_path)
  invisible(post_path)
}