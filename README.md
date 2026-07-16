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
  received per year, OA share by year, most-cited faculty. Once the app has
  recorded snapshots on two different days, *Tracked History* charts show the
  cohort's observed works/citations movement across your own fetches.
- **What's New** — *Check for Updates* re-fetches everyone straight from
  OpenAlex (skipping the 7-day response cache) and reports what changed per
  member: new publications with links, citation and h-index movement. Changes
  accumulate across checks until you click *Mark Reviewed*.
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
- **Research topics** — what the division actually works on, from each work's
  OpenAlex primary topic: top topics (coauthored works counted once), decade
  trend lines for the leading topics, a sortable topic × field × faculty
  table, and each profile's top three topics.
- **Publications** — the shape of the division's output, from each work's
  OpenAlex metadata: publication-type breakdown (articles, reviews, book
  chapters, …) with decade trend lines, per-year open-access status
  composition (gold / hybrid / green / bronze / closed), a sortable venue ×
  works × citations × faculty table, and each profile's top work types.
- **Funding dashboard** — division-level rollup of the attached NIH grants:
  total awarded, funded faculty, active and R01-equivalent projects, awards by
  fiscal year and by activity code, and the most-funded faculty. Multi-PI
  projects shared by roster members count once in the totals. A *Timeline*
  view charts each PI's grant periods Gantt-style — today line, grants
  expiring within 12 months highlighted, periods approximated from fiscal
  years marked ≈ — with a toggle for recently ended grants.
- **Tracked history** — every fetch records a dated per-author snapshot of
  works, citations, and h-index (in `snapshots.json`, keyed by author so it
  survives roster re-imports). Dashboard and profile charts plot the observed
  movement — actual change between your fetches, not inferred trends.
- **Coauthorship network** — a node-link graph of who publishes with whom
  inside the roster: nodes colored by academic rank and sized by output, edges
  weighted by shared works, with a minimum-weight filter and a per-member
  collaborator panel.
- **External collaborators** — a sortable table of frequent coauthors from
  outside the roster, ranked by shared works, showing which roster members
  each one publishes with; affiliations and author metrics fetched on demand,
  plus a CSV export. Unresolved roster members are kept out of the list by
  ID and by a normalized name match. An Institutions view groups externals
  by affiliation — the strategic-partnership picture — with its own export.
  Any external can be added to the roster in one click (sidebar button or
  right-click), optionally straight to Emeritus: they're resolved to their
  known OpenAlex author and fetched immediately, then drop out of the
  externals list.
- **Member status** — mark people Active/Emeritus/Retired (member editor, or
  a "status" CSV column). Emeritus/retired members stay in the division views
  and off the externals list, but are excluded from promotion benchmarks and
  candidacy so they don't skew the bar for active faculty.
- **Work audit & exclusions** — OpenAlex author disambiguation isn't perfect;
  every profile has an Audit Works sheet where misattributed papers can be
  marked "not theirs" (persisted, survives refreshes) and drop out of every
  metric, chart, benchmark, and export. Works in fields the member has barely
  touched are flagged as review candidates.
- **Retraction flags** — works OpenAlex marks retracted are badged in
  profiles, listed on the Publications tab, and called out in the promotion
  dossier PDF before it goes anywhere.
- **Authorship positions** — first/middle/senior(last)/corresponding splits
  per member with a position-by-year chart: the first-author → senior-author
  transition at a glance.
- **Field benchmark** — one click samples a random OpenAlex cohort of authors
  on the member's dominant topic (≥10 works each) and shows the member's
  works/citations/h-index percentiles within it — external context the
  in-division benchmarks can't give.
- **Suggested collaborations** — the Network tab lists member pairs who
  publish on the same topics but have never co-published.
- **Automatic updates** — optional scheduled re-checks (daily/weekly/monthly)
  while the app is open, with a notification when What's New has changes.
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
  - **NIH iCite** — Relative Citation Ratio, NIH percentile, and Approximate
    Potential to Translate per PubMed-indexed work; mean RCR and mean APT per
    person; median RCR and APT plus a most-translational-faculty chart on the
    dashboard.
  - **NIH RePORTER** — grant funding per confirmed principal investigator
    (activity codes, fiscal years, total awards, R01-equivalent count); name
    matches are confirmed via a search sheet since PI search is fuzzy, and a
    wrongly attached grant can be removed from the profile — the removal is
    remembered, so no refresh or re-attach brings it back (with a Restore
    button to undo).
  - **Semantic Scholar** — influential-citation counts per work (shared
    keyless rate pool, so this source can be slow; a manual Semantic Scholar
    ID field is honored when set).
- **Sortable, searchable tables** — every table sorts by clicking column
  headers, and the people lists (Roster, Resolution, Faculty Profiles) have a
  search field filtering by name, rank, or division.

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
swift test                    # unit tests (CSV, roster mapping, metrics, trends, topics, funding, deltas, history, network, PDF)
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
3. **Dashboard / Profiles / Promotion / Topics / Network / External
   Collaborators** — explore; use the toolbar division picker to focus on one
   division.
4. **Enrich (optional)** — enable iCite / RePORTER / Semantic Scholar in
   **Settings → Data Enrichment**, then click *Enrich Data* in the toolbar;
   the Funding tab lights up once grants are attached.
5. **Export** — save CSVs, a division summary PDF, or a per-member promotion
   dossier PDF.
6. **Come back later** — *Check for Updates* on the What's New tab re-fetches
   everyone and shows what changed; each visit also extends the tracked
   history charts.

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
