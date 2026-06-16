# get_started.R
# Prints a concise workflow reference for common site tasks.
# Sourced automatically via .Rprofile when the project is opened.

get_started <- function() {
  cat("
=======================================================
  erwinlares-site — quick reference
=======================================================

NEW POST
  1. init_post(\"your-post-slug\")
  2. Write the post
  3. Set status: published in YAML front matter
  4. Confirm publish_to list
  5. publish()

EDIT AN EXISTING POST
  1. Edit the .qmd file directly
  2. publish()

STRUCTURAL CHANGES (layout, CSS, _quarto.yml, new pages)
  1. Edit the relevant files
  2. git add . && git commit -m \"describe change\" && git push

TAGS WITH SPECIAL BEHAVIOR
  journal   → appears in \"From the Journal\" on the About page

DISPATCH STATUS
  erwinlares   ✔ live    (git push → Netlify)
  brug         ✔ live    (GitHub Contents API)
  shopify      ○ stub
  wordpress    ○ stub    (waiting on work migration)
  squarespace  ✗ ruled out (commerce-only API)

=======================================================
")
}