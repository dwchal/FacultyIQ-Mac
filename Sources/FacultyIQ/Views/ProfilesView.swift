import Charts
import SwiftUI

/// Individual faculty drill-down: metric grid, publication trend, top works.
struct ProfilesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedID: UUID?

    private var membersWithData: [FacultyMember] {
        store.roster.filter { store.personData[$0.id] != nil }
    }

    var body: some View {
        if membersWithData.isEmpty {
            ContentUnavailableView(
                "No Faculty Data",
                systemImage: "person.text.rectangle",
                description: Text("Fetch metrics on the Resolution tab to view individual profiles.")
            )
        } else {
            HSplitView {
                List(membersWithData, selection: $selectedID) { member in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(member.name)
                        Text(member.rank ?? "—")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(member.id)
                }
                .frame(minWidth: 200, maxWidth: 280)

                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onAppear {
                if selectedID == nil { selectedID = membersWithData.first?.id }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let member = membersWithData.first(where: { $0.id == selectedID }),
           let data = store.personData[member.id] {
            ProfileDetail(member: member, data: data,
                          resolution: store.resolution(for: member),
                          metrics: MetricsEngine.personMetrics(member: member, data: data))
        } else {
            Text("Select a faculty member")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct ProfileDetail: View {
    let member: FacultyMember
    let data: PersonData
    let resolution: Resolution?
    let metrics: PersonMetrics

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                metricGrid
                trendChart
                topWorks
            }
            .padding(20)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(member.name).font(.title.weight(.semibold))
            HStack(spacing: 8) {
                if let rank = member.rank { Text(rank) }
                if let aff = resolution?.affiliation {
                    Text("·").foregroundStyle(.tertiary)
                    Text(aff)
                }
            }
            .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                if let res = resolution,
                   let url = URL(string: "https://openalex.org/\(res.openalexID)") {
                    Link("OpenAlex ↗", destination: url)
                }
                if let orcid = member.orcid ?? resolution?.orcid.map(RosterImporter.cleanORCID),
                   let url = URL(string: "https://orcid.org/\(orcid)") {
                    Link("ORCID ↗", destination: url)
                }
            }
            .font(.callout)
        }
    }

    private var metricGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            tile("Works", "\(metrics.worksCount)")
            tile("Citations", metrics.citations.formatted())
            tile("h-index", "\(metrics.hIndex)")
            tile("i10-index", "\(metrics.i10Index)")
            tile("Citations / Work", String(format: "%.1f", metrics.citationsPerWork))
            tile("Works / Year", String(format: "%.2f", metrics.worksPerYear))
            tile("Open Access", metrics.oaPercent.map { String(format: "%.0f%%", $0) } ?? "—")
            tile("Works, Last 5y", "\(metrics.recentWorks5y)")
        }
    }

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title2.weight(.semibold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private var trendChart: some View {
        var byYear: [Int: Int] = [:]
        for work in data.works {
            if let y = work.year { byYear[y, default: 0] += 1 }
        }
        let series = byYear.sorted { $0.key < $1.key }

        return VStack(alignment: .leading, spacing: 10) {
            Text("Publications per Year").font(.headline)
            Chart(series, id: \.key) { year, count in
                BarMark(
                    x: .value("Year", year),
                    y: .value("Works", count),
                    width: .ratio(0.7)
                )
                .foregroundStyle(ChartPalette.series1)
                .cornerRadius(2)
            }
            .yearXAxis(years: series.map(\.key))
            .frame(height: 180)
        }
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private var topWorks: some View {
        let top = Array(data.works.sorted { $0.citedByCount > $1.citedByCount }.prefix(15))
        return VStack(alignment: .leading, spacing: 10) {
            Text("Most-Cited Works").font(.headline)
            Table(top) {
                TableColumn("Title") { work in
                    if let doi = work.doi, let url = URL(string: doi) {
                        Link(work.title, destination: url)
                            .foregroundStyle(.primary)
                    } else {
                        Text(work.title)
                    }
                }
                TableColumn("Year") { Text($0.year.map(String.init) ?? "—") }
                    .width(45)
                TableColumn("Venue") { Text($0.venue ?? "—") }
                    .width(min: 100, ideal: 180)
                TableColumn("Citations") { Text("\($0.citedByCount)") }
                    .width(60)
                TableColumn("OA") { work in
                    if work.isOA == true {
                        Text(work.oaStatus ?? "open")
                            .font(.caption)
                            .foregroundStyle(ChartPalette.positive)
                    } else {
                        Text("—").foregroundStyle(.tertiary)
                    }
                }
                .width(55)
            }
            .frame(height: 360)
        }
    }
}
