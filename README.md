# FacultyIQ for Mac

A native macOS app for analyzing academic division research productivity — the
SwiftUI counterpart of the [FacultyIQ Shiny app](https://github.com/dwchal/FacultyIQ).

Import a faculty roster, resolve each member to an OpenAlex author, fetch their
publications and citation metrics, and explore division-level dashboards,
individual profiles, and promotion benchmarks.

## Features

- **Roster import** — CSV with flexible header matching (handles survey-style
  headers like *"What is your current academic rank?"*). Columns: name
  (required), email, rank, hire/promotion dates, Scopus ID, Google Scholar ID,
  ORCID, associations. A built-in sample roster is included.
- **Identity resolution** — auto-resolve via ORCID or Scopus ID against
  OpenAlex, with a manual name-search picker (affiliation, works, citations,
  h-index shown per candidate) for the rest.
- **Metrics** — total works, citations, h-index, i10-index, citations/work,
  works/year, open-access share, recent 5-year output. Computed from OpenAlex
  data; h/i10 fall back to local computation from works when needed.
- **Dashboard** — KPI tiles plus charts: publications per year, citations
  received per year, OA share by year, most-cited faculty.
- **Faculty profiles** — per-person metric grid, publication trend, most-cited
  works with DOI links, links to OpenAlex/ORCID profiles.
- **Promotion insights** — median benchmarks per academic rank, and candidates
  meeting the next rank's medians on ≥ 2 of works / citations / h-index.
- **Export** — faculty metrics, yearly time series, and resolved roster as CSV.
- **Privacy & caching** — roster emails are never sent to any API; all OpenAlex
  responses are cached for 7 days in `~/Library/Application Support/FacultyIQ/`.

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
swift test                    # unit tests (CSV, roster mapping, metrics)
FACULTYIQ_LIVE=1 swift test   # + live OpenAlex API integration tests
```

## Usage

1. **Roster** — import your CSV (or load the sample). Excel files: export to
   CSV first.
2. **Resolution** — click *Auto-Resolve All* (uses ORCID/Scopus IDs), then
   *Search…* for anyone left, then *Fetch Metrics*.
3. **Dashboard / Profiles / Promotion** — explore.
4. **Export** — save CSVs.

Set your email in **Settings → OpenAlex** to join the
[polite pool](https://docs.openalex.org/how-to-use-the-api/rate-limits-and-authentication)
for faster rate limits.

## Data sources

[OpenAlex](https://openalex.org) only. The Shiny app's optional Scopus/Google
Scholar/bibliometrix layers are not ported; OpenAlex covers profiles, works,
citations, counts-by-year, and OA status for free without keys.
