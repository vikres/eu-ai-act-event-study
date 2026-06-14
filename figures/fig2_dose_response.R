# =====================================================================
# Figure 2 - Dose-response: signed CAR vs AI exposure (the null gradient)
# Shows there is NO smooth relationship between AI exposure and reaction.
# Base R. Run; saves a PNG.
# =====================================================================

# Mean AI-exposure in each bin, and mean signed CAR (% ; + = moved WITH
# the regulatory direction). Signed = -CAR at tightening, +CAR at easing.
expo   <- c(-0.76, -0.14, 0.19, 1.85)
signed <- c(0.169, -0.324, 0.152, 0.102)

png("fig2_dose_response.png", width = 850, height = 600, res = 130)
par(mar = c(4.5, 4.5, 3, 1), family = "sans")

plot(expo, signed, type = "b", pch = 19, lwd = 2, col = "steelblue",
     xlab = "Industry AI exposure (Felten AIIE)",
     ylab = "Mean signed CAR (%)",
     main = "No dose-response: reaction does not scale with AI exposure",
     ylim = c(-0.6, 0.6), cex.main = 0.95)
abline(h = 0, col = "grey60", lty = 2)

# add a flat fitted line to underline the absence of a gradient
fit <- lm(signed ~ expo)
abline(fit, col = "firebrick", lwd = 1.5, lty = 3)
legend("topright", legend = c("Bin means", "Fitted (flat)"),
       col = c("steelblue", "firebrick"), lty = c(1, 3), pch = c(19, NA),
       bty = "n", cex = 0.85)

dev.off()
