# erwinlares-site

This repo holds the Quarto source for [erwinlares.com](https://erwinlares.com), along with a small set of R helper functions I've written to publish and retract posts across the handful of places my writing ends up living. This README is the map to those helpers — what each one does, when to reach for it, and the handful of gotchas I've learned the hard way.

## The shape of the system

I think of this site as a hub, with a few spokes hanging off it. erwinlares.com is the canonical source: every post starts here, and everything else — [The Burrows](https://github.com/erwinlares/the-burrows) (the BRUG community site), lasrubieraspottery.com, [aikidoofwisconsin.com](https://www.aikidoofwisconsin.com) (Capital Aikikai of Wisconsin's dojo site, dispatched under the platform key `caow`), researchci.doit.wisc.edu — is a spoke that a post may or may not get pushed out to, depending on what I put in its front matter. `publish_to` in a post's YAML is the switch that decides which spokes a given post reaches; nothing gets pushed anywhere I haven't explicitly listed.

That hub-and-spoke framing matters because it shapes how the helper functions are organized. There's one function that dispatches a post outward per platform, and — as of the `retract()` work — a mirror-image function that pulls a post back per platform. Keeping those two operations symmetric, rather than letting retraction become an afterthought bolted onto a couple of platforms, is a design choice I've tried to hold onto as this has grown.

None of this lives inside an R package, by the way — no `DESCRIPTION`, no `NAMESPACE`, nothing you'd `devtools::install()`. These are just sourced helper scripts living in `R/`, meant to be run from an R console with the project open.

## Before you start: credentials

Two GitHub personal access tokens live in `.Renviron`, one per GitHub-backed spoke:

- `GITHUB_PAT_BRUG`, scoped to Contents: Read and Write on `erwinlares/the-burrows`
- `GITHUB_PAT_CAOW`, scoped to Contents: Read and Write on `erwinlares/caow-website`

Neither is ever written to a post file or committed anywhere — `Sys.getenv()` reads them at call time, and every function that needs one checks for its presence up front and fails loudly if it's missing, rather than failing halfway through a dispatch with a partial set of files pushed.

Pushing to erwinlares.com itself doesn't need a PAT at all — that goes through your existing local git credentials via `gert`, the same way you'd `git push` from the command line.

## The files

### `R/publish.R` — the dispatch layer

This is the orchestrator. `publish()` walks every post under `posts/`, keeps only the ones marked `status: published`, and for each one loops over whatever platforms are listed in its `publish_to` field, calling the matching `dispatch_*()` function:

- `dispatch_erwinlares()` — commits and pushes the post to this repo, which is what actually gets it live on erwinlares.com once Netlify rebuilds. Idempotent: if the post's already committed and nothing's changed, it says so and moves on rather than creating an empty commit.
- `dispatch_brug()` — pushes the post to The Burrows via the GitHub Contents API, no local clone required. It routes to `resources/` by default, unless the post's `categories` field contains `"announcement"` or `"journal"`, in which case it lands in `blog/` instead. Because BRUG's GitHub Actions CI has no R installed, this one pre-cleans the front matter and forces `engine: markdown` before pushing, so nothing there depends on live execution.
- `dispatch_caow()` — pushes the post to caow-website (aikidoofwisconsin.com) via the same Contents API mechanism, landing every post at `blog/{post-slug}/` — no resources/blog split, just one target. Unlike BRUG, caow-website runs its own Quarto + GitHub + Netlify pipeline, the same stack as this repo, so the post goes out largely as-is and gets rendered by CAOW's own Netlify build rather than pre-cleaned here.
- `dispatch_shopify()`, `dispatch_wordpress()` — stubs. Shopify's API is commerce-only with no content-posting endpoint, so that one's more or less permanently a stub. WordPress is waiting on a separate migration.

`publish.R` also owns `dispatch_log.csv`, which tracks, per post and per platform, whether dispatch succeeded, when, and which `section` it landed in (that matters for `dispatch_brug()`'s `blog/` vs. `resources/` split, and — trivially, since it's always the same value — for `dispatch_caow()` too). `already_dispatched()` checks this log before dispatching, so re-running `publish()` is safe — it skips anything already sent rather than duplicating it.

Valid `publish_to` values as of this writing: `erwinlares`, `brug`, `caow`, `lasrubieraspottery`, `researchci`. The old `aikidoofwisconsin` key is retired — caow-website replaced the Squarespace-backed version of that spoke, so `dispatch_squarespace()` is gone too.

### `R/github-helpers.R` — shared GitHub Contents API primitives

`github_get_sha()` (fetches a file's current SHA, needed for any update via the Contents API) and `github_put_file()` (creates or updates a single file) used to live inside `dispatch-brug.R`, back when BRUG was the only GitHub-backed spoke. Once `dispatch_caow()` needed the same two functions, I pulled them out here so neither dispatcher owns primitives the other depends on. `github_delete_file()` lives here too — it's the retraction counterpart to `github_put_file()`, called by `retract_gh()`. It's idempotent: if the file's already gone (a 404 on the SHA lookup), that's treated as success rather than an error, since the end state — file absent — already holds. All three are deliberately platform-agnostic — no BRUG- or CAOW-specific knowledge belongs in this file.

### `R/dispatch-brug.R` — BRUG-specific dispatch logic

What's left here after the extraction above: `dispatch_brug()` itself, plus the front-matter cleanup it needs — `strip_front_matter_brug()` strips a post's YAML down to what BRUG actually needs, and forces `engine: markdown` so BRUG's GitHub Actions CI never tries to execute R (BRUG posts render as static syntax-highlighted code blocks, which is deliberate: BRUG's CI has no R installed, so nothing there can depend on live execution).

### `R/dispatch-caow.R` — CAOW-specific dispatch logic

`dispatch_caow()` and its front-matter helper, `prepare_front_matter_caow()`. Because caow-website renders its own posts (unlike BRUG), this doesn't need BRUG's aggressive stripping — it only touches two things: it drops `publish_to` (hub-only bookkeeping that has no meaning in caow-website's repo), and it merges in `format.html.include-before-body: "../../_partials/blog-nav.html"`, which CAOW's blog template expects but which would break rendering if it ever ended up in this hub's own copy of the post — the relative path only resolves correctly from within caow-website's own `blog/{slug}/` structure. Keeping that field out of the hub source, and injecting it only on the pushed copy, is what keeps a single post safely shareable between erwinlares.com and caow-website when it's tagged for both.

### `R/retract.R` — pulling a post back

This is the newer half of the system, and it's meant to read as `publish.R`'s mirror image. `retract(post_path, platform)` is the entry point — pass it a post's path and a platform name, and it routes to the matching `retract_*()` function, then clears that post's row from `dispatch_log.csv` so a future `publish()` treats it as un-dispatched and will send it again if it's still listed in `publish_to`.

- `retract_erwinlares()` — the git-based retraction from the hub itself. Removes the post's directory via `gert::git_rm()` (which stages the deletion and clears it from disk in one step), commits, and pushes.
- `retract_gh()` — the GitHub Contents API equivalent for GitHub-backed spokes: BRUG and CAOW both go through this one function, with `owner`/`repo` passed in per platform. It figures out which section (`blog/` or `resources/` for BRUG; always `blog/` for CAOW) the post landed in by checking `dispatch_log.csv`, unless you pass `section` explicitly — you'd only need to do that for posts dispatched before the log tracked sections at all. It also derives which credential to use from `platform` itself — `Sys.getenv(paste0("GITHUB_PAT_", toupper(platform)))` — so `"brug"` reads `GITHUB_PAT_BRUG` and `"caow"` reads `GITHUB_PAT_CAOW` without the function needing to know about either one specifically. Underneath, it calls `github_delete_file()` once per file. Worth knowing: `retract_gh()` only deletes; it doesn't touch the log itself. That's `retract()`'s job, centralized there the same way `log_dispatch()` is centralized in `publish()` rather than duplicated inside each `dispatch_*()`.
- `retract_shopify()`, `retract_wordpress()` — stubs, mirroring the dispatch stubs for the same reasons.

Every function in this file is called on `post_path` alone, without a `front_matter` argument — a small but deliberate asymmetry with the dispatch side. By the time I'm retracting something, I can't necessarily trust the post's local front matter to reflect what's actually live on the platform, so these functions identify posts by directory name instead.

### `R/get-started.R` — the quick reference

`get_started()` sources automatically via `.Rprofile` when I open the project, and prints a condensed cheat sheet covering new posts, edits, retraction, and structural changes, plus a status table of which platforms are actually live versus stubbed.

## Common workflows

**Publishing a new post.** Scaffold it with `init_post("your-post-slug")`, write it, set `status: published` and confirm the `publish_to` list in the front matter, then call `publish()`. The one step that's easy to forget: any YAML front matter change — including flipping `status` to `published` — invalidates the freeze cache, so if the post has executed R code, re-render it locally (`quarto render posts/your-post-slug/index.qmd`) and commit the updated `_freeze/` output *before* pushing. Skipping this is the single most common way a Netlify build breaks, since Netlify has no R installed and depends entirely on that pre-rendered cache.

**Editing an existing post.** Same freeze-cache caveat applies if you touch the front matter. Otherwise, edit the `.qmd` and run `publish()` again — `dispatch_erwinlares()`'s idempotency means it's safe to call even if nothing's actually changed.

**Pulling a post down.** `retract(post_path, platform)` for a single platform, or call it once per platform if you want a post gone everywhere. It's worth remembering that erwinlares.com is the canonical hub, so retracting from it is a more consequential act than retracting from a spoke — there's no "it's still live somewhere else" safety net once it's off the hub.

**Structural changes** — layout, CSS, `_quarto.yml`, new pages — bypass this whole dispatch system. Those are just `git add . && git commit && git push`, the same as any other Quarto/Netlify site. This is also exactly the pathway the pre-commit hook below guards.

## Guarding the hub: the pre-commit hook

A post whose `publish_to` doesn't include `erwinlares` (a caow-only post, say) is never pushed to this repo's remote by `publish()` — `dispatch_erwinlares()` simply isn't called for it. But the file still sits locally in `posts/`, and Netlify renders whatever's actually committed to `main`, regardless of what `dispatch_log.csv` says. An unrelated structural commit — `git add .` while fixing a CSS rule, say — can sweep that post in and publish it on erwinlares.com by accident.

`.githooks/pre-commit` guards against exactly that: it inspects every staged `posts/*/index.qmd`, and refuses the commit if any of them omit `erwinlares` from `publish_to`. It's a no-op for commits that don't touch a post file, so it never gets in the way of ordinary structural changes. Since git hooks in `.git/hooks/` aren't version-controlled by default, this one lives in a tracked `.githooks/` directory instead — it needs a one-time setup per clone:

```
git config core.hooksPath .githooks
```

`git commit --no-verify` bypasses it, same as any hook — a deliberate override, not something that happens by accident. My own practice going forward: if a post is genuinely exclusive to a spoke, I write it directly in that spoke's own repo rather than starting it here at all, so the hook is mostly a backstop for mistakes rather than something I expect to trip often.

## Known rough edges

A couple of things I know about and haven't closed yet, mostly so I don't forget them:

`status: draft` is a custom YAML key I invented, and it only means something to the dispatch functions in this project — Quarto and Netlify have no idea it exists. A post marked `draft` still renders and publishes publicly the moment it's pushed; the field only gates whether it goes out to spoke platforms. Closing this gap means either using Quarto's own native `draft` key, or adding a render-time hook that reads `status` and excludes the post from the build. Neither is done yet.

`freeze: auto` won't detect changes to R scripts a post sources from elsewhere, only changes to the `.qmd` itself — so if I edit a sourced script without touching the post file, the freeze cache goes stale silently and the next Netlify build fails.

`yaml::as.yaml()` dumps R logicals as `yes`/`no` by default, not `true`/`false` — a YAML 1.1 spelling that Quarto's strict YAML 1.2 parser rejects outright ("Field \"echo\" has value yes, which must instead be `true` or `false`", etc.). This broke the very first CAOW deploy: `dispatch_caow()` re-serializes a post's *entire* front matter through `as.yaml()`, so any `execute:`/`format: html:` boolean silently flipped to `yes`/`no` on the way through and failed CAOW's Netlify build. Fixed there with a custom `logical` handler in `make_prepared_post_text()` that forces `true`/`false`. `dispatch_brug()` doesn't hit this today because `strip_front_matter_brug()` only keeps fields that are never logical (title, author, date, categories, description, engine) — but that's true by coincidence, not by design, so if a boolean field is ever added to what BRUG keeps, apply the same handler fix there. If a *new* GitHub-backed spoke gets added later and its dispatcher re-serializes front matter at all, assume it needs this handler too rather than finding out from a broken build.

`dispatch_erwinlares()` and `retract_erwinlares()` both check `gert::git_status()` to decide whether there's anything to commit — but that check is repo-wide, not scoped to the post's own directory. If something else is already staged (a structural change I started but haven't committed yet, say) when either function runs, the check can't tell the difference between "this post has changes" and "something, anything, is staged" — and since `gert::git_commit()` commits the entire index, not just the post, a stray staged file could end up bundled into a commit titled `publish: <post title>` or worse, silently prevent the post's own changes from being detected as needing a commit at all. This is exactly what happened testing the caow spoke: the caow-implementation files were staged for review at the same time a test post went through `publish()`, and the post ended up not committed at all.

The operating rule that sidesteps this: content changes always go through `publish()`/`retract()` with a clean staging area — nothing else staged when either runs. Structural changes (layout, CSS, `_quarto.yml`, new pages, or anything in `R/`) go through manual `git add`/`git commit`/`git push` instead, never interleaved with a `publish()`/`retract()` call. As long as those two paths don't overlap, the repo-wide check happens to mean what it's supposed to mean. It's a workflow discipline masking the underlying bug, not a fix — the check itself is still unscoped, so if the discipline ever slips, the same confusion can resurface. Scoping the check (and, harder, scoping the commit itself, which may or may not be possible with `gert::git_commit()`) would close this properly; not done yet.

And a small filesystem quirk that's bitten me before: a bare `readme` with no extension is invisible to Quarto's listings, but `readme.md` — same name, with the extension — risks being picked up as a renderable document if it doesn't have valid YAML front matter. I keep ancillary files extensionless for exactly this reason.

## Tag taxonomy

Tags aren't just organizational — a couple of them trigger actual behavior. `journal` drives the dynamic "From the Journal" section on the About page. `announcement` and `journal` both, on BRUG specifically, route a post to `blog/` instead of the default `resources/`. The full canonical list I draw from: `personal`, `data-science`, `linguistics`, `pottery`, `aikido`, `r`, `brug`, `reproducibility`, `productivity`, `coding`, `journal`.