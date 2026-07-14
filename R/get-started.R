# get_started.R
# Prints a concise workflow reference for common site tasks.
# Sourced automatically via .Rprofile when the project is opened.

get_started <- function() {
  cat(
    "
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

RETRACT A POST
  Use when a post landed in the wrong place, needs pulling from a
  spoke, or needs pulling off erwinlares.com entirely.
     retract(
       post_path = \"posts/your-post-slug/index.qmd\",
       platform  = \"brug\"
     )
  platform is one of: erwinlares, brug, caow, lasrubieraspottery,
  researchci (the last two are stubs for now).
  Call it once per platform if a post needs pulling from more than
  one place.
  Clears the matching dispatch_log.csv row, so the next publish()
  redispatches the post (e.g. to the right section) if it's still
  listed in publish_to.

  Platform-specific functions (retract_erwinlares(), retract_gh(),
  etc.) can be called directly, but skip the dispatch_log.csv
  clearing that retract() handles for you — prefer retract()
  unless you have a specific reason not to.

  retract_gh() (called for platform = \"brug\" or \"caow\") looks up
  section automatically from dispatch_log.csv, and reads the right
  credential from platform too (GITHUB_PAT_BRUG / GITHUB_PAT_CAOW).
  Pass section explicitly only for posts dispatched before the log
  tracked it:
     retract_gh(post_path, owner = \"erwinlares\", repo = \"the-burrows\",
                section = \"blog\", platform = \"brug\")

STRUCTURAL CHANGES (layout, CSS, _quarto.yml, new pages)
  1. Edit the relevant files
  2. git add . && git commit -m \"describe change\" && git push
  ⚠  pre-commit hook checks any staged posts/*/index.qmd for
     \"erwinlares\" in publish_to before allowing the commit —
     install once per clone: git config core.hooksPath .githooks

TAGS WITH SPECIAL BEHAVIOR
  journal                → appears in \"From the Journal\" on About
  announcement, journal  → on brug, routes to blog/ instead of
                           the default resources/

DISPATCH STATUS
  erwinlares   ✔ live    (git push → Netlify)
  brug         ✔ live    (GitHub Contents API)
  caow         ✔ live    (GitHub Contents API)
  shopify      ○ stub
  wordpress    ○ stub    (waiting on work migration)

=======================================================
"
  )
}