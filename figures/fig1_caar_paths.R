# =====================================================================
# Figure 1 - CAAR paths around each AI Act event
# Base R. Paste-in values; run; saves a PNG.
# =====================================================================

# Trading days -10..+10 on the x-axis
days <- -10:10

# Cumulative average abnormal returns (%) for each event
E1 <- c(0.227,0.198,0.383,-0.077,-0.311,-0.416,-0.282,-0.008,0.112,0.047,-0.082,-0.182,-0.088,1.201,1.049,1.069,1.178,1.327,1.304,1.28,1.291)
E2 <- c(-0.575,-0.833,-0.842,-0.879,-1.01,-1.183,-1.115,-0.725,-0.955,-0.757,-0.659,-0.764,-0.879,-0.949,-1.321,-1.449,-1.128,-0.939,-0.996,-1.128,-1.071)
E3 <- c(0.061,-0.029,-0.429,-0.456,-0.374,-0.52,-1.066,-1.19,-1.382,-1.294,-1.421,-1.604,-1.591,-1.319,-1.823,-1.83,-1.758,-1.877,-1.638,-1.457,-1.752)
E4 <- c(0.212,0.224,0.201,0.389,0.451,-0.001,-0.315,-0.603,-0.532,-0.303,-0.425,-0.239,-0.087,-0.096,-0.013,-0.387,-0.321,-0.645,-1.012,-0.963,-1.097)

# Save to file (comment out the next line and dev.off() to view on screen)
png("fig1_caar_paths.png", width = 1000, height = 800, res = 130)

par(mfrow = c(2, 2), mar = c(4, 4, 3, 1), family = "sans")

draw <- function(y, ttl, col) {
  plot(days, y, type = "l", lwd = 2, col = col,
       xlab = "Trading days relative to event", ylab = "CAAR (%)",
       main = ttl, cex.main = 0.95)
  abline(h = 0, col = "grey60")
  abline(v = 0, col = col, lty = 2)
  points(0, y[days == 0], pch = 19, col = col)
}

draw(E1, "E1 - 11 Dec 2023 (tightening)", "firebrick")
draw(E2, "E2 - 07 May 2026 (easing)",     "forestgreen")
draw(E3, "E3 - 13 Mar 2026 (easing valid.)", "forestgreen")
draw(E4, "E4 - 04 Aug 2025 (GPAI)",       "steelblue")

dev.off()
