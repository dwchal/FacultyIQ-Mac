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
  ID, Google Scholar ID, ORCID, Semantic Scholar ID, associations, notes. A built-in
  sample roster is included, and members can also be added or edited one at a
  time.
- **Identity resolution** — auto-resolve via ORCID or Scopus ID against
  OpenAlex, with a manual name-search picker (affiliation, works, citations,
  h-index shown per candidate) for the rest.
- **Metrics** — total works, citations, h-index, i10-index, citations/work,
  works/year, open-access share, recent 5-year output. Computed from OpenAlex
  data; h/i10 fall back to local computation from works when needed.
- **Dashboard** — KPI tiles plus charts: publications per year, citations
  received per year (the always-partial current year is shown to date with a
  prorated full-year pace marker instead of a misleading dip), OA share by
  year, most-cited faculty. Once the app has recorded snapshots on two
  different days, *Tracked History* charts show the cohort's observed
  works/citations movement across your own fetches.
- **What's New** — *Check for Updates* re-fetches everyone straight from
  OpenAlex (skipping the 7-day response cache) and reports what changed per
  member: new publications with links, citation and h-index movement. Changes
  accumulate across checks until you click *Mark Reviewed*. A *Between Dates*
  mode diffs the tracked history between any two dates — per-member works,
  citation, and h-index deltas over an annual-review period — with a one-page
  *Year in Review* PDF.
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
  works × citations × faculty table, and each profile's top work types. With
  Scopus enabled, a *Journal Quality* card shows the cohort's CiteScore
  quartile distribution (% of publications in Q1 venues) and the venue table
  gains sortable CiteScore / SJR / quartile columns.
- **Journal quality without a key** — journal metrics come from the OpenAlex
  sources index (2-year mean citedness, h-index per venue) with no API key,
  so the *Journal Quality* card and the venue table's impact/quartile columns
  work out of the box. Scopus upgrades individual journals wherever it has a
  CiteScore, since its quartiles are absolute; the OpenAlex quartiles are
  relative to the venues the cohort actually publishes in, and are labeled as
  such. Metrics join on the venue's linking ISSN, so works fetched before
  ISSNs were tracked need a *Refresh All Works* first — the card says so, with
  a button, rather than rendering empty.
- **Preprints** — OpenAlex indexes a bioRxiv/medRxiv/arXiv posting and its
  eventual journal article as two separate works, which double-counts the
  paper and puts a phantom point on the publications-per-year chart. Preprints
  are matched to their published version by normalized title and dropped from
  the metrics (toggleable in Settings); both stay visible on the Publications
  tab, where a *Preprints* card reports how many were published, how many are
  preprint-only, and which have sat unpublished for 2+ years — the follow-up
  list. Matching is deliberately conservative: a retitled preprint reads as
  unpublished rather than risking a false pair that would delete a real paper
  from the counts.
- **Compare Faculty** — pick 2–4 members for a side-by-side metrics grid
  (works, citations, h-index incl. Scopus, authorship positions, RCR, Q1
  share, NIH funding, trials), best value bolded, with division rank-medians
  for context — exportable as a one-page PDF for committee meetings.
- **Funding dashboard** — division-level rollup of the attached NIH grants:
  total awarded, funded faculty, active and R01-equivalent projects, awards by
  fiscal year and by activity code, and the most-funded faculty. Multi-PI
  projects shared by roster members count once in the totals. A *Timeline*
  view charts each PI's grant periods Gantt-style — today line, grants
  expiring within 12 months highlighted, periods approximated from fiscal
  years marked ≈ — with a toggle for recently ended grants.
- **Funding cliffs** — the actionable half of the funding picture: members
  whose *last* award ends within 12 months with nothing running past it,
  soonest first, on the Funding tab and again in What's New (where it shows up
  even when no publications changed). Any award covering the gap clears the
  flag, NIH or NSF; already-expired and well-funded members never appear, so
  the list stays short enough to act on. Exportable as CSV.
- **Non-NIH funding** — NSF awards (PI and co-PI, keyless, name-matched and
  verified client-side) get their own rollup and profile card, and feed the
  cliff calculation alongside NIH. Separately, a *Funders* tab reads the
  funder credits recorded on the publications themselves — every agency and
  foundation at once, with no name matching involved, answering "who funds
  this cohort" for sources neither RePORTER nor NSF covers.
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
  touched are flagged as review candidates. With Scopus enabled, a
  cross-check diffs the member's Scopus document list against OpenAlex by DOI
  in both directions: works missing from OpenAlex, and OpenAlex-only works
  that are misattribution candidates.
- **Review notes** — a free-text notes field and a *last reviewed* stamp per
  member, on the profile and in the member editor. Notes save as you type,
  are searchable from the faculty lists, ride along in the workspace archive
  and the roster CSV, and are never sent to any API — the part of a profile
  that isn't derived from a database.
- **Scheduled reports** — point Settings → Reports at a folder and FacultyIQ
  writes a dated Division Summary or Year in Review PDF on a weekly, monthly,
  or quarterly cadence while the app is open, covering the whole roster
  regardless of the division filter in the window. Existing files are never
  overwritten; each run adds a new dated file.
- **Workspace archive** — one-click export of the entire workspace (roster,
  resolutions, fetched works, enrichment, notes, and metric history) to a
  single JSON file, with a confirming import to restore it. For backups,
  moving to another Mac, or handing the dataset to a colleague. The API
  response cache is left out — it re-fetches on its own and is the bulk of the
  size.
- **Data health** — the Resolution tab flags members missing ORCID or Scopus
  IDs (and anyone unresolved), plus works without a DOI or PMID that
  therefore can't join the DOI/PMID-keyed enrichment sources — with
  per-member shortcuts to fix each gap.
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
- **Export** — faculty metrics (including Scopus, journal-quality, NSF, and
  clinical-trial columns), yearly time series, resolved roster (with notes and
  review dates), NIH grants, NSF awards, funding cliffs, funders, and the
  coauthorship edge list as CSV (respecting the division filter).
- **PDF reports** — a per-faculty *Promotion Dossier* (header, metric grid,
  readiness bars, publication chart, paginated most-cited-works table, plus
  Scopus/RCR/funding/trials summary lines), a two-page *Division Summary*
  (KPIs, all four dashboard charts, rank benchmarks, Scopus rollup), the
  *Faculty Comparison* sheet, and the *Year in Review* diff — rendered as
  vector PDFs with selectable text.
- **Data enrichment (optional)** — sources toggled in **Settings → Data
  Sources** and fetched with the *Enrich Data* toolbar button:
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
  - **NSF Awards** — awards where the member is PI or co-PI (program, project
    period, total award), keyless. NSF publishes no investigator IDs, so the
    server-side name query is re-verified client-side against both the PI and
    co-PI fields; the profile card lists the awards for eyeballing.
  - **OpenAlex journal metrics** — 2-year mean citedness and h-index for every
    venue the cohort publishes in, keyless and on by default; fetched once per
    workspace rather than per member, since journals are shared across the
    roster.
  - **Semantic Scholar** — influential-citation counts per work (shared
    keyless rate pool, so this source can be slow; a manual Semantic Scholar
    ID field is honored when set).
  - **ClinicalTrials.gov** — registered trials where the member is an overall
    official (PI / study chair / study director), keyless, conservatively
    name-matched: a trials card on each profile and a division rollup on the
    Funding tab.
  - **Scopus (Elsevier)** — the one keyed source: official Scopus h-index,
    document, and citation counts per member (shown next to the OpenAlex
    numbers, since promotion packets usually quote Scopus), plus
    CiteScore/SNIP/SJR journal quality per publication via the Serial Title
    API. Keys are free from [dev.elsevier.com](https://dev.elsevier.com) but
    are authorized by the institution's IP range — calls only work on the
    institutional network or VPN (or with an Elsevier-issued insttoken).
    Members without a Scopus ID get a confirm-before-attach author search
    that also writes the ID back to the roster.
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
swift test                    # unit tests (CSV, roster mapping, metrics, trends, topics, funding, deltas, history, network, PDF, Scopus/trials fixtures)
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
4. **Enrich (optional)** — enable iCite / RePORTER / Semantic Scholar /
   ClinicalTrials.gov / Scopus in **Settings → Data Sources** (Scopus also
   needs your API key, and works only on the institutional network or VPN),
   then click *Enrich Data* in the toolbar; the Funding tab lights up once
   grants are attached. For Scopus journal-quality metrics on data fetched
   before Scopus support existed, run *Refresh All Works* first so works
   carry their venue ISSNs.
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
traffic is limited to OpenAlex lookups by author ID, name, or journal ISSN
plus, when the optional enrichment sources are enabled, PMID/DOI/name/ID
lookups against NIH iCite, NIH RePORTER, NSF Awards, Semantic Scholar,
ClinicalTrials.gov, and Elsevier's Scopus APIs; everything is cached locally
for 7 days. Review notes stay on your Mac and are never sent anywhere. The Scopus API key is
stored in the app's preferences on your Mac and sent only to api.elsevier.com.
The `data/` directory in this repo ignores everything except the fictional
sample roster, so a real roster file placed there cannot be committed by
accident.

## Data sources

[OpenAlex](https://openalex.org) is the primary source: profiles, works,
citations, counts-by-year, OA status, PMIDs, venue ISSNs, funder credits, and
journal metrics from its sources index — free without keys. Optional
enrichment adds [NIH iCite](https://icite.od.nih.gov) (RCR / NIH percentile),
[NIH RePORTER](https://reporter.nih.gov) (grants),
[NSF Awards](https://www.nsf.gov/awardsearch/) (grants),
[Semantic Scholar](https://www.semanticscholar.org) (influential citations),
and [ClinicalTrials.gov](https://clinicaltrials.gov) (registered trials) —
all keyless — plus [Scopus](https://dev.elsevier.com) (author metrics and
CiteScore/SNIP/SJR journal quality) with a free but institution-bound
Elsevier API key. The Shiny app's Google Scholar/bibliometrix layers are not
ported (no API).
