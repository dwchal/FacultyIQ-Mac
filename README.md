# FacultyIQ for Mac

A native macOS app for analyzing academic division research productivity — the
SwiftUI counterpart of the [FacultyIQ Shiny app](https://github.com/dwchal/FacultyIQ).

Import a faculty roster, resolve each member to an OpenAlex author, fetch their
publications and citation metrics, and explore division-level dashboards,
individual profiles, coauthorship networks, and promotion insights.

## Features

- **Roster import** — CSV with flexible header matching (handles survey-style
  headers like *"What is your current academic rank?"*). Columns: name
  (required), email, rank, division/department, hire/promotion dates, Scopus
  ID, Google Scholar ID, ORCID, associations. A built-in sample roster is
  included, and members can also be added or edited one at a time.
- **Identity resolution** — auto-resolve via ORCID or Scopus ID against
  OpenAlex, with a manual name-search picker (affiliation, works, citations,
  h-index shown per candidate) for the rest.
- **Metrics** — total works, citations, h-index, i10-index, citations/work,
  works/year, open-access share, recent 5-year output. Computed from OpenAlex
  data; h/i10 fall back to local computation from works when needed.
- **Dashboard** — KPI tiles plus charts: publications per year, citations
  received per year, OA share by year, most-cited faculty.
- **Faculty profiles** — per-person metric grid, promotion readiness card,
  publication trend, most-cited works with DOI links, links to OpenAlex/ORCID
  profiles.
- **Promotion insights** — per-rank medians plus a *promotion target* (the
  25th percentile of current rank-holders, since accumulated medians overstate
  the bar people actually cleared at promotion). Candidates meet the next
  rank's target on ≥ 2 of works / citations / h-index; a *Close to Promotion*
  section shows near-misses with per-metric gaps.
- **Coauthorship network** — a node-link graph of who publishes with whom
  inside the roster: nodes colored by academic rank and sized by output, edges
  weighted by shared works, with a minimum-weight filter and a per-member
  collaborator panel.
- **Divisions** — filter every analysis tab (and the exports) to one
  division/department from the toolbar; benchmarks and targets recompute
  within the selection.
- **Refresh** — a toolbar button on the analysis tabs resolves newly added
  members and fetches missing data in one click; editing a member's ORCID or
  Scopus ID safely invalidates their stale resolution and data.
- **Export** — faculty metrics, yearly time series, resolved roster, and the
  coauthorship edge list as CSV (respecting the division filter).
- **Sortable tables** — every table sorts by clicking column headers.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15+ command-line tools to build

No third-party dependencies — SwiftUI, Swift Charts, and Foundation only.

## Build & run

```bash
# Development run
swift run

# Build FacultyIQ.app (release, ad-hoc signed)
./scripts/build-app.sh
open build/FacultyIQ.app
```

Or open `Package.swift` in Xcode and run the FacultyIQ scheme.

## Tests

```bash
swift test                    # unit tests (CSV, roster mapping, metrics, network)
FACULTYIQ_LIVE=1 swift test   # + live OpenAlex API integration tests
```

Opt-in render tests write charts/graphs to PNG for visual inspection, e.g.
`RENDER_OUT=/tmp/net.png swift test --filter NetworkRenderTest`.

## Usage

1. **Roster** — import your CSV (or load the sample). Excel files: export to
   CSV first.
2. **Resolution** — click *Auto-Resolve All* (uses ORCID/Scopus IDs), then
   *Search…* for anyone left, then *Fetch Metrics*.
3. **Dashboard / Profiles / Promotion / Network** — explore; use the toolbar
   division picker to focus on one division.
4. **Export** — save CSVs.

Set your email in **Settings → OpenAlex** to join the
[polite pool](https://docs.openalex.org/how-to-use-the-api/rate-limits-and-authentication)
for faster rate limits.

## Privacy

Your roster stays on your Mac. All app state (roster, resolutions, fetched
data) lives in `~/Library/Application Support/FacultyIQ/` — outside this
repository — and roster emails are never sent to any API. The only network
traffic is OpenAlex lookups by author ID or name, cached locally for 7 days.
The `data/` directory in this repo ignores everything except the fictional
sample roster, so a real roster file placed there cannot be committed by
accident.

## Data sources

[OpenAlex](https://openalex.org) only. The Shiny app's optional Scopus/Google
Scholar/bibliometrix layers are not ported; OpenAlex covers profiles, works,
citations, counts-by-year, and OA status for free without keys.
