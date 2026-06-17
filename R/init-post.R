init_post <- function(slug, yaml_data = NULL) {
  
  # Detect input style and derive directory slug + YAML title accordingly
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
  
  # Build paths
  date      <- format(Sys.Date(), "%Y-%m-%d")
  dir_path  <- file.path("posts", paste0(date, "-", dir_slug))
  post_path <- file.path(dir_path, "index.qmd")
  
  # Stop if directory already exists
  if (dir.exists(dir_path)) {
    stop("Directory already exists: ", dir_path, call. = FALSE)
  }
  
  # Resolve author block
  if (!is.null(yaml_data)) {
    yaml_path <- if (grepl("\\.ya?ml$", yaml_data)) yaml_data else paste0(yaml_data, ".yml")
    if (!file.exists(yaml_path)) {
      stop("yaml_data file not found: ", yaml_path, call. = FALSE)
    }
    author_data <- yaml::read_yaml(yaml_path)
    if (is.null(author_data$author)) {
      stop("yaml_data file must contain an 'author' key.", call. = FALSE)
    }
    author_block <- yaml::as.yaml(list(author = author_data$author))
  } else {
    author_block <- paste0(
      "author:\n",
      "  - name: \"\"\n",
      "    affiliation: \"\"\n",
      "    orcid: \"\"\n",
      "    email: \"\"\n"
    )
  }
  
  # Create directory
  dir.create(dir_path, recursive = TRUE)
  
  # Build YAML template
  template <- paste0(
    "---\n",
    'title: "', title, '"\n',
    'subtitle: ""\n',
    'description: "One or two sentences."\n',
    'abstract: ""\n',
    author_block,
    "date: ", date, "\n",
    "date-modified: last-modified\n",
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
    "  error: false\n",
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