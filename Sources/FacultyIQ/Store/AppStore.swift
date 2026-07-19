import Foundation
import SwiftUI
@preconcurrency import UserNotifications

/// Central app state: roster, identity resolutions, fetched data, and the
/// async workflow operations. Persists itself as JSON in Application Support.
@MainActor
final class AppStore: ObservableObject {
    @Published var roster: [FacultyMember] = []
    @Published var resolutions: [UUID: Resolution] = [:]
    @Published var personData: [UUID: PersonData] = [:]
    @Published var enrichment: [UUID: Enrichment] = [:]

    /// Works the user marked "not this member's" — misattributed by OpenAlex
    /// disambiguation. Kept out of every metric but still listed (flagged) in
    /// Publications so the exclusion can be undone.
    @Published var excludedWorks: [UUID: Set<String>] = [:]

    /// Accumulated per-member changes from re-fetches, until reviewed.
    @Published var deltas: [UUID: RefreshDelta] = [:]
    @Published var lastUpdateCheck: Date?

    /// Dated metric readings appended at fetch time; see SnapshotStore.
    @Published private(set) var snapshots: [MetricSnapshot] = []

    /// Restricts every analysis tab (dashboard, profiles, promotion, network,
    /// export) to one division; nil shows everyone. Session-only, not persisted.
    @Published var divisionFilter: String? = nil {
        didSet { invalidateDerived() }
    }

    @Published var isBusy = false
    @Published var progressText = ""
    @Published var progress: Double? = nil   // 0...1 while a batch runs
    @Published var lastError: String?

    // MARK: Cross-view navigation

    /// Presents the global Find Faculty sheet (Go → Find Faculty…, ⌘F).
    @Published var showFacultySearch = false
    /// A member the Profiles tab should select on next appearance — set by
    /// the Find Faculty sheet, consumed (and cleared) by ProfilesView.
    @Published var profileFocusID: UUID?
    /// Sidebar tab a background event wants opened (e.g. clicking the
    /// What's New notification) — consumed and cleared by ContentView.
    @Published var pendingSidebarTarget: SidebarItem?

    private let client = OpenAlexClient.shared
    private let notificationDelegate = NotificationDelegate()

    init() {
        load()
        snapshots = SnapshotStore.load()
        // Clicking the What's New notification should land on What's New.
        // No notification center exists under `swift run` (no app bundle).
        if Bundle.main.bundleIdentifier != nil {
            notificationDelegate.onOpenWhatsNew = { [weak self] in
                self?.pendingSidebarTarget = .whatsNew
            }
            UNUserNotificationCenter.current().delegate = notificationDelegate
        }
    }

    // MARK: Derived state

    /// Memoized derived values. Every data mutation funnels through save()
    /// (and divisionFilter's didSet), which clears this — so the expensive
    /// aggregations run once per data change instead of once per view update.
    private var derived = DerivedCache()

    private struct DerivedCache {
        var effectivePersonData: [UUID: PersonData]?
        var metrics: [PersonMetrics]?
        var coauthorNetwork: CoauthorNetwork?
        var mentorshipEdges: [MentorshipEdge]?
        var externalCollaborators: [ExternalCollaborator]?
    }

    func invalidateDerived() {
        derived = DerivedCache()
    }

    /// Distinct divisions present in the roster, sorted.
    var divisions: [String] {
        Array(Set(roster.compactMap(\.division))).sorted()
    }

    /// The roster as the analysis tabs see it: everyone, or one division.
    var filteredRoster: [FacultyMember] {
        guard let filter = divisionFilter, divisions.contains(filter) else { return roster }
        return roster.filter { $0.division == filter }
    }

    /// personData with each member's excluded works removed and headline
    /// counts adjusted — what every metric and chart should consume. Raw
    /// personData remains the source for the Publications list, where
    /// excluded works stay visible so the exclusion can be undone.
    var effectivePersonData: [UUID: PersonData] {
        if let cached = derived.effectivePersonData { return cached }
        let result = Dictionary(uniqueKeysWithValues: personData.map { id, data in
            (id, MetricsEngine.applyingExclusions(data, excluded: excludedWorks[id] ?? []))
        })
        derived.effectivePersonData = result
        return result
    }

    /// One member's data with exclusions applied.
    func effectiveData(for memberID: UUID) -> PersonData? {
        effectivePersonData[memberID]
    }

    var filteredPersonData: [PersonData] {
        filteredRoster.compactMap { effectivePersonData[$0.id] }
    }

    var metrics: [PersonMetrics] {
        if let cached = derived.metrics { return cached }
        let result = MetricsEngine.allMetrics(roster: filteredRoster, personData: effectivePersonData)
        derived.metrics = result
        return result
    }

    var summary: DivisionSummary {
        MetricsEngine.divisionSummary(
            roster: filteredRoster,
            resolvedCount: filteredRoster.count { resolutions[$0.id] != nil },
            metrics: metrics)
    }

    /// Metrics for members on the promotion track — emeritus/retired members
    /// stay in the division views but out of benchmarks and candidacy.
    var activeMetrics: [PersonMetrics] {
        let active = Set(filteredRoster.filter(\.isActive).map(\.id))
        return metrics.filter { active.contains($0.memberID) }
    }

    var benchmarks: [RankBenchmark] {
        MetricsEngine.rankBenchmarks(metrics: activeMetrics)
    }

    var promotionCandidates: [PromotionCandidate] {
        MetricsEngine.promotionCandidates(metrics: activeMetrics, benchmarks: benchmarks)
    }

    var promotionProgress: [PromotionProgress] {
        MetricsEngine.promotionProgress(metrics: activeMetrics, benchmarks: benchmarks)
    }

    var coauthorNetwork: CoauthorNetwork {
        if let cached = derived.coauthorNetwork { return cached }
        let result = MetricsEngine.coauthorNetwork(
            roster: filteredRoster, resolutions: resolutions, personData: effectivePersonData)
        derived.coauthorNetwork = result
        return result
    }

    /// Directed mentor→mentee pairs (last author over a first author) within
    /// the division in view.
    var mentorshipEdges: [MentorshipEdge] {
        if let cached = derived.mentorshipEdges { return cached }
        let result = MetricsEngine.mentorshipEdges(
            roster: filteredRoster, resolutions: resolutions, personData: effectivePersonData)
        derived.mentorshipEdges = result
        return result
    }

    /// Frequent non-roster coauthors, computed from cached works. Exclusions
    /// consider the full roster so other divisions never appear as external.
    var externalCollaborators: [ExternalCollaborator] {
        if let cached = derived.externalCollaborators { return cached }
        let result = MetricsEngine.externalCollaborators(
            roster: filteredRoster, fullRoster: roster,
            resolutions: resolutions, personData: effectivePersonData)
        derived.externalCollaborators = result
        return result
    }

    /// Promote an external collaborator to a roster member: add them,
    /// resolve them to their already-known OpenAlex ID, and fetch their
    /// data. Once resolved they drop out of the externals list on their own.
    /// Rank/division start empty — edit them on the Roster tab.
    func addToRoster(external: ExternalCollaborator, status: MemberStatus? = nil) async {
        guard !roster.contains(where: { resolutions[$0.id]?.openalexID == external.openalexID })
        else { return }
        let details = externalAuthorDetails[external.openalexID]
        var member = FacultyMember(name: details?.displayName ?? external.displayName)
        member.status = status
        member.orcid = details?.orcid.map(RosterImporter.cleanORCID)
        roster.append(member)
        resolutions[member.id] = Resolution(
            openalexID: external.openalexID,
            displayName: details?.displayName ?? external.displayName,
            method: .manual,
            affiliation: details?.affiliation,
            orcid: details?.orcid)
        save()
        await runBatch(label: "Fetching", items: [member]) { member in
            try await self.fetchOne(member)
        }
    }

    // MARK: Work exclusion

    func isWorkExcluded(_ workID: String, for memberID: UUID) -> Bool {
        excludedWorks[memberID]?.contains(workID) ?? false
    }

    /// Toggle "not this member's paper". The work stays visible in
    /// Publications but leaves every metric.
    func setWorkExcluded(_ workID: String, for memberID: UUID, excluded: Bool) {
        var set = excludedWorks[memberID] ?? []
        if excluded { set.insert(workID) } else { set.remove(workID) }
        excludedWorks[memberID] = set.isEmpty ? nil : set
        save()
    }

    /// Author details (affiliation, h-index) for external collaborators,
    /// fetched on demand. Session-only; the HTTP layer caches to disk anyway.
    @Published var externalAuthorDetails: [String: AuthorCandidate] = [:]

    /// Fill in externalAuthorDetails for the given author IDs.
    func fetchExternalAuthorDetails(ids: [String]) async {
        let missing = ids.filter { externalAuthorDetails[$0] == nil }
        guard !missing.isEmpty, !isBusy else { return }
        isBusy = true
        defer {
            progress = nil
            progressText = ""
            isBusy = false
        }
        do {
            for start in stride(from: 0, to: missing.count, by: 50) {
                progress = Double(start) / Double(missing.count)
                progressText = "Fetching collaborator details (\(start + 1)–\(min(start + 50, missing.count)) of \(missing.count))…"
                let chunk = Array(missing[start..<min(start + 50, missing.count)])
                for author in try await client.authors(ids: chunk) {
                    externalAuthorDetails[author.openalexID] = author
                }
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func resolution(for member: FacultyMember) -> Resolution? {
        resolutions[member.id]
    }

    /// Members whose data the next refreshData() call would bring up to date:
    /// unresolved with an ORCID/Scopus ID, or resolved but not yet fetched.
    var pendingRefreshCount: Int {
        roster.count { member in
            if resolutions[member.id] == nil {
                member.orcid != nil || member.scopusID != nil
            } else {
                personData[member.id] == nil
            }
        }
    }

    // MARK: Roster

    func importRoster(from url: URL) {
        do {
            let members = try RosterImporter.importRoster(from: url)
            replaceRoster(with: members)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func loadSampleRoster() {
        guard let members = try? RosterImporter.importRoster(fromText: sampleRosterCSV) else { return }
        replaceRoster(with: members)
    }

    private func replaceRoster(with members: [FacultyMember]) {
        roster = members
        // Keep resolutions/data only makes sense per-roster; new roster resets them.
        resolutions = [:]
        personData = [:]
        enrichment = [:]
        deltas = [:]
        excludedWorks = [:]
        divisionFilter = nil
        lastError = nil
        save()
    }

    func addMember(_ member: FacultyMember) {
        roster.append(member)
        save()
    }

    func updateMember(_ member: FacultyMember) {
        guard let index = roster.firstIndex(where: { $0.id == member.id }) else { return }
        let old = roster[index]
        roster[index] = member
        // A changed ORCID or Scopus ID means the member may resolve to a
        // different author, so the old resolution and data no longer apply.
        if old.orcid != member.orcid || old.scopusID != member.scopusID {
            resolutions[member.id] = nil
            personData[member.id] = nil
            enrichment[member.id] = nil
            deltas[member.id] = nil
            excludedWorks[member.id] = nil
        }
        save()
    }

    func removeMembers(_ ids: Set<UUID>) {
        roster.removeAll { ids.contains($0.id) }
        for id in ids {
            resolutions[id] = nil
            personData[id] = nil
            enrichment[id] = nil
            deltas[id] = nil
            excludedWorks[id] = nil
        }
        save()
    }

    func clearAll() {
        roster = []
        resolutions = [:]
        personData = [:]
        enrichment = [:]
        deltas = [:]
        excludedWorks = [:]
        divisionFilter = nil
        save()
    }

    // MARK: Resolution

    /// Resolve every member that has an ORCID or Scopus ID and isn't resolved yet.
    func autoResolveAll() async {
        let pending = roster.filter { resolutions[$0.id] == nil && ($0.orcid != nil || $0.scopusID != nil) }
        guard !pending.isEmpty else { return }
        await runBatch(label: "Resolving", items: pending) { member in
            try await self.autoResolve(member)
        }
    }

    private func autoResolve(_ member: FacultyMember) async throws {
        var candidate: AuthorCandidate?
        var method = ResolutionMethod.orcid
        if let orcid = member.orcid {
            candidate = try await client.authorByORCID(orcid)
        }
        if candidate == nil, let scopus = member.scopusID {
            candidate = try await client.authorByScopus(scopus)
            method = .scopus
        }
        if let candidate {
            resolve(member, with: candidate, method: method)
        }
    }

    func resolve(_ member: FacultyMember, with candidate: AuthorCandidate, method: ResolutionMethod) {
        // The member may have been deleted while a search sheet was open;
        // resolving them anyway would orphan a resolutions entry.
        guard roster.contains(where: { $0.id == member.id }) else { return }
        // Data fetched for a previously resolved author doesn't carry over.
        if resolutions[member.id]?.openalexID != candidate.openalexID {
            personData[member.id] = nil
            enrichment[member.id] = nil
            deltas[member.id] = nil
            excludedWorks[member.id] = nil
        }
        resolutions[member.id] = Resolution(
            openalexID: candidate.openalexID,
            displayName: candidate.displayName,
            method: method,
            affiliation: candidate.affiliation,
            orcid: candidate.orcid
        )
        save()
    }

    func unresolve(_ member: FacultyMember) {
        resolutions[member.id] = nil
        personData[member.id] = nil
        enrichment[member.id] = nil
        deltas[member.id] = nil
        excludedWorks[member.id] = nil
        save()
    }

    func searchAuthors(name: String) async -> [AuthorCandidate] {
        do {
            return try await client.searchAuthors(name: name)
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    // MARK: Fetch

    /// Catch up after roster or resolution edits: auto-resolve members that
    /// gained an ORCID/Scopus ID, then fetch data for anyone missing it.
    func refreshData() async {
        await autoResolveAll()
        await fetchAll()
    }

    /// Fetch profile + works for every resolved member without data.
    func fetchAll(refresh: Bool = false) async {
        let pending = roster.filter { member in
            resolutions[member.id] != nil && (refresh || personData[member.id] == nil)
        }
        guard !pending.isEmpty else { return }
        await runBatch(label: "Fetching", items: pending) { member in
            try await self.fetchOne(member)
        }
    }

    func fetchOne(_ member: FacultyMember, bypassCache: Bool = false) async throws {
        guard let resolution = resolutions[member.id] else { return }
        let profile = try await client.author(id: resolution.openalexID, bypassCache: bypassCache)
        let works = try await client.works(authorID: resolution.openalexID, bypassCache: bypassCache)
        let new = PersonData(profile: profile, works: works, fetchedAt: Date())
        if let old = personData[member.id] {
            let delta = MetricsEngine.refreshDelta(old: old, new: new,
                                                   accumulating: deltas[member.id])
            deltas[member.id] = delta.hasChanges ? delta : nil
        }
        personData[member.id] = new
        recordSnapshot(new)
        save()
    }

    /// Append a history reading unless nothing moved since the author's last one.
    private func recordSnapshot(_ data: PersonData) {
        let snapshot = MetricSnapshot(
            date: data.fetchedAt,
            openalexID: data.profile.openalexID,
            name: data.profile.displayName,
            works: MetricsEngine.effectiveWorksCount(data),
            citations: MetricsEngine.effectiveCitations(data),
            hIndex: MetricsEngine.effectiveHIndex(data))
        if let last = snapshots.last(where: { $0.openalexID == snapshot.openalexID }),
           (last.works, last.citations, last.hIndex)
               == (snapshot.works, snapshot.citations, snapshot.hIndex) {
            return
        }
        snapshots.append(snapshot)
        SnapshotStore.save(snapshots)
    }

    func clearSnapshots() {
        snapshots = []
        SnapshotStore.save(snapshots)
    }

    // MARK: What's new

    /// Re-fetch everyone who already has data, straight from OpenAlex (the
    /// 7-day response cache would otherwise hand back the same data), and
    /// record what changed. Deltas accumulate until cleared via markReviewed().
    func checkForUpdates() async {
        let members = roster.filter { resolutions[$0.id] != nil && personData[$0.id] != nil }
        guard !members.isEmpty else { return }
        await runBatch(label: "Checking", items: members) { member in
            try await self.fetchOne(member, bypassCache: true)
        }
        lastUpdateCheck = Date()
        save()
    }

    // MARK: Scheduled refresh

    /// When switched on in Settings, re-check OpenAlex once the configured
    /// interval has elapsed since the last check. Called at launch and on an
    /// hourly heartbeat, so leaving the app running is enough.
    func autoCheckIfDue() async {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "autoCheckEnabled"), !isBusy, !personData.isEmpty else { return }
        let days = max(defaults.integer(forKey: "autoCheckIntervalDays"), 1)
        if let last = lastUpdateCheck,
           Date().timeIntervalSince(last) < Double(days) * 86_400 {
            return
        }
        await checkForUpdates()
        notifyAboutDeltas()
    }

    /// Post a user notification summarizing unreviewed changes. Silently does
    /// nothing under `swift run`, where there is no app bundle to notify from.
    private func notifyAboutDeltas() {
        guard !deltas.isEmpty, Bundle.main.bundleIdentifier != nil else { return }
        let changed = deltas.count
        let newWorks = deltas.values.map(\.newWorkIDs.count).reduce(0, +)
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .badge]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "FacultyIQ found new activity"
            content.body = newWorks > 0
                ? "\(newWorks) new works across \(changed) members — review them in What's New."
                : "Metrics moved for \(changed) members — review them in What's New."
            center.add(UNNotificationRequest(
                identifier: "facultyiq.whatsnew", content: content, trigger: nil))
        }
    }

    /// Clear the accumulated deltas: the next check diffs against today's data.
    func markReviewed() {
        deltas = [:]
        save()
    }

    /// The works a delta's IDs refer to, resolved against the member's
    /// current data, newest first.
    func newWorks(for memberID: UUID) -> [Work] {
        guard let delta = deltas[memberID], let data = personData[memberID] else { return [] }
        let ids = Set(delta.newWorkIDs)
        return data.works.filter { ids.contains($0.id) }
            .sorted { ($0.year ?? 0, $0.citedByCount) > (($1.year ?? 0), $1.citedByCount) }
    }

    // MARK: Enrichment

    enum AppError: LocalizedError {
        case needsScopusID

        var errorDescription: String? {
            switch self {
            case .needsScopusID:
                "no Scopus ID on the roster — use Find Scopus Author on the member's profile."
            }
        }
    }

    /// Which enrichment sources the user has switched on in Settings.
    var enabledEnrichmentSources: (icite: Bool, reporter: Bool, semanticScholar: Bool, scopus: Bool, trials: Bool) {
        let defaults = UserDefaults.standard
        let scopusKey = defaults.string(forKey: "scopusAPIKey")?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return (defaults.bool(forKey: "enableICite"),
                defaults.bool(forKey: "enableReporter"),
                defaults.bool(forKey: "enableSemanticScholar"),
                defaults.bool(forKey: "enableScopus") && !scopusKey.isEmpty,
                defaults.bool(forKey: "enableTrials"))
    }

    var anyEnrichmentEnabled: Bool {
        let sources = enabledEnrichmentSources
        return sources.icite || sources.reporter || sources.semanticScholar
            || sources.scopus || sources.trials
    }

    /// Opt-in second phase after the OpenAlex fetch: pull iCite citation
    /// metrics, NIH grants, and Semantic Scholar stats for every member with
    /// data, per the Settings toggles. Skips members already enriched unless
    /// `refresh` is set.
    func enrichAll(refresh: Bool = false) async {
        let sources = enabledEnrichmentSources
        let members = roster.filter { personData[$0.id] != nil }
        guard anyEnrichmentEnabled, !members.isEmpty else { return }

        if sources.icite {
            let pending = members.filter { refresh || enrichment[$0.id]?.icite == nil }
            await runBatch(label: "Enriching (iCite)", items: pending) { member in
                try await self.enrichICite(member)
            }
        }
        if sources.reporter {
            let pending = members.filter { refresh || enrichment[$0.id]?.grants == nil }
            await runBatch(label: "Enriching (NIH RePORTER)", items: pending) { member in
                try await self.enrichReporter(member)
            }
        }
        if sources.semanticScholar {
            let pending = members.filter { refresh || enrichment[$0.id]?.semanticScholar == nil }
            await runBatch(label: "Enriching (Semantic Scholar)", items: pending) { member in
                try await self.enrichSemanticScholar(member)
            }
        }
        if sources.scopus {
            let pending = members.filter { refresh || enrichment[$0.id]?.scopus == nil }
            await runBatch(label: "Enriching (Scopus)", items: pending) { member in
                try await self.enrichScopus(member)
            }
        }
        if sources.trials {
            let pending = members.filter { refresh || enrichment[$0.id]?.trials == nil }
            await runBatch(label: "Enriching (ClinicalTrials.gov)", items: pending) { member in
                try await self.enrichTrials(member)
            }
        }
    }

    /// Author metrics via the member's Scopus ID plus journal quality metrics
    /// for every distinct ISSN in their works (the response cache dedupes
    /// journals shared across members). Members without a Scopus ID are
    /// skipped with a nudge toward the profile's Find Scopus Author sheet —
    /// never name-matched silently.
    private func enrichScopus(_ member: FacultyMember) async throws {
        guard let data = personData[member.id] else { return }
        guard let scopusID = member.scopusID, !scopusID.isEmpty else {
            throw AppError.needsScopusID
        }
        let author = try await ScopusClient.shared.author(scopusID: scopusID)

        var journals = enrichment[member.id]?.scopus?.journalByISSN ?? [:]
        let issns = Set(data.works.compactMap(\.venueISSN))
        for issn in issns {
            if let metrics = try? await ScopusClient.shared.serialMetrics(issn: issn) {
                journals[issn] = metrics
            }
        }

        var entry = enrichment[member.id] ?? Enrichment()
        entry.scopus = ScopusData(
            author: author,
            journalByISSN: journals,
            documents: entry.scopus?.documents,
            fetchedAt: Date())
        enrichment[member.id] = entry
        save()
    }

    /// Scopus author candidates for the profile confirm sheet.
    func searchScopusAuthors(name: String) async -> [ScopusAuthorCandidate] {
        let criteria = ReporterClient.piNameCriteria(from: name)
        do {
            return try await ScopusClient.shared.searchAuthors(
                lastName: criteria.lastName ?? criteria.anyName ?? name,
                firstName: criteria.firstName)
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    /// Write a confirmed Scopus author back to the roster (which also lets
    /// OpenAlex resolution use it) and enrich immediately.
    func attachScopusAuthor(_ member: FacultyMember, candidate: ScopusAuthorCandidate) async {
        guard let index = roster.firstIndex(where: { $0.id == member.id }) else { return }
        roster[index].scopusID = candidate.scopusID
        save()
        await runBatch(label: "Enriching (Scopus)", items: [roster[index]]) { member in
            try await self.enrichScopus(member)
        }
    }

    /// Pull the member's full Scopus document list for the coverage audit.
    func fetchScopusDocuments(for member: FacultyMember) async {
        guard let scopusID = member.scopusID, !scopusID.isEmpty, !isBusy else { return }
        isBusy = true
        progressText = "Fetching Scopus documents for \(member.name)…"
        defer {
            progressText = ""
            isBusy = false
        }
        do {
            let docs = try await ScopusClient.shared.documents(scopusID: scopusID)
            var entry = enrichment[member.id] ?? Enrichment()
            var scopus = entry.scopus ?? ScopusData(author: nil, journalByISSN: [:], fetchedAt: Date())
            scopus.documents = docs
            entry.scopus = scopus
            enrichment[member.id] = entry
            save()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func enrichICite(_ member: FacultyMember) async throws {
        guard let data = personData[member.id] else { return }
        let pmids = data.works.compactMap(\.pmid)
        guard !pmids.isEmpty else { return }   // pre-pmid cache or nothing PubMed-indexed
        let metrics = try await ICiteClient.shared.metrics(pmids: pmids)
        var entry = enrichment[member.id] ?? Enrichment()
        entry.icite = ICiteData(
            byPMID: Dictionary(metrics.map { ($0.pmid, $0) }, uniquingKeysWith: { first, _ in first }),
            fetchedAt: Date())
        enrichment[member.id] = entry
        save()
    }

    /// Auto-attaches grants only when the PI is already confirmed or the name
    /// search finds exactly one profile; ambiguous names stay unattached until
    /// the user confirms via the profile's Find Grants sheet.
    private func enrichReporter(_ member: FacultyMember) async throws {
        if let confirmed = enrichment[member.id]?.grants?.confirmedProfileID {
            let candidate = PICandidate(
                profileID: confirmed,
                name: enrichment[member.id]?.grants?.confirmedPIName ?? member.name,
                orgName: nil, projectCount: 0, latestFiscalYear: nil)
            try await attachGrants(member, candidate: candidate)
            return
        }
        let candidates = try await ReporterClient.shared.searchPIs(name: member.name)
        if candidates.count == 1 {
            try await attachGrants(member, candidate: candidates[0])
        }
    }

    /// Re-fetch just the attached grants (e.g. to pick up the per-fiscal-year
    /// award breakdown on data enriched before it was tracked).
    func refreshGrants() async {
        let members = roster.filter { enrichment[$0.id]?.grants != nil }
        guard !members.isEmpty else { return }
        await runBatch(label: "Refreshing grants", items: members) { member in
            try await self.enrichReporter(member)
        }
    }

    func searchPIs(name: String) async -> [PICandidate] {
        do {
            return try await ReporterClient.shared.searchPIs(name: name)
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    func attachGrants(_ member: FacultyMember, candidate: PICandidate) async throws {
        let grants = try await ReporterClient.shared.projects(profileID: candidate.profileID)
        var entry = enrichment[member.id] ?? Enrichment()
        entry.grants = GrantData(
            grants: entry.filteringExcluded(grants),
            confirmedProfileID: candidate.profileID,
            confirmedPIName: candidate.name,
            fetchedAt: Date())
        enrichment[member.id] = entry
        save()
    }

    /// Detach one grant and remember the removal, so no future refresh or
    /// re-attach brings it back.
    func excludeGrant(_ member: FacultyMember, coreProjectNum: String) {
        var entry = enrichment[member.id] ?? Enrichment()
        entry.excludedGrants = (entry.excludedGrants ?? []).union([coreProjectNum])
        entry.grants?.grants.removeAll { $0.coreProjectNum == coreProjectNum }
        enrichment[member.id] = entry
        save()
    }

    /// Forget the member's hand-removed grants and re-attach from the
    /// confirmed investigator so they reappear immediately.
    func restoreExcludedGrants(_ member: FacultyMember) async {
        guard var entry = enrichment[member.id],
              !(entry.excludedGrants ?? []).isEmpty else { return }
        entry.excludedGrants = nil
        enrichment[member.id] = entry
        save()
        guard entry.grants?.confirmedProfileID != nil else { return }
        await runBatch(label: "Restoring grants", items: [member]) { member in
            try await self.enrichReporter(member)
        }
    }

    private func enrichSemanticScholar(_ member: FacultyMember) async throws {
        guard let data = personData[member.id],
              let resolution = resolutions[member.id] else { return }
        let s2 = try await SemanticScholarClient.shared.enrich(
            member: member, resolvedName: resolution.displayName, works: data.works)
        var entry = enrichment[member.id] ?? Enrichment()
        entry.semanticScholar = s2
        enrichment[member.id] = entry
        save()
    }

    /// Registered trials where the member appears as an overall official.
    /// Matching is by normalized name tokens (client-side, conservative), so
    /// common names can still over-match — the card shows the trial list for
    /// eyeballing.
    private func enrichTrials(_ member: FacultyMember) async throws {
        let trials = try await ClinicalTrialsClient.shared.trials(officialName: member.name)
        var entry = enrichment[member.id] ?? Enrichment()
        entry.trials = TrialsData(trials: trials, fetchedAt: Date())
        enrichment[member.id] = entry
        save()
    }

    // MARK: Peer benchmark cohort

    /// Benchmark one member against a random OpenAlex sample of authors
    /// active on their dominant topic (≥10 works each).
    func fetchPeerCohort(for member: FacultyMember) async {
        guard let data = effectiveData(for: member.id), !isBusy else { return }
        guard let topicName = MetricsEngine.personTopics(data: data, limit: 1).first?.name else {
            lastError = "\(member.name) has no topic-tagged works to match a cohort on — refresh works first."
            return
        }
        isBusy = true
        progressText = "Sampling peers on “\(topicName)”…"
        defer {
            progressText = ""
            isBusy = false
        }
        do {
            guard let topic = try await client.topic(named: topicName) else {
                lastError = "OpenAlex couldn't find the topic “\(topicName)”."
                return
            }
            let cohort = try await client.authorSample(topicID: topic.id)
            guard cohort.count >= 20, cohort.map(\.worksCount).max() ?? 0 > 0 else {
                lastError = "OpenAlex returned no usable cohort for “\(topic.name)” — its authors index may be degraded; try again later."
                return
            }
            let m = MetricsEngine.personMetrics(member: member, data: data)
            var entry = enrichment[member.id] ?? Enrichment()
            entry.peerCohort = PeerCohortData(
                topicName: topic.name,
                topicID: topic.id,
                cohortSize: cohort.count,
                worksPercentile: MetricsEngine.percentileRank(
                    of: m.worksCount, in: cohort.map(\.worksCount)),
                citationsPercentile: MetricsEngine.percentileRank(
                    of: m.citations, in: cohort.map(\.citedByCount)),
                hIndexPercentile: MetricsEngine.percentileRank(
                    of: m.hIndex, in: cohort.compactMap(\.hIndex)),
                fetchedAt: Date())
            enrichment[member.id] = entry
            save()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Run an async operation over members with progress reporting; individual
    /// failures are collected rather than aborting the batch. Re-entry is
    /// dropped: menu shortcuts can fire while a batch is already running.
    private func runBatch(label: String,
                          items: [FacultyMember],
                          operation: @escaping (FacultyMember) async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        lastError = nil
        var failures: [String] = []
        for (i, member) in items.enumerated() {
            progress = Double(i) / Double(items.count)
            progressText = "\(label) \(member.name) (\(i + 1)/\(items.count))…"
            do {
                try await operation(member)
            } catch {
                failures.append("\(member.name): \(error.localizedDescription)")
            }
        }
        progress = nil
        progressText = ""
        isBusy = false
        if !failures.isEmpty {
            lastError = failures.joined(separator: "\n")
        }
        save()
    }

    // MARK: Persistence

    private struct SavedState: Codable {
        var roster: [FacultyMember]
        var resolutions: [UUID: Resolution]
        var personData: [UUID: PersonData]
        var enrichment: [UUID: Enrichment]?  // optional: absent in pre-enrichment state files
        var deltas: [UUID: RefreshDelta]?    // optional: absent in pre-what's-new state files
        var lastUpdateCheck: Date?
        var excludedWorks: [UUID: Set<String>]?  // optional: absent in pre-exclusion state files
    }

    private var stateURL: URL {
        CacheStore.supportDirectory.appendingPathComponent("state.json")
    }

    func save() {
        invalidateDerived()
        let state = SavedState(roster: roster, resolutions: resolutions,
                               personData: personData, enrichment: enrichment,
                               deltas: deltas, lastUpdateCheck: lastUpdateCheck,
                               excludedWorks: excludedWorks.isEmpty ? nil : excludedWorks)
        do {
            try FileManager.default.createDirectory(
                at: CacheStore.supportDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(state)
            try data.write(to: stateURL, options: .atomic)
        } catch {
            lastError = "Could not save state: \(error.localizedDescription)"
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(SavedState.self, from: data) else { return }
        roster = state.roster
        resolutions = state.resolutions
        personData = state.personData
        enrichment = state.enrichment ?? [:]
        deltas = state.deltas ?? [:]
        lastUpdateCheck = state.lastUpdateCheck
        excludedWorks = state.excludedWorks ?? [:]
    }
}

/// Routes notification clicks back into the app. Kept outside AppStore so
/// the store stays free of NSObject/delegate plumbing.
private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    var onOpenWhatsNew: (@MainActor () -> Void)?

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard response.notification.request.identifier == "facultyiq.whatsnew" else { return }
        await MainActor.run { onOpenWhatsNew?() }
    }

    /// Show the banner even when FacultyIQ is frontmost (default is to
    /// silently drop notifications for the active app).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner]
    }
}
