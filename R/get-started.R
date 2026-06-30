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
  ⚠  Any YAML change (including status: published) invalidates
     the freeze cache — re-render before publishing:
     quarto render posts/your-post-slug/index.qmd
     then commit the updated _freeze files
  5. publish()

EDIT AN EXISTING POST
  1. Edit the .qmd file directly
  2. If you changed the YAML front matter, re-render first:
     quarto render posts/your-post-slug/index.qmd
     then commit the updated _freeze files
  3. publish()

RETRACT A POST (GitHub-backed platforms only — currently: brug)
  Use when a post landed in the wrong place, or needs pulling.
     retract_gh(
       post_path = \"posts/your-post-slug/index.qmd\",
       owner     = \"erwinlares\",
       repo      = \"the-burrows\"
     )
  section is looked up automatically from dispatch_log.csv.
  Pass section explicitly only for posts dispatched before the
  log tracked it: section = \"blog\" or section = \"resources\"
  Clears the matching dispatch_log.csv row, so the next
  publish() redispatches the post (e.g. to the right section).

STRUCTURAL CHANGES (layout, CSS, _quarto.yml, new pages)
  1. Edit the relevant files
  2. git add . && git commit -m \"describe change\" && git push

TAGS WITH SPECIAL BEHAVIOR
  journal                → appears in \"From the Journal\" on About
  announcement, journal  → on brug, routes to blog/ instead of
                           the default resources/

DISPATCH STATUS
  erwinlares   ✔ live    (git push → Netlify)
  brug         ✔ live    (GitHub Contents API)
  shopify      ○ stub
  wordpress    ○ stub    (waiting on work migration)
  squarespace  ✗ ruled out (commerce-only API)

=======================================================
")
}