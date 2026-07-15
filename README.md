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
  ID, Google Scholar ID, ORCID, Semantic Scholar ID, associations. A built-in
  sample roster is included, and members can also be added or edited one at a
  time.
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
  profiles. A works sparkline and growth arrow next to each name in the list.
- **Trends & trajectory** — recent-vs-prior 3-year growth in works and
  citations, a cumulative-works projection to the next rank's target at the
  current 5-year pace, and a career-normalized comparison (cumulative works by
  years since first publication, against the cohort median).
- **Promotion insights** — per-rank medians plus a *promotion target* (the
  25th percentile of current rank-holders, since accumulated medians overstate
  the bar people actually cleared at promotion). Candidates meet the next
  rank's target on ≥ 2 of works / citations / h-index; a *Close to Promotion*
  section shows near-misses with per-metric gaps, time-to-target pace
  estimates, and a nearest-rank prediction chip (a port of the Shiny app's
  weighted rank-distance model).
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
- **Export** — faculty metrics, yearly time series, resolved roster, NIH
  grants, and the coauthorship edge list as CSV (respecting the division
  filter).
- **PDF reports** — a per-faculty *Promotion Dossier* (header, metric grid,
  readiness bars, publication chart, paginated most-cited-works table) and a
  two-page *Division Summary* (KPIs, all four dashboard charts, rank
  benchmarks), rendered as vector PDFs with selectable text.
- **Data enrichment (optional)** — free, keyless sources toggled in Settings
  and fetched with the *Enrich Data* toolbar button:
  - **NIH iCite** — Relative Citation Ratio and NIH percentile per
    PubMed-indexed work, mean RCR per person, median RCR on the dashboard.
  - **NIH RePORTER** — grant funding per confirmed principal investigator
    (activity codes, fiscal years, total awards, R01-equivalent count); name
    matches are confirmed via a search sheet since PI search is fuzzy.
  - **Semantic Scholar** — influential-citation counts per work (shared
    keyless rate pool, so this source can be slow; a manual Semantic Scholar
    ID field is honored when set).
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
swift test                    # unit tests (CSV, roster mapping, metrics, trends, network, PDF)
FACULTYIQ_LIVE=1 swift test   # + live API tests (OpenAlex, iCite, RePORTER, Semantic Scholar)
```

Opt-in render tests write charts/graphs to PNG (and the report pages to PDF)
for visual inspection, e.g. `RENDER_OUT=/tmp/net.png swift test --filter
NetworkRenderTest` or `RENDER_OUT=/tmp swift test --filter PDFRenderTest`.

## Usage

1. **Roster** — import your CSV (or load the sample). Excel files: export to
   CSV first.
2. **Resolution** — click *Auto-Resolve All* (uses ORCID/Scopus IDs), then
   *Search…* for anyone left, then *Fetch Metrics*.
3. **Dashboard / Profiles / Promotion / Network** — explore; use the toolbar
   division picker to focus on one division.
4. **Enrich (optional)** — enable iCite / RePORTER / Semantic Scholar in
   **Settings → Data Enrichment**, then click *Enrich Data* in the toolbar.
5. **Export** — save CSVs, a division summary PDF, or a per-member promotion
   dossier PDF.

Set your email in **Settings → OpenAlex** to join the
[polite pool](https://docs.openalex.org/how-to-use-the-api/rate-limits-and-authentication)
for faster rate limits.

## Privacy

Your roster stays on your Mac. All app state (roster, resolutions, fetched
data, enrichment) lives in `~/Library/Application Support/FacultyIQ/` —
outside this repository — and roster emails are never sent to any API. Network
traffic is limited to OpenAlex lookups by author ID or name plus, when the
optional enrichment sources are enabled, PMID/DOI/name lookups against NIH
iCite, NIH RePORTER, and Semantic Scholar; everything is cached locally for
7 days. The `data/` directory in this repo ignores everything except the
fictional sample roster, so a real roster file placed there cannot be
committed by accident.

## Data sources

[OpenAlex](https://openalex.org) is the primary source: profiles, works,
citations, counts-by-year, OA status, and PMIDs, free without keys. Optional
enrichment adds [NIH iCite](https://icite.od.nih.gov) (RCR / NIH percentile),
[NIH RePORTER](https://reporter.nih.gov) (grants), and
[Semantic Scholar](https://www.semanticscholar.org) (influential citations) —
all keyless. The Shiny app's Scopus/Google Scholar/bibliometrix layers are not
ported (paid keys or no API).
