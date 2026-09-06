# ------------------------------------------------------------------------------
# Title:   Question 3 (Graphs) - Adverse event visualizations with {ggplot2}
#
# Purpose: Produce the two adverse event figures requested in the assessment.
#
# Input dataset(s):
#   - pharmaverseadam::adae   adverse events (AESEV, AETERM), TEAEs are TRTEMFL == "Y"
#   - pharmaverseadam::adsl   subject level data (denominator, ACTARM)
#
# Output(s):
#   - question_3_tlg/ae_severity_by_treatment.png
#       Plot 1: AE severity (AESEV) distribution by treatment arm, record-level counts
#   - question_3_tlg/ae_top10_incidence_ci.png
#       Plot 2: top 10 AEs by subject incidence with 95% Clopper-Pearson CIs
#   - question_3_tlg/run_log_02.txt   console log proving an error-free run
#
# Author: Maksim Sendetski
# Date:   2026-09-02
# ------------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(pharmaverseadam)
})

# ------------------------------------------------------------------------------
# 1. Source data and analysis population
# ------------------------------------------------------------------------------

adae <- pharmaverseadam::adae
adsl <- pharmaverseadam::adsl

# Same population rule as the summary table in 01_create_ae_summary_table.R: ADSL
# carries a fourth ACTARM, "Screen Failure" (52 subjects screened but never
# treated), who were never at risk of a treatment-emergent event. The denominator
# is the three treatment arms, N = 254.
#
# That set has a name: it is exactly the Safety population. ADSL flags it as
# SAFFL == "Y", which selects 254 subjects - the same 254, subject for subject,
# that the three treatment arms select (asserted in the validation block below).
# The Safety population is the standard denominator for adverse event incidence,
# because it is defined as the subjects who received any study drug and were
# therefore at risk of a treatment-emergent event. The ACTARM filter is kept as
# the operative definition so that this script and the summary table select the
# population the same way; SAFFL is verified against it rather than substituted
# for it.

TRT_ARMS <- c("Placebo", "Xanomeline Low Dose", "Xanomeline High Dose")

pop <- adsl %>%
  filter(ACTARM %in% TRT_ARMS)

teae <- adae %>%
  filter(TRTEMFL == "Y")

n_treated <- nrow(pop)

# ------------------------------------------------------------------------------
# 2. Plot 1 - AE severity distribution by treatment
# ------------------------------------------------------------------------------

# Counting here is at RECORD level, deliberately, and this is the one place in
# Question 3 where that is correct. The figure describes the severity profile of
# the events themselves - of all the adverse events that occurred, how many were
# mild, moderate or severe. Collapsing to subject level would force one severity
# per subject and discard the very thing being plotted: a subject with four mild
# events and one severe event contributes five events at five severities. The
# incidence question ("how many subjects were affected") is answered by the
# summary table and by Plot 2 below, both of which do count subjects.
#
# AESEV is stored as character, so it would otherwise sort alphabetically and put
# MILD after MODERATE. An ordered factor fixes the legend and the stacking order
# to the clinical severity ordering.

SEV_LEVELS <- c("MILD", "MODERATE", "SEVERE")

sev_counts <- teae %>%
  mutate(AESEV = factor(AESEV, levels = SEV_LEVELS, ordered = TRUE)) %>%
  count(ACTARM, AESEV, name = "n_events")

# Total event burden per arm, annotated above each bar. The stack already shows
# the total as the bar height, but reading it off the axis is imprecise, and it
# is the one number a reader most often wants from this figure.

arm_totals <- sev_counts %>%
  group_by(ACTARM) %>%
  summarise(n_total = sum(n_events), .groups = "drop")

# Per-segment label positions, computed here rather than left to
# position_stack(), which centres every label in its own band. Centring is right
# for MILD and MODERATE - those bands are 65 to 286 events tall and have room to
# spare - but fails for the shortest SEVERE segments: with only 6 and 10 events,
# their midpoints land at 3 and 5 on the count scale and the label collides with
# the x axis. Those two are lifted just above the top edge of their segment.
# Every other label, SEVERE included where the band is tall enough, keeps the
# centred position it would have had.
#
# Lifting only the labels that need it is deliberate. Applying the
# just-above-the-top rule to all three severities would push the MILD label above
# the bar, where it would compete with the arm total drawn there.
#
# geom_col() stacks the first factor level at the top, so the stack builds from
# the bottom in reverse severity order: SEVERE, then MODERATE, then MILD. The
# running total taken in that order gives each segment's upper boundary, and the
# boundary minus half the segment's own height gives its midpoint - which
# reproduces exactly what position_stack(vjust = 0.5) computed.
#
# Label ink is chosen for contrast against the fill the label actually sits on,
# not against its own severity: MILD's label sits on the pale tint and is drawn
# dark (contrast 7.4), while the MODERATE and lifted SEVERE labels both sit on
# the Roche-blue band and are drawn white (contrast 4.6, above the 4.5 needed for
# body text). Carried as a column and mapped through scale_colour_identity() so
# the colour travels with its row instead of depending on layer row order.
#
# Only the labels move. The bars are still drawn by geom_col() from n_events.

LABEL_OFFSET <- 10

# A SEVERE label is lifted only when its own band is too short to hold it. At
# this figure's scale one line of label text is about 12 event units tall, so a
# band of 20 units or more has room to centre the label inside itself with a
# margin at each edge. Xanomeline Low Dose (25 severe events) clears that and
# keeps its label in its own dark band; Placebo (6) and Xanomeline High Dose (10)
# do not, and theirs are lifted. Expressing it as a height test rather than
# naming the arms means the figure stays correct if the data change.

MIN_BAND_INSIDE <- 20

sev_counts <- sev_counts %>%
  arrange(ACTARM, desc(AESEV)) %>%
  group_by(ACTARM) %>%
  mutate(
    stack_top    = cumsum(n_events),
    stack_mid    = stack_top - n_events / 2,
    label_y      = if_else(AESEV == "SEVERE" & n_events < MIN_BAND_INSIDE,
                           stack_top + LABEL_OFFSET, stack_mid),
    label_colour = if_else(AESEV == "MILD", "grey20", "white")
  ) %>%
  ungroup()

# Stacked rather than grouped: the stack shows both the composition within an arm
# and the total event burden of that arm in one mark.
#
# #007AC2 is Roche's brand blue and anchors the palette. The severity ramp is a
# single hue at three lightness steps - a white tint of the anchor for MILD, the
# anchor itself for MODERATE, a black shade of it for SEVERE - so severity is
# encoded by intensity rather than by hue. That is what keeps it readable in
# greyscale and under colour vision deficiency: the steps fall at greyscale
# values 196 / 116 / 66, with adjacent contrast ratios of 2.69 and 2.26, so no
# viewer has to distinguish colours to read the order.

ROCHE_BLUE <- "#007AC2"

p_severity <- ggplot(sev_counts, aes(x = ACTARM, y = n_events, fill = AESEV)) +
  geom_col(width = 0.6) +
  geom_text(
    aes(y = label_y, label = n_events, colour = label_colour),
    size = 3.4
  ) +
  geom_text(
    data = arm_totals,
    aes(x = ACTARM, y = n_total, label = n_total),
    inherit.aes = FALSE,
    vjust = -0.6,
    size = 3.6,
    colour = "grey20"
  ) +
  scale_fill_manual(
    values = c(MILD = "#9ECCE8", MODERATE = ROCHE_BLUE, SEVERE = "#00436B"),
    name = "Severity"
  ) +
  scale_colour_identity() +
  # Headroom for the total above the tallest bar.
  scale_y_continuous(expand = expansion(mult = c(0, 0.08))) +
  labs(
    title = "Treatment-emergent adverse events by severity and treatment arm",
    subtitle = paste0(
      "Event records (not subjects); ", nrow(teae),
      " treatment-emergent events in ", n_treated, " treated subjects"
    ),
    x = NULL,
    y = "Number of adverse event records"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    panel.grid.major.x = element_blank(),
    panel.grid.minor = element_blank(),
    legend.position = "right",
    plot.title = element_text(face = "bold")
  )

out_p1 <- file.path("question_3_tlg", "ae_severity_by_treatment.png")
ggsave(out_p1, p_severity, width = 9, height = 6, dpi = 300)

# ------------------------------------------------------------------------------
# 3. Plot 2 - Top 10 adverse events with 95% Clopper-Pearson CIs
# ------------------------------------------------------------------------------

# Counting here is at SUBJECT level: distinct(USUBJID, AETERM) first, so a subject
# who reported pruritus five times counts once toward pruritus. An incidence rate
# is a proportion of subjects, so the numerator has to be subjects.
#
# Reading of the spec: "top 10 most frequent AEs with 95% CI for incidence rates"
# is taken as OVERALL incidence with the arms POOLED - one point estimate and one
# interval per adverse event, over all 254 treated subjects. A per-arm reading
# would give three intervals per term and answer a comparative question the spec
# does not ask. Pooling is also what makes "top 10" well defined: ranked by total
# subjects affected rather than by any one arm.

ae_subject_level <- teae %>%
  distinct(USUBJID, AETERM)

# Ties on the boundary count would otherwise make the tenth row depend on the
# input row order. Sorting by descending subject count and then alphabetically by
# term makes the cut deterministic and reproducible: exactly 10 rows, and the same
# 10 on every run. (In the current data the rank-10 count of 17 is shared by two
# terms, both of which fall inside the top 10, so nothing is dropped at the
# boundary - but the tiebreak is what guarantees that.)

top10 <- ae_subject_level %>%
  count(AETERM, name = "n_subj") %>%
  arrange(desc(n_subj), AETERM) %>%
  slice_head(n = 10)

# Clopper-Pearson is the exact binomial interval. stats::binom.test() computes it
# directly and is the established implementation - no hand-rolled interval, and no
# normal approximation, which would misbehave at the low incidences seen here.

cp_ci <- t(vapply(
  top10$n_subj,
  function(k) binom.test(x = k, n = n_treated, conf.level = 0.95)$conf.int,
  numeric(2)
))

top10 <- top10 %>%
  mutate(
    incidence_pct = 100 * n_subj / n_treated,
    ci_lower_pct  = 100 * cp_ci[, 1],
    ci_upper_pct  = 100 * cp_ci[, 2]
  )

# The y axis takes its level order from the sorted top10 rows rather than from
# reorder(): reorder() would rank by subject count alone and break the ties in
# its own way, so the three terms tied at 21 subjects and the two tied at 17
# would appear in the figure in a different order than in the validation output
# below. Reversing the sorted terms puts row 1 at the top of the axis, so the
# figure reads top to bottom exactly as the log reads down the page.

term_levels <- rev(top10$AETERM)

# Black point and capped error bars, the conventional look for a regulatory
# forest-style figure. Colour carries no information here - every row is the same
# kind of quantity - and black holds the thin interval lines against the white
# panel better than the Roche blue does, so this figure stays monochrome. Plot 1
# keeps the brand-anchored ramp, where lightness does encode something.
# geom_errorbar() with orientation = "y" rather than geom_errorbarh(), which is
# deprecated as of ggplot2 4.0.0 and would put a deprecation warning in the run
# log.

p_incidence <- ggplot(top10, aes(x = incidence_pct,
                                 y = factor(AETERM, levels = term_levels))) +
  geom_errorbar(aes(xmin = ci_lower_pct, xmax = ci_upper_pct),
                orientation = "y", width = 0.3,
                colour = "black", linewidth = 0.5) +
  geom_point(size = 2.4, colour = "black") +
  scale_x_continuous(
    limits = c(0, max(top10$ci_upper_pct) * 1.05),
    expand = expansion(mult = c(0, 0.02)),
    labels = function(x) paste0(x, "%")
  ) +
  labs(
    title = "Ten most frequent treatment-emergent adverse events",
    subtitle = paste0(
      "Subject incidence with 95% Clopper-Pearson exact binomial intervals\n",
      "All treatment arms pooled; Safety population, N = ", n_treated,
      " treated subjects"
    ),
    x = "Subjects affected (%)",
    y = NULL
  ) +
  theme_minimal(base_size = 12) +
  theme(
    panel.grid.major.y = element_blank(),
    panel.grid.minor = element_blank(),
    plot.title = element_text(face = "bold")
  )

out_p2 <- file.path("question_3_tlg", "ae_top10_incidence_ci.png")
ggsave(out_p2, p_incidence, width = 10, height = 6, dpi = 300)

# ------------------------------------------------------------------------------
# 4. Validation
# ------------------------------------------------------------------------------

cat("\n================ VALIDATION ================\n")

cat("\n[1] Population and TEAE subset\n")
cat("  Treated subjects (denominator):", n_treated,
    if (n_treated == 254L) " OK (expected 254)\n" else " MISMATCH (expected 254)\n")
cat("  Screen Failure excluded:",
    if (!"Screen Failure" %in% pop$ACTARM) "OK\n" else "FAILED - still present\n")

n_saffl <- sum(adsl$SAFFL == "Y", na.rm = TRUE)
cat("  Safety population, SAFFL == 'Y':", n_saffl,
    if (n_saffl == 254L) " OK (expected 254)\n" else " MISMATCH (expected 254)\n")
cat("  SAFFL population and the 3 treatment arms are the same subjects:",
    if (setequal(adsl$USUBJID[adsl$SAFFL == "Y"], pop$USUBJID)) "OK\n" else "FAILED\n")
cat("  TEAE records:", nrow(teae),
    if (nrow(teae) == 1122L) " OK (expected 1122)\n" else " MISMATCH (expected 1122)\n")
cat("  All TEAE subjects present in the denominator population:",
    if (all(teae$USUBJID %in% pop$USUBJID)) "OK\n" else "FAILED\n")

cat("\n[2] Plot 1 - AESEV x ACTARM record counts (the matrix behind the bars)\n")
sev_matrix <- with(
  teae,
  table(Severity = factor(AESEV, levels = SEV_LEVELS, ordered = TRUE),
        Arm = ACTARM, useNA = "ifany")
)
print(addmargins(sev_matrix))
cat("  Severity factor levels in order:", paste(SEV_LEVELS, collapse = " < "), "\n")
cat("  Records in matrix vs TEAE records:", sum(sev_matrix), "vs", nrow(teae),
    if (sum(sev_matrix) == nrow(teae)) " OK\n" else " MISMATCH\n")

cat("\n[3] Plot 2 - top 10 terms, subject counts, incidence and 95% CI\n")
print(
  top10 %>%
    mutate(
      n_of_N        = paste0(n_subj, "/", n_treated),
      incidence_pct = round(incidence_pct, 2),
      ci_lower_pct  = round(ci_lower_pct, 2),
      ci_upper_pct  = round(ci_upper_pct, 2)
    ) %>%
    select(AETERM, n_of_N, incidence_pct, ci_lower_pct, ci_upper_pct) %>%
    as.data.frame()
)
cat("  Rows selected:", nrow(top10),
    if (nrow(top10) == 10L) " OK (exactly 10)\n" else " MISMATCH\n")
cat("  Point estimate inside its own CI for every term:",
    if (all(top10$incidence_pct >= top10$ci_lower_pct &
            top10$incidence_pct <= top10$ci_upper_pct)) "OK\n" else "FAILED\n")
cat("  Subject counts strictly non-increasing (descending sort):",
    if (!is.unsorted(rev(top10$n_subj))) "OK\n" else "FAILED\n")

cat("\n[4] Output files\n")
for (f in c(out_p1, out_p2)) {
  ok <- file.exists(f) && file.size(f) > 0
  cat("  ", f, ": written =", file.exists(f),
      ", bytes =", if (file.exists(f)) file.size(f) else 0,
      if (ok) " OK\n" else " FAILED\n")
}

cat("\n============== END VALIDATION ==============\n\n")

sessionInfo()
