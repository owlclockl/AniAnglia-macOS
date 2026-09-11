import SwiftUI

@MainActor
final class ReleaseDetailViewModel: ObservableObject {
    @Published var release: Release?
    @Published var videoBlocks: [VideoBlock] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var bookmarkCategory: Int? = nil // 0 = none, 1..5 = list category
    @Published var bookmarkPending = false
    @Published var bookmarkError: String?
    @Published var userVote: Int = 0 // 0 = none, 1..5 stars
    @Published var votePending = false

    func load(api: AnixartAPI, releaseId: Int64) async {
        isLoading = true
        let loadedRelease: Release? = await {
            do { return try await api.release(id: releaseId) }
            catch { return nil }
        }()
        let loadedBlocks: [VideoBlock] = await {
            do { return try await api.videoBlocks(releaseId: releaseId).blocks }
            catch { return [] }
        }()
        if let loadedRelease {
            release = loadedRelease
            bookmarkCategory = loadedRelease.profileListStatus
            userVote = loadedRelease.yourVote ?? 0
        }
        videoBlocks = loadedBlocks
        if release == nil && errorMessage == nil {
            errorMessage = "Не удалось загрузить релиз"
        }
        isLoading = false
    }

    func setRating(api: AnixartAPI, releaseId: Int64, stars: Int) async {
        let previous = userVote
        let next = stars == userVote ? 0 : stars
        userVote = next
        votePending = true
        defer { votePending = false }
        do {
            if next == 0 {
                _ = try await api.unrateRelease(releaseId: releaseId)
            } else {
                _ = try await api.rateRelease(releaseId: releaseId, stars: next)
            }
        } catch {
            userVote = previous
            bookmarkError = error.localizedDescription
        }
    }

    func setBookmark(api: AnixartAPI, releaseId: Int64, category: Int?) async {
        bookmarkPending = true
        defer { bookmarkPending = false }
        do {
            if let category {
                _ = try await api.addToList(releaseId: releaseId, category: category)
                bookmarkCategory = category
            } else {
                _ = try await api.removeFromList(releaseId: releaseId)
                bookmarkCategory = nil
            }
            bookmarkError = nil
        } catch {
            bookmarkError = error.localizedDescription
        }
    }
}

struct ReleaseDetailView: View {
    let releaseId: Int64
    let prefetched: Release?

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var vm = ReleaseDetailViewModel()
    @State private var fullscreenScreenshots: [URL]?
    @State private var fullscreenIndex: Int = 0
    @State private var playingVideo: Video?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if let release = effectiveRelease {
                    info(for: release)
                    if !vm.videoBlocks.isEmpty {
                        videosSection
                    }
                    if !release.screenshots.isEmpty {
                        screenshotsSection(urls: release.screenshots)
                    }
                    description(for: release)
                    Divider().padding(.vertical, 8)
                    CommentsView(releaseId: releaseId)
                } else if vm.isLoading {
                    ProgressView().padding()
                } else if let error = vm.errorMessage {
                    ErrorState(message: error) {
                        Task { await vm.load(api: appState.api, releaseId: releaseId) }
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle(effectiveRelease?.displayTitle ?? "Релиз")
        .task { await vm.load(api: appState.api, releaseId: releaseId) }
        .sheet(item: $playingVideo) { video in
            VideoPlayerSheet(video: video)
        }
        .sheet(isPresented: Binding(get: { fullscreenScreenshots != nil }, set: { if !$0 { fullscreenScreenshots = nil } })) {
            if let urls = fullscreenScreenshots {
                ScreenshotsViewer(urls: urls, initialIndex: fullscreenIndex) {
                    fullscreenScreenshots = nil
                }
            }
        }
        .alert("Не удалось", isPresented: Binding(
            get: { vm.bookmarkError != nil },
            set: { if !$0 { vm.bookmarkError = nil } }
        ), actions: {
            Button("OK") { vm.bookmarkError = nil }
        }, message: {
            Text(vm.bookmarkError ?? "")
        })
    }

    private var effectiveRelease: Release? {
        vm.release ?? prefetched
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 24) {
            RemoteImage(url: effectiveRelease?.posterURL, contentMode: .fill) {
                Rectangle().fill(Color.secondary.opacity(0.1))
            }
            .frame(width: 220, height: 320)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(radius: 8)

            VStack(alignment: .leading, spacing: 12) {
                if let release = effectiveRelease {
                    Text(release.displayTitle)
                        .font(.system(size: 28, weight: .bold))
                    if let original = release.titleOriginal, original != release.displayTitle {
                        Text(original)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 12) {
                        if let year = release.year { Tag(text: year) }
                        if let status = release.status?.name { Tag(text: status) }
                        if let category = release.category?.name { Tag(text: category) }
                        if let grade = release.grade {
                            Tag(text: String(format: "★ %.2f", grade), tint: .yellow)
                        }
                    }
                    if let genres = release.genres, !genres.isEmpty {
                        Text(genres)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if auth.isAuthenticated {
                        userRatingRow
                    }
                    actionsRow
                }
                Spacer()
            }
            Spacer()
        }
    }

    private var userRatingRow: some View {
        HStack(spacing: 4) {
            Text(vm.userVote == 0 ? "Оценить:" : "Твоя оценка:")
                .font(.callout)
                .foregroundStyle(.secondary)
            ForEach(1...5, id: \.self) { star in
                Button {
                    Task { await vm.setRating(api: appState.api, releaseId: releaseId, stars: star) }
                } label: {
                    Image(systemName: star <= vm.userVote ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundStyle(star <= vm.userVote ? Color.yellow : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(vm.votePending)
            }
            if vm.userVote > 0 {
                Button {
                    Task { await vm.setRating(api: appState.api, releaseId: releaseId, stars: vm.userVote) }
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Убрать свою оценку")
            }
        }
    }

    private var actionsRow: some View {
        HStack(spacing: 10) {
            NavigationLink {
                EpisodesView(releaseId: releaseId, releaseTitle: effectiveRelease?.displayTitle)
            } label: {
                Label("Смотреть", systemImage: "play.fill")
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)

            bookmarkMenu
        }
        .padding(.top, 8)
    }

    private var bookmarkMenu: some View {
        let cats: [(Int, String, Color)] = [
            (1, "В планах", .yellow),
            (2, "Смотрю", .indigo),
            (3, "Просмотрено", .green),
            (4, "Отложено", .purple),
            (5, "Брошено", .red)
        ]
        let current = vm.bookmarkCategory
        let currentLabel = cats.first(where: { $0.0 == current })
        return Menu {
            ForEach(cats, id: \.0) { (id, name, _) in
                Button {
                    Task { await vm.setBookmark(api: appState.api, releaseId: releaseId, category: id) }
                } label: {
                    if current == id {
                        Label(name, systemImage: "checkmark")
                    } else {
                        Text(name)
                    }
                }
            }
            if current != nil {
                Divider()
                Button(role: .destructive) {
                    Task { await vm.setBookmark(api: appState.api, releaseId: releaseId, category: nil) }
                } label: {
                    Label("Убрать из списка", systemImage: "bookmark.slash")
                }
            }
        } label: {
            Label(currentLabel?.1 ?? "В закладки",
                  systemImage: currentLabel == nil ? "bookmark" : "bookmark.fill")
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .foregroundStyle(currentLabel?.2 ?? .accentColor)
        }
        .fixedSize()
        .disabled(vm.bookmarkPending || !auth.isAuthenticated)
        .help(auth.isAuthenticated ? "Списки отслеживания" : "Войди в аккаунт во вкладке «Профиль», чтобы добавлять в закладки")
    }

    private func info(for release: Release) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Студия", release.studio)
            row("Страна", release.country)
            row("Автор", release.author)
            row("Режиссёр", release.director)
            row("Серий вышло", release.episodesReleased.map { String($0) })
            row("Серий всего", release.episodesTotal.map { String($0) })
        }
        .font(.callout)
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                Text(label)
                    .frame(width: 120, alignment: .leading)
                    .foregroundStyle(.secondary)
                Text(value)
            }
        }
    }

    private func description(for release: Release) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Описание").font(.title3.bold())
            Text(release.description ?? "—")
                .font(.callout)
                .textSelection(.enabled)
        }
    }

    private var videosSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Видео").font(.title3.bold())
            ForEach(vm.videoBlocks) { block in
                VStack(alignment: .leading, spacing: 8) {
                    Text(block.category.name)
                        .font(.headline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(block.videos) { video in
                                Button {
                                    playingVideo = video
                                } label: {
                                    VideoThumbnail(video: video)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    private func screenshotsSection(urls: [URL]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Кадры").font(.title3.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { (index, url) in
                        Button {
                            fullscreenIndex = index
                            fullscreenScreenshots = urls
                        } label: {
                            RemoteImage(url: url, contentMode: .fill) {
                                Rectangle().fill(Color.secondary.opacity(0.1))
                            }
                            .frame(width: 240, height: 135)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct Tag: View {
    let text: String
    var tint: Color = .accentColor

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.18))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }
}

private struct VideoThumbnail: View {
    let video: Video

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RemoteImage(url: video.thumbnailURL, contentMode: .fill) {
                    Rectangle().fill(Color.secondary.opacity(0.1))
                }
                .frame(width: 240, height: 135)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.white.opacity(0.95))
            }
            Text(video.title ?? "Без названия")
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .frame(width: 240, alignment: .leading)
            if let host = video.hosting?.name {
                Text(host)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
