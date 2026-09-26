# eu-ai-act-event-study

Code for my Bocconi undergraduate thesis, *AI exposure and equity market reactions to the EU Artificial Intelligence Act: evidence from European listed firms* (2026).

This repository holds the first stage: an event study of STOXX Europe 600 constituents around four EU AI Act milestones, namely the trilogue agreement (December 2023), the start of general-purpose AI obligations (August 2025), the Council position on simplification (March 2026) and the simplification agreement (May 2026).

## scripts/01_membership.R

Rebuilds point-in-time index membership on each event date from the Compustat Global constituent history, so firms that later left the index stay in the sample and the results carry no survivorship bias. The union across events is 680 firms, with 581 to 589 per event after data screens.

## scripts/02_build_returns.R

Stitches the Datastream download batches into two clean panels keyed by ISIN: total-return indices (RI) and market values (MV).

## scripts/03_event_study.R

Estimates a market model for every firm and event over trading days −250 to −30, then computes daily abnormal returns, cumulative abnormal returns over the event windows and summary statistics per event.

## scripts/04_figures.R

Plots cumulative average abnormal return paths over trading days −10 to +10 for each event (`figures/fig_caar_paths.png`).

## Data

The inputs are licensed and not included: index constituents come from Compustat Global via WRDS and returns from LSEG Datastream. The scripts read them from `data/`.
