import SwiftUI

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var watching: [Release] = []
    @Published var recommendations: [Release] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load(api: AnixartAPI) async {
        isLoading = true
        do {
            let watchingResp = try await api.discoverWatching(page: 0)
            self.watching = watchingResp.items
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        // Personal recommendations only when authed (don't fail the whole load if this fails).
        if api.auth.isAuthenticated {
            if let recs = try? await api.discoverRecommendations(page: 0).items {
                self.recommendations = recs
            }
        } else {
            self.recommendations = []
        }
        isLoading = false
    }
}

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var vm = HomeViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if vm.isLoading && vm.watching.isEmpty {
                    ProgressView("Загрузка…")
                        .padding(.vertical, 40)
                        .frame(maxWidth: .infinity)
                } else if let error = vm.errorMessage, vm.watching.isEmpty {
                    ErrorState(message: error) {
                        Task { await vm.load(api: appState.api) }
                    }
                } else {
                    if !vm.recommendations.isEmpty {
                        section(title: "Рекомендации", releases: vm.recommendations)
                    }
                    section(title: "Сейчас смотрят", releases: vm.watching)
                }
            }
            .padding(24)
        }
        .navigationTitle("Главная")
        // Reload when the signed-in profile changes (login/logout) so the
        // personal recommendations section appears/disappears correctly.
        .task(id: auth.profileId) { await vm.load(api: appState.api) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await vm.load(api: appState.api) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Обновить")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("AniAnglia")
                    .font(.system(size: 28, weight: .bold))
                Text("Неофициальный клиент Anixart для macOS")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func section(title: String, releases: [Release]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(releases) { release in
                        NavigationLink(value: release) {
                            ReleaseCard(release: release)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct ErrorState: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.orange)
            Text("Не удалось загрузить")
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Повторить", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
    }
}
