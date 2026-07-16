#### first try

library(ggplot2)

set.seed(42)

# ---- parameters -------------------------------------------------------------
n_cols   <- 14      # lattice columns
n_rows   <- 22      # lattice rows (body is taller than wide)
wobble   <- 0.18    # how wavy the reticulation lines are
spot_r   <- 0.16    # base spot radius (in cell units)

deep     <- "#0b2f57"   # deep navy (body core)
mid      <- "#12557f"   # mid teal-blue
edge     <- "#4ba3c9"   # pale edge blue
pale     <- "#dbeff5"   # spot / line colour

# ---- background gradient (fine raster) --------------------------------------
gres <- 260
bg <- expand.grid(x = seq(0, n_cols, length.out = gres),
                  y = seq(0, n_rows, length.out = gres))
# diagonal + radial mix so the core is deep and edges lighten
cx <- n_cols / 2; cy <- n_rows / 2
bg$rad  <- sqrt(((bg$x - cx) / cx)^2 + ((bg$y - cy) / cy)^2)
bg$diag <- (bg$x + bg$y) / (n_cols + n_rows)
bg$t    <- pmin(1, 0.55 * bg$rad + 0.45 * bg$diag)

# ---- wavy lattice lines -----------------------------------------------------
line_path <- function(fixed, along, amp, phase, freq) {
  # returns a wavy line: 'fixed' is the nominal coord, 'along' the sweep
  disp <- amp * sin(freq * along + phase) + rnorm(length(along), 0, 0.03)
  fixed + disp
}
along_y <- seq(0, n_rows, length.out = 200)
along_x <- seq(0, n_cols, length.out = 200)

vlines <- do.call(rbind, lapply(0:n_cols, function(i) {
  data.frame(grp = paste0("v", i),
             x = line_path(i, along_y, wobble, runif(1, 0, 6.28), runif(1, .4, .9)),
             y = along_y)
}))
hlines <- do.call(rbind, lapply(0:n_rows, function(j) {
  data.frame(grp = paste0("h", j),
             x = along_x,
             y = line_path(j, along_x, wobble, runif(1, 0, 6.28), runif(1, .4, .9)))
}))

# ---- spots: one per cell, jittered, varied size -----------------------------
spots <- expand.grid(cx = seq(0.5, n_cols - 0.5, by = 1),
                     cy = seq(0.5, n_rows - 0.5, by = 1))
spots$x    <- spots$cx + rnorm(nrow(spots), 0, 0.10)
spots$y    <- spots$cy + rnorm(nrow(spots), 0, 0.10)
spots$size <- spot_r * runif(nrow(spots), 0.55, 1.15)
# drop a few spots so the field is not perfectly regular
spots <- spots[runif(nrow(spots)) > 0.08, ]

# ---- plot -------------------------------------------------------------------
p <- ggplot() +
  geom_raster(data = bg, aes(x, y, fill = t)) +
  scale_fill_gradientn(colours = c(deep, mid, edge)) +
  geom_path(data = vlines, aes(x, y, group = grp),
            colour = pale, alpha = 0.28, linewidth = 0.4) +
  geom_path(data = hlines, aes(x, y, group = grp),
            colour = pale, alpha = 0.28, linewidth = 0.4) +
  geom_point(data = spots, aes(x, y, size = size),
             colour = pale, alpha = 0.9) +
  scale_size_identity() +
  coord_fixed(xlim = c(0, n_cols), ylim = c(0, n_rows), expand = FALSE) +
  theme_void() +
  theme(legend.position = "none",
        plot.background = element_rect(fill = deep, colour = NA))

ggsave("/home/claude/ws_v1.png", p, width = 5, height = 7.5, dpi = 130)
cat("done\n")


### second try

library(ggplot2)

set.seed(42)

# ---- parameters -------------------------------------------------------------
n_cols   <- 14      # lattice columns
n_rows   <- 22      # lattice rows (body is taller than wide)
wobble   <- 0.18    # how wavy the reticulation lines are
spot_r   <- 0.16    # base spot radius (in cell units)

# line character
line_w   <- 0.55    # base line width; segments swing above and below this
break_lvl<- 0.42    # solidity cutoff: higher = more dotted / broken line

# dot field
base_lam <- 0.55    # average dots per cell far from the head
dot_amin <- 0.40    # dot alpha floor
dot_amax <- 1.00    # dot alpha ceiling

# head: raises dot density nearby. move it anywhere in lattice units.
head_x   <- n_cols * 0.50
head_y   <- n_rows * 0.97   # near the top edge by default
head_reach <- n_rows * 0.45 # how far the head's influence reaches
head_boost <- 1.8            # extra expected dots per cell at the head

deep     <- "#0a2b52"   # deep navy (body core)
mid      <- "#0f5f92"   # mid teal-blue
edge     <- "#5cc0dd"   # pale edge blue
pale     <- "#eaf7fb"   # spot / line colour

# ---- background gradient (fine raster) --------------------------------------
gres <- 260
bg <- expand.grid(x = seq(0, n_cols, length.out = gres),
                  y = seq(0, n_rows, length.out = gres))
cx <- n_cols / 2; cy <- n_rows / 2
bg$rad  <- sqrt(((bg$x - cx) / cx)^2 + ((bg$y - cy) / cy)^2)
bg$diag <- (bg$x + bg$y) / (n_cols + n_rows)
bg$t    <- pmin(1, 0.55 * bg$rad + 0.45 * bg$diag)

# ---- lattice lines: wavy, width varies along length, break into dots --------
# Each line is sampled at many points, cut into short segments, and every
# segment gets its own width. A smooth "solidity" signal decides whether a
# segment is drawn at all, so lines fade from solid to dotted to broken.
build_line <- function(fixed, along, orient) {
  n <- length(along)
  t <- seq(0, 1, length.out = n)
  
  disp <- wobble * sin(runif(1, .4, .9) * along + runif(1, 0, 6.28)) +
    rnorm(n, 0, 0.03)
  if (orient == "v") { x <- fixed + disp; y <- along }
  else               { x <- along;        y <- fixed + disp }
  
  # width: smooth swell and thin down the length, plus a little noise
  wf <- 0.5 + 0.5 * sin(runif(1, 3, 7) * 2 * pi * t + runif(1, 0, 6.28))
  w  <- line_w * (0.20 + 1.55 * wf) + rnorm(n, 0, 0.04)
  w  <- pmax(w, 0.03)
  
  # solidity: low-frequency envelope + faster ripple. Where the sum dips
  # below break_lvl the segment is dropped; near the cutoff it flickers on
  # and off, which reads as a dotted run.
  env    <- 0.68 + 0.32 * sin(runif(1, 1.1, 2.4) * 2 * pi * t + runif(1, 0, 6.28))
  ripple <- 0.30 * sin(runif(1, 7, 12) * 2 * pi * t + runif(1, 0, 6.28))
  keep_pt <- (env + ripple) > break_lvl
  
  data.frame(
    x = x[-n], y = y[-n], xend = x[-1], yend = y[-1],
    w = (w[-n] + w[-1]) / 2,
    keep = keep_pt[-n] & keep_pt[-1]
  )
}

along_y <- seq(0, n_rows, length.out = 220)
along_x <- seq(0, n_cols, length.out = 220)
segs <- rbind(
  do.call(rbind, lapply(0:n_cols, function(i) build_line(i, along_y, "v"))),
  do.call(rbind, lapply(0:n_rows, function(j) build_line(j, along_x, "h")))
)
segs <- segs[segs$keep, ]

# ---- dot field: dots per cell vary; denser near the head --------------------
cells <- expand.grid(cx = seq(0.5, n_cols - 0.5, by = 1),
                     cy = seq(0.5, n_rows - 0.5, by = 1))
d2     <- (cells$cx - head_x)^2 + (cells$cy - head_y)^2
lambda <- base_lam + head_boost * exp(-d2 / (2 * head_reach^2))
cells$n <- rpois(nrow(cells), lambda)

dots <- do.call(rbind, lapply(which(cells$n > 0), function(i) {
  k <- cells$n[i]
  data.frame(
    x     = cells$cx[i] + runif(k, -0.42, 0.42),
    y     = cells$cy[i] + runif(k, -0.42, 0.42),
    size  = spot_r * runif(k, 0.35, 1.5),
    alpha = runif(k, dot_amin, dot_amax)
  )
}))
dots$a_glow <- dots$alpha * 0.16

# ---- plot -------------------------------------------------------------------
p <- ggplot() +
  geom_raster(data = bg, aes(x, y, fill = t)) +
  scale_fill_gradientn(colours = c(deep, mid, edge)) +
  geom_segment(data = segs,
               aes(x, y, xend = xend, yend = yend, linewidth = w),
               colour = pale, alpha = 0.42, lineend = "round") +
  scale_linewidth_identity() +
  geom_point(data = dots, aes(x, y, size = size * 2.1, alpha = a_glow),
             colour = pale) +
  geom_point(data = dots, aes(x, y, size = size, alpha = alpha),
             colour = pale) +
  scale_size_identity() +
  scale_alpha_identity() +
  coord_fixed(xlim = c(0, n_cols), ylim = c(0, n_rows), expand = FALSE) +
  theme_void() +
  theme(legend.position = "none",
        plot.background = element_rect(fill = deep, colour = NA))

ggsave("/home/claude/whaleshark_pattern.png", p, width = 5, height = 7.5, dpi = 130)
cat("segments:", nrow(segs), " dots:", nrow(dots), "\n")

######## third attempt

library(ggplot2)

set.seed(42)

# ---- parameters -------------------------------------------------------------
n_cols   <- 14      # lattice columns
n_rows   <- 22      # lattice rows (body is taller than wide)
wobble   <- 0.18    # how wavy the reticulation lines are

# line character: each line is redrawn a random number of times, every copy
# nudged by a tiny jitter. Where copies splay the bundle widens; where they
# converge it tightens. Width is therefore emergent, not computed.
max_copies <- 10    # a line is drawn between 1 and this many times
jit        <- 0.035 # size of the per-copy jitter (keep it minuscule)
line_alpha <- 0.14  # per-copy alpha; overlaps build up the solid core

# head: densest, smallest dots at the chosen quadrant centre. Moving away,
# dots grow sparser but larger on average (probabilistically, not by rule).
head_quadrant <- "top-left"   # top-left | top-right | bottom-left | bottom-right
lam_head <- 4.5     # expected dots per cell at the head
lam_far  <- 0.35    # expected dots per cell far from the head
size_head <- 0.12   # mean dot size at the head (small)
size_far  <- 0.34   # mean dot size in the tail (large)
reach_f   <- 0.22   # head influence, as a fraction of the plot diagonal

deep     <- "#0b2f57"   # deep navy (body core)
mid      <- "#12557f"   # mid teal-blue
edge     <- "#4ba3c9"   # pale edge blue
pale     <- "#dbeff5"   # spot / line colour

# ---- background gradient (fine raster) --------------------------------------
gres <- 260
bg <- expand.grid(x = seq(0, n_cols, length.out = gres),
                  y = seq(0, n_rows, length.out = gres))
cx <- n_cols / 2; cy <- n_rows / 2
bg$rad  <- sqrt(((bg$x - cx) / cx)^2 + ((bg$y - cy) / cy)^2)
bg$diag <- (bg$x + bg$y) / (n_cols + n_rows)
bg$t    <- pmin(1, 0.55 * bg$rad + 0.45 * bg$diag)

# ---- wavy lattice lines, redrawn with jitter --------------------------------
# The base wavy path is computed once per line so every copy follows the same
# reticulation; only the tiny jitter differs between copies.
build_line_copies <- function(id, fixed, along, orient) {
  base_disp <- wobble * sin(runif(1, .4, .9) * along + runif(1, 0, 6.28)) +
    rnorm(length(along), 0, 0.03)
  if (orient == "v") { bx <- fixed + base_disp; by <- along }
  else               { bx <- along;             by <- fixed + base_disp }
  
  k <- sample(seq_len(max_copies), 1)
  do.call(rbind, lapply(seq_len(k), function(cc) {
    jx <- jit * sin(runif(1, 1, 3) * along + runif(1, 0, 6.28)) +
      rnorm(length(along), 0, jit * 0.3)
    jy <- jit * sin(runif(1, 1, 3) * along + runif(1, 0, 6.28)) +
      rnorm(length(along), 0, jit * 0.3)
    data.frame(grp = paste0(id, "_", cc), x = bx + jx, y = by + jy)
  }))
}

along_y <- seq(0, n_rows, length.out = 200)
along_x <- seq(0, n_cols, length.out = 200)
lines_df <- rbind(
  do.call(rbind, lapply(0:n_cols, function(i) build_line_copies(paste0("v", i), i, along_y, "v"))),
  do.call(rbind, lapply(0:n_rows, function(j) build_line_copies(paste0("h", j), j, along_x, "h")))
)

# ---- dot field: count falls off from the head, size grows with distance -----
head_xy <- switch(head_quadrant,
                  "top-left"     = c(n_cols * 0.25, n_rows * 0.75),
                  "top-right"    = c(n_cols * 0.75, n_rows * 0.75),
                  "bottom-left"  = c(n_cols * 0.25, n_rows * 0.25),
                  "bottom-right" = c(n_cols * 0.75, n_rows * 0.25))
head_x <- head_xy[1]; head_y <- head_xy[2]

cells <- expand.grid(cx = seq(0.5, n_cols - 0.5, by = 1),
                     cy = seq(0.5, n_rows - 0.5, by = 1))
maxd  <- sqrt(n_cols^2 + n_rows^2)
reach <- reach_f * maxd
d     <- sqrt((cells$cx - head_x)^2 + (cells$cy - head_y)^2)
dn    <- d / maxd                                   # normalised distance 0..~1

cells$lam   <- lam_far + (lam_head - lam_far) * exp(-(d / reach)^2)
cells$n     <- rpois(nrow(cells), cells$lam)
cells$smean <- size_head + (size_far - size_head) * dn   # mean size grows outward

dots <- do.call(rbind, lapply(which(cells$n > 0), function(i) {
  k <- cells$n[i]
  data.frame(
    x     = cells$cx[i] + runif(k, -0.42, 0.42),
    y     = cells$cy[i] + runif(k, -0.42, 0.42),
    size  = pmax(0.02, cells$smean[i] * runif(k, 0.6, 1.35)), # probabilistic spread
    alpha = runif(k, 0.40, 1.00)
  )
}))

# ---- plot -------------------------------------------------------------------
p <- ggplot() +
  geom_raster(data = bg, aes(x, y, fill = t)) +
  scale_fill_gradientn(colours = c(deep, mid, edge)) +
  geom_path(data = lines_df, aes(x, y, group = grp),
            colour = pale, alpha = line_alpha, linewidth = 0.4) +
  geom_point(data = dots, aes(x, y, size = size, alpha = alpha),
             colour = pale) +
  scale_size_identity() +
  scale_alpha_identity() +
  coord_fixed(xlim = c(0, n_cols), ylim = c(0, n_rows), expand = FALSE) +
  theme_void() +
  theme(legend.position = "none",
        plot.background = element_rect(fill = deep, colour = NA))
p
ggsave("/home/claude/whaleshark_pattern.png", p, width = 5, height = 7.5, dpi = 130)
cat("line-copies:", length(unique(lines_df$grp)), " dots:", nrow(dots), "\n")


############## fourth attempt

library(ggplot2)

set.seed(42)

# ---- parameters -------------------------------------------------------------
n_cols   <- 10
n_rows   <- 18
wobble   <- 0.14    # slightly straighter reticulation than before

# lines: redrawn with jitter, but de-frayed (fewer copies, tighter jitter)
max_copies <- 6
jit        <- 0.020
line_alpha <- 0.16
line_w     <- 0.35

# ONE head-ness field h in [0,1] drives BOTH count and size, so the density
# peak and the small-dot region are the same place, by construction.
head_quadrant <- "top-left"   # top-left | top-right | bottom-left | bottom-right
reach_cells <- 5.0   # TIGHT: half-width of the hotspot in cells (was ~12)
lam_head <- 5.0      # dots/cell at the head (dense)
lam_far  <- 0.60     # dots/cell far away (sparse but not barren)
size_head <- 0.045   # dot size at the head (small)
size_far  <- 0.40    # dot size far away (large)
size_jit  <- 0.14    # +/- fraction of per-dot size noise (was 0.6..1.35 = huge)

deep <- "#0b2f57"; mid <- "#12557f"; edge <- "#4ba3c9"; pale <- "#dbeff5"

# ---- background gradient (unchanged) ----------------------------------------
gres <- 260
bg <- expand.grid(x = seq(0, n_cols, length.out = gres),
                  y = seq(0, n_rows, length.out = gres))
cx <- n_cols/2; cy <- n_rows/2
bg$rad  <- sqrt(((bg$x-cx)/cx)^2 + ((bg$y-cy)/cy)^2)
bg$diag <- (bg$x+bg$y)/(n_cols+n_rows)
bg$t    <- pmin(1, 0.55*bg$rad + 0.45*bg$diag)

# ---- lines: jittered copies, de-frayed --------------------------------------
build_line_copies <- function(id, fixed, along, orient) {
  base_disp <- wobble*sin(runif(1,.4,.9)*along + runif(1,0,6.28)) + rnorm(length(along),0,0.03)
  if (orient=="v") { bx <- fixed+base_disp; by <- along } else { bx <- along; by <- fixed+base_disp }
  k <- sample(seq_len(max_copies), 1)
  do.call(rbind, lapply(seq_len(k), function(cc) {
    jx <- jit*sin(runif(1,1,3)*along+runif(1,0,6.28)) + rnorm(length(along),0,jit*0.3)
    jy <- jit*sin(runif(1,1,3)*along+runif(1,0,6.28)) + rnorm(length(along),0,jit*0.3)
    data.frame(grp=paste0(id,"_",cc), x=bx+jx, y=by+jy)
  }))
}
along_y <- seq(0, n_rows, length.out = 200)
along_x <- seq(0, n_cols, length.out = 200)
lines_df <- rbind(
  do.call(rbind, lapply(0:n_cols, function(i) build_line_copies(paste0("v",i), i, along_y, "v"))),
  do.call(rbind, lapply(0:n_rows, function(j) build_line_copies(paste0("h",j), j, along_x, "h")))
)

# ---- dots: single head-ness field drives count AND size ---------------------
head_xy <- switch(head_quadrant,
                  "top-left"     = c(n_cols*0.25, n_rows*0.75),
                  "top-right"    = c(n_cols*0.75, n_rows*0.75),
                  "bottom-left"  = c(n_cols*0.25, n_rows*0.25),
                  "bottom-right" = c(n_cols*0.75, n_rows*0.25))
head_x <- head_xy[1]; head_y <- head_xy[2]

cells <- expand.grid(cx = seq(0.5, n_cols-0.5, by=1),
                     cy = seq(0.5, n_rows-0.5, by=1))
d <- sqrt((cells$cx-head_x)^2 + (cells$cy-head_y)^2)
cells$h <- exp(-(d/reach_cells)^2)                       # 1 at head, ->0 away

cells$lam   <- lam_far  + (lam_head  - lam_far ) * cells$h        # dense at head
cells$n     <- rpois(nrow(cells), cells$lam)
cells$smean <- size_far + (size_head - size_far) * cells$h        # small at head

dots <- do.call(rbind, lapply(which(cells$n > 0), function(i) {
  k <- cells$n[i]
  data.frame(
    x = cells$cx[i] + runif(k, -0.42, 0.42),
    y = cells$cy[i] + runif(k, -0.42, 0.42),
    size  = pmax(0.02, cells$smean[i] * runif(k, 1-size_jit, 1+size_jit)),
    alpha = runif(k, 0.45, 1.00)
  )
}))

# ---- plot -------------------------------------------------------------------
p <- ggplot() +
  geom_raster(data=bg, aes(x,y,fill=t)) +
  scale_fill_gradientn(colours=c(deep,mid,edge)) +
  geom_path(data=lines_df, aes(x,y,group=grp), colour=pale, alpha=line_alpha, linewidth=line_w) +
  geom_point(data=dots, aes(x,y,size=size,alpha=alpha), colour=pale) +
  scale_size_identity() + scale_alpha_identity() +
  coord_fixed(xlim=c(0,n_cols), ylim=c(0,n_rows), expand=FALSE) +
  theme_void() +
  theme(legend.position="none", plot.background=element_rect(fill=deep, colour=NA))

p

ggsave("/home/claude/whaleshark_pattern.png", p, width=5, height=7.5, dpi=130)
cat("dots:", nrow(dots), "\n")
