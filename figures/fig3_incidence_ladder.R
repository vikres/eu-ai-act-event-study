# =====================================================================
# Figure 3 - Legal-incidence ladder
# Treated-minus-control CAR[-1,+1] for each exposure concept, two events.
# Shows: continuous exposure = flat; legal categories = significant.
# Base R. Run; saves a PNG.
# =====================================================================

labels <- c("Continuous\nAI exposure", "Tech / provider\nsectors",
            "Developer /\nprovider", "High-risk\ndomain")

# Each row: difference (pp), lower CI, upper CI, significant? (p<0.05)
# --- E1 (11 Dec 2023, tightening) ---
e1_diff <- c(-0.12, 0.08, 1.22, -0.57)
e1_lo   <- c(-0.33, -0.51, 0.34, -1.03)
e1_hi   <- c( 0.09,  0.67, 2.11, -0.11)
e1_sig  <- c(FALSE, FALSE, TRUE, TRUE)
# --- E4 (04 Aug 2025, GPAI) ---
e4_diff <- c( 0.02, -1.26, -1.15, 0.43)
e4_lo   <- c(-0.19, -2.19, -2.09, -0.02)
e4_hi   <- c( 0.23, -0.33, -0.20, 0.87)
e4_sig  <- c(FALSE, TRUE, TRUE, FALSE)

png("fig3_incidence_ladder.png", width = 1100, height = 500, res = 130)
par(mfrow = c(1, 2), mar = c(4.5, 8, 3, 1), family = "sans")

ladder <- function(diff, lo, hi, sig, ttl) {
  y <- length(diff):1
  cols <- ifelse(sig, "steelblue", "grey65")
  plot(diff, y, xlim = range(c(lo, hi)), ylim = c(0.5, length(diff) + 0.5),
       pch = 19, col = cols, cex = 1.3, yaxt = "n", ylab = "",
       xlab = "Treated - control CAR[-1,+1] (pp)", main = ttl, cex.main = 0.95)
  segments(lo, y, hi, y, col = cols, lwd = 2)
  abline(v = 0, col = "grey40")
  axis(2, at = y, labels = labels, las = 1, cex.axis = 0.75)
  # star the significant ones
  text(hi[sig] + 0.1, y[sig], "*", col = "firebrick", cex = 1.6)
}

ladder(e1_diff, e1_lo, e1_hi, e1_sig, "E1 - 11 Dec 2023 (tightening)")
ladder(e4_diff, e4_lo, e4_hi, e4_sig, "E4 - 04 Aug 2025 (GPAI)")

dev.off()
