# eu-ai-act-event-study

Code for my Bocconi undergraduate thesis, *AI exposure and equity market reactions to the EU Artificial Intelligence Act: evidence from European listed firms* (2026).

This is stage 1, an event study of STOXX Europe 600 constituents around four EU AI Act milestones: the trilogue agreement (December 2023), the start of general-purpose AI obligations (August 2025), the Council position on simplification (March 2026) and the simplification agreement (May 2026).

| Script | What it does |
|---|---|
| `scripts/01_membership.R` | Rebuilds point-in-time index membership on each event date from the Compustat Global constituent history, so firms that later left the index stay in the sample (680 distinct firms, 581 to 589 per event after screens) |
| `scripts/02_build_returns.R` | Stitches the Datastream download batches into total-return (RI) and market-value (MV) panels keyed by ISIN |
| `scripts/03_event_study.R` | Estimates a market model per firm and event over trading days −250 to −30, then computes abnormal returns, CARs and summary statistics per event |
| `scripts/04_figures.R` | Plots CAAR paths over [−10, +10] for each event (`figures/fig_caar_paths.png`) |

## Data

Not included, because the sources are licensed: index constituents come from Compustat Global via WRDS and returns from LSEG Datastream. The scripts read their inputs from `data/`.
