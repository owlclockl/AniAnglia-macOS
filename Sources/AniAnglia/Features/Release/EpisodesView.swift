import SwiftUI

@MainActor
final class EpisodesViewModel: ObservableObject {
    let releaseId: Int64
    @Published var types: [EpisodeType] = []
    @Published var sources: [EpisodeSource] = []
    @Published var episodes: [Episode] = []
    @Published var selectedTypeId: Int?
    @Published var selectedSourceId: Int?
    @Published var isLoadingTypes = false
    @Published var isLoadingSources = false
    @Published var isLoadingEpisodes = false
    @Published var errorMessage: String?
    /// Locally toggled watched state, keyed by Episode.id.
    @Published var watchedOverrides: [String: Bool] = [:]

    init(releaseId: Int64) { self.releaseId = releaseId }

    func isWatched(_ episode: Episode) -> Bool {
        if let v = watchedOverrides[episode.id] { return v }
        return episode.isWatched == true
    }

    func toggleWatched(_ episode: Episode, api: AnixartAPI) async {
        let nextWatched = !isWatched(episode)
        watchedOverrides[episode.id] = nextWatched
        do {
            if nextWatched {
                _ = try await api.markEpisodeWatched(releaseId: episode.releaseId, sourceId: episode.sourceId, position: episode.position)
            } else {
                _ = try await api.unmarkEpisodeWatched(releaseId: episode.releaseId, sourceId: episode.sourceId, position: episode.position)
            }
        } catch {
            // Revert on failure
            watchedOverrides[episode.id] = !nextWatched
            errorMessage = error.localizedDescription
        }
    }

    func loadTypes(api: AnixartAPI) async {
        isLoadingTypes = true
        defer { isLoadingTypes = false }
        do {
            let list = try await api.episodeTypes(releaseId: releaseId)
            types = list
            errorMessage = nil
            // Pick pinned or first
            if let firstPinned = list.first(where: { $0.pinned == true }) ?? list.first {
                selectedTypeId = firstPinned.id
                await loadSources(api: api, typeId: firstPinned.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadSources(api: AnixartAPI, typeId: Int) async {
        selectedTypeId = typeId
        sources = []
        episodes = []
        selectedSourceId = nil
        isLoadingSources = true
        defer { isLoadingSources = false }
        do {
            let list = try await api.episodeSources(releaseId: releaseId, typeId: typeId)
            sources = list
            if let first = list.first(where: { $0.pinned == true }) ?? list.first {
                selectedSourceId = first.id
                await loadEpisodes(api: api, typeId: typeId, sourceId: first.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadEpisodes(api: AnixartAPI, typeId: Int, sourceId: Int) async {
        selectedSourceId = sourceId
        episodes = []
        isLoadingEpisodes = true
        defer { isLoadingEpisodes = false }
        do {
            let list = try await api.episodes(releaseId: releaseId, typeId: typeId, sourceId: sourceId)
            episodes = list.sorted { $0.position < $1.position }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct EpisodesView: View {
    let releaseId: Int64
    let releaseTitle: String?

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var vm: EpisodesViewModel
    @State private var playing: Episode?

    init(releaseId: Int64, releaseTitle: String? = nil) {
        self.releaseId = releaseId
        self.releaseTitle = releaseTitle
        _vm = StateObject(wrappedValue: EpisodesViewModel(releaseId: releaseId))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !vm.types.isEmpty { typesPicker }
            if !vm.sources.isEmpty { sourcesPicker }
            Divider()
            content
        }
        .padding(20)
        .navigationTitle(releaseTitle ?? "Серии")
        .task { await vm.loadTypes(api: appState.api) }
        .sheet(item: $playing) { episode in
            EpisodePlayerSheet(episode: episode, releaseTitle: releaseTitle, onClosed: {
                if auth.isAuthenticated && !vm.isWatched(episode) {
                    Task { await vm.toggleWatched(episode, api: appState.api) }
                }
            })
        }
    }

    private var typesPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Озвучка")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.types) { type in
                        chip(
                            title: type.name,
                            subtitle: type.workers,
                            count: type.episodesCount,
                            isSelected: vm.selectedTypeId == type.id
                        ) {
                            Task { await vm.loadSources(api: appState.api, typeId: type.id) }
                        }
                    }
                }
            }
        }
    }

    private var sourcesPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Плеер")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.sources) { source in
                        chip(
                            title: source.name,
                            subtitle: nil,
                            count: source.episodesCount,
                            isSelected: vm.selectedSourceId == source.id
                        ) {
                            if let typeId = vm.selectedTypeId {
                                Task { await vm.loadEpisodes(api: appState.api, typeId: typeId, sourceId: source.id) }
                            }
                        }
                    }
                }
            }
        }
    }

    private func chip(title: String, subtitle: String?, count: Int?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.callout.bold())
                    if let count, count > 0 {
                        Text("\(count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoadingTypes || vm.isLoadingSources || vm.isLoadingEpisodes {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = vm.errorMessage, vm.episodes.isEmpty {
            ErrorState(message: error) {
                Task { await vm.loadTypes(api: appState.api) }
            }
        } else if vm.episodes.isEmpty {
            Text("У этого релиза пока нет серий в выбранной озвучке/плеере.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(vm.episodes) { episode in
                        EpisodeRow(
                            episode: episode,
                            isWatched: vm.isWatched(episode),
                            canMark: auth.isAuthenticated,
                            onPlay: { playing = episode },
                            onToggleWatched: {
                                Task { await vm.toggleWatched(episode, api: appState.api) }
                            }
                        )
                        Divider()
                    }
                }
            }
        }
    }
}

private struct EpisodeRow: View {
    let episode: Episode
    let isWatched: Bool
    let canMark: Bool
    let onPlay: () -> Void
    let onToggleWatched: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggleWatched) {
                Image(systemName: isWatched ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isWatched ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!canMark)
            .help(canMark ? (isWatched ? "Отметить как не просмотренную" : "Отметить как просмотренную") : "Войди в аккаунт, чтобы отмечать серии")

            Button(action: onPlay) {
                HStack(spacing: 12) {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(episode.name ?? "Серия \(episode.position + 1)")
                            .font(.body)
                            .foregroundStyle(.primary)
                        if let url = episode.url, !url.isEmpty {
                            Text(host(of: url))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func host(of url: String) -> String {
        URL(string: url)?.host ?? url
    }
}

struct EpisodePlayerSheet: View {
    let episode: Episode
    let releaseTitle: String?
    var onClosed: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(episode.name ?? "Серия \(episode.position + 1)")
                        .font(.headline)
                    if let title = releaseTitle {
                        Text(title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let url = episode.resolvedURL {
                    Button {
                        openURL(url)
                    } label: {
                        Image(systemName: "safari")
                    }
                    .help("Открыть в Safari")
                }
                Button("Закрыть") {
                    onClosed?()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider()
            if let url = episode.resolvedURL {
                WebView(url: url)
                    .frame(minWidth: 800, minHeight: 480)
            } else {
                Text("Нет ссылки на плеер")
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 600, minHeight: 300)
            }
        }
        .frame(minWidth: 800, minHeight: 540)
    }
}
