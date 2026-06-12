# =====================================================================
# 04_figures.R   --- Figure 1: CAAR paths around each event
# ---------------------------------------------------------------------
# Purpose:
#   Plot cumulative average abnormal returns over [-10,+10] trading days
#   around each event, one panel per event, as the thesis's Tier-1
#   figure. Reads the path data produced by 03_event_study.R.
#
# Input  (in DATA_DIR):  caar_paths_long.csv
# Output (in DATA_DIR):  fig_caar_paths.png  and  fig_caar_paths.pdf
# =====================================================================

# ---- CONFIG ----------------------------------------------------------
DATA_DIR <- "C:/Users/victo/Downloads/thesis/data"
# ---------------------------------------------------------------------

library(ggplot2)

paths <- read.csv(file.path(DATA_DIR, "caar_paths_long.csv"), stringsAsFactors = FALSE)

# Readable panel titles, ordered tightening -> easing -> secondary
labels <- c(
  E1 = "E1 \u2014 11 Dec 2023 \u00b7 Trilogue agreement (tightening)",
  E2 = "E2 \u2014 07 May 2026 \u00b7 Simplification agreement (easing)",
  E3 = "E3 \u2014 13 Mar 2026 \u00b7 Council position (easing validation)",
  E4 = "E4 \u2014 04 Aug 2025 \u00b7 GPAI obligations apply"
)
paths$panel <- factor(labels[paths$event], levels = labels)

# Colour each event by its economic direction
colmap <- c(
  "E1 \u2014 11 Dec 2023 \u00b7 Trilogue agreement (tightening)"        = "#dc2626", # tightening (red)
  "E2 \u2014 07 May 2026 \u00b7 Simplification agreement (easing)"      = "#16a34a", # easing (green)
  "E3 \u2014 13 Mar 2026 \u00b7 Council position (easing validation)"   = "#16a34a",
  "E4 \u2014 04 Aug 2025 \u00b7 GPAI obligations apply"                 = "#0f6fc6"  # developer (blue)
)

p <- ggplot(paths, aes(x = rel_day, y = caar, colour = panel)) +
  geom_hline(yintercept = 0, colour = "#999999", linewidth = 0.3) +
  geom_vline(xintercept = 0, linetype = "dashed", colour = "#888888", linewidth = 0.4) +
  geom_line(linewidth = 0.9) +
  geom_point(data = subset(paths, rel_day == 0), size = 1.8) +
  facet_wrap(~ panel, ncol = 2, scales = "free_y") +
  scale_colour_manual(values = colmap, guide = "none") +
  scale_x_continuous(breaks = seq(-10, 10, 5), limits = c(-10, 10)) +
  labs(
    title = "Cumulative average abnormal returns around EU AI Act events",
    subtitle = "Market model vs STOXX Europe 600, equal-weighted across constituents",
    x = "Trading days relative to event", y = "CAAR (%)"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    plot.title    = element_text(face = "bold", size = 13),
    plot.subtitle = element_text(colour = "#555555", size = 10),
    strip.text    = element_text(face = "bold", size = 9.5),
    panel.grid.minor = element_blank(),
    panel.spacing = unit(1, "lines")
  )

ggsave(file.path(DATA_DIR, "fig_caar_paths.png"), p, width = 11, height = 8.2, dpi = 150)
ggsave(file.path(DATA_DIR, "fig_caar_paths.pdf"), p, width = 11, height = 8.2)

cat("Figure written: fig_caar_paths.png and fig_caar_paths.pdf in\n  ", DATA_DIR, "\n", sep = "")
