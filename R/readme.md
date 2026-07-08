# erwinlares-site

This repo holds the Quarto source for [erwinlares.com](https://erwinlares.com), along with a small set of R helper functions I've written to publish and retract posts across the handful of places my writing ends up living. This README is the map to those helpers — what each one does, when to reach for it, and the handful of gotchas I've learned the hard way.

## The shape of the system

I think of this site as a hub, with a few spokes hanging off it. erwinlares.com is the canonical source: every post starts here, and everything else — [The Burrows](https://github.com/erwinlares/the-burrows) (the BRUG community site), lasrubieraspottery.com, aikidoofwisconsin.com, researchci.doit.wisc.edu — is a spoke that a post may or may not get pushed out to, depending on what I put in its front matter. `publish_to` in a post's YAML is the switch that decides which spokes a given post reaches; nothing gets pushed anywhere I haven't explicitly listed.

That hub-and-spoke framing matters because it shapes how the helper functions are organized. There's one function that dispatches a post outward per platform, and — as of the `retract()` work — a mirror-image function that pulls a post back per platform. Keeping those two operations symmetric, rather than letting retraction become an afterthought bolted onto a couple of platforms, is a design choice I've tried to hold onto as this has grown.

None of this lives inside an R package, by the way — no `DESCRIPTION`, no `NAMESPACE`, nothing you'd `devtools::install()`. These are just sourced helper scripts living in `R/`, meant to be run from an R console with the project open.

## Before you start: credentials

The only credential these functions need is a GitHub personal access token, stored in `.Renviron` as `GITHUB_PAT_BRUG`, scoped to Contents: Read and Write on `erwinlares/the-burrows`. It's never written to a post file or committed anywhere — `Sys.getenv()` reads it at call time, and every function that needs it checks for its presence up front and fails loudly if it's missing, rather than failing halfway through a dispatch with a partial set of files pushed.

Pushing to erwinlares.com itself doesn't need a PAT at all — that goes through your existing local git credentials via `gert`, the same way you'd `git push` from the command line.

## The files

### `R/publish.R` — the dispatch layer

This is the orchestrator. `publish()` walks every post under `posts/`, keeps only the ones marked `status: published`, and for each one loops over whatever platforms are listed in its `publish_to` field, calling the matching `dispatch_*()` function:

- `dispatch_erwinlares()` — commits and pushes the post to this repo, which is what actually gets it live on erwinlares.com once Netlify rebuilds. Idempotent: if the post's already committed and nothing's changed, it says so and moves on rather than creating an empty commit.
- `dispatch_brug()` — pushes the post to The Burrows via the GitHub Contents API, no local clone required. It routes to `resources/` by default, unless the post's `categories` field contains `"announcement"` or `"journal"`, in which case it lands in `blog/` instead.
- `dispatch_shopify()`, `dispatch_squarespace()`, `dispatch_wordpress()` — stubs. Shopify's API is commerce-only with no content-posting endpoint, so that one's more or less permanently a stub. WordPress is waiting on a separate migration. Squarespace is being replaced outright by the aikidoofwisconsin.com rebuild, so I don't expect that stub to ever grow into something real either.

`publish.R` also owns `dispatch_log.csv`, which tracks, per post and per platform, whether dispatch succeeded, when, and which `section` it landed in (that last part matters for `dispatch_brug()`'s `blog/` vs. `resources/` split). `already_dispatched()` checks this log before dispatching, so re-running `publish()` is safe — it skips anything already sent rather than duplicating it.

### `R/dispatch-brug.R` — GitHub Contents API mechanics

This is where the GitHub-specific plumbing behind `dispatch_brug()` lives: `github_get_sha()` (fetches a file's current SHA, needed for any update via the Contents API), `github_put_file()` (creates or updates a single file), and a couple of front-matter cleanup functions — `strip_front_matter_brug()` strips a post's YAML down to what BRUG actually needs, and forces `engine: markdown` so BRUG's GitHub Actions CI never tries to execute R (BRUG posts render as static syntax-highlighted code blocks, which is deliberate: BRUG's CI has no R installed, so nothing there can depend on live execution).

### `R/retract.R` — pulling a post back

This is the newer half of the system, and it's meant to read as `publish.R`'s mirror image. `retract(post_path, platform)` is the entry point — pass it a post's path and a platform name, and it routes to the matching `retract_*()` function, then clears that post's row from `dispatch_log.csv` so a future `publish()` treats it as un-dispatched and will send it again if it's still listed in `publish_to`.

- `retract_erwinlares()` — the git-based retraction from the hub itself. Removes the post's directory via `gert::git_rm()` (which stages the deletion and clears it from disk in one step), commits, and pushes.
- `retract_gh()` — the GitHub Contents API equivalent for GitHub-backed spokes, currently just BRUG. It figures out which section (`blog/` or `resources/`) the post landed in by checking `dispatch_log.csv`, unless you pass `section` explicitly — you'd only need to do that for posts dispatched before the log tracked sections at all. Underneath, it calls `github_delete_file()` once per file. Worth knowing: `retract_gh()` only deletes; it doesn't touch the log itself. That's `retract()`'s job, centralized there the same way `log_dispatch()` is centralized in `publish()` rather than duplicated inside each `dispatch_*()`.
- `retract_shopify()`, `retract_squarespace()`, `retract_wordpress()` — stubs, mirroring the dispatch stubs for the same reasons.

Every function in this file is called on `post_path` alone, without a `front_matter` argument — a small but deliberate asymmetry with the dispatch side. By the time I'm retracting something, I can't necessarily trust the post's local front matter to reflect what's actually live on the platform, so these functions identify posts by directory name instead.

### `R/get-started.R` — the quick reference

`get_started()` sources automatically via `.Rprofile` when I open the project, and prints a condensed cheat sheet covering new posts, edits, retraction, and structural changes, plus a status table of which platforms are actually live versus stubbed. It's meant to save me from having to remember all of this from scratch every time I sit down to write. One thing worth flagging: as of this README, `get_started()` still points at calling `retract_gh()` directly rather than the newer generalized `retract()` — I'd like to update that reference so the cheat sheet matches the current interface, but I'm noting it here rather than changing it silently.

## Common workflows

**Publishing a new post.** Scaffold it with `init_post("your-post-slug")`, write it, set `status: published` and confirm the `publish_to` list in the front matter, then call `publish()`. The one step that's easy to forget: any YAML front matter change — including flipping `status` to `published` — invalidates the freeze cache, so if the post has executed R code, re-render it locally (`quarto render posts/your-post-slug/index.qmd`) and commit the updated `_freeze/` output *before* pushing. Skipping this is the single most common way a Netlify build breaks, since Netlify has no R installed and depends entirely on that pre-rendered cache.

**Editing an existing post.** Same freeze-cache caveat applies if you touch the front matter. Otherwise, edit the `.qmd` and run `publish()` again — `dispatch_erwinlares()`'s idempotency means it's safe to call even if nothing's actually changed.

**Pulling a post down.** `retract(post_path, platform)` for a single platform, or call it once per platform if you want a post gone everywhere. It's worth remembering that erwinlares.com is the canonical hub, so retracting from it is a more consequential act than retracting from a spoke — there's no "it's still live somewhere else" safety net once it's off the hub.

**Structural changes** — layout, CSS, `_quarto.yml`, new pages — bypass this whole dispatch system. Those are just `git add . && git commit && git push`, the same as any other Quarto/Netlify site.

## Known rough edges

A couple of things I know about and haven't closed yet, mostly so I don't forget them:

`status: draft` is a custom YAML key I invented, and it only means something to the dispatch functions in this project — Quarto and Netlify have no idea it exists. A post marked `draft` still renders and publishes publicly the moment it's pushed; the field only gates whether it goes out to spoke platforms. Closing this gap means either using Quarto's own native `draft` key, or adding a render-time hook that reads `status` and excludes the post from the build. Neither is done yet.

`freeze: auto` won't detect changes to R scripts a post sources from elsewhere, only changes to the `.qmd` itself — so if I edit a sourced script without touching the post file, the freeze cache goes stale silently and the next Netlify build fails.

And a small filesystem quirk that's bitten me before: a bare `readme` with no extension is invisible to Quarto's listings, but `readme.md` — same name, with the extension — risks being picked up as a renderable document if it doesn't have valid YAML front matter. I keep ancillary files extensionless for exactly this reason.

## Tag taxonomy

Tags aren't just organizational — a couple of them trigger actual behavior. `journal` drives the dynamic "From the Journal" section on the About page. `announcement` and `journal` both, on BRUG specifically, route a post to `blog/` instead of the default `resources/`. The full canonical list I draw from: `personal`, `data-science`, `linguistics`, `pottery`, `aikido`, `r`, `brug`, `reproducibility`, `productivity`, `coding`, `journal`.