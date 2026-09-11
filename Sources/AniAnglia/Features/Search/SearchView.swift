import SwiftUI

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var results: [Release] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var currentTask: Task<Void, Never>?
    /// Guards against out-of-order responses: only the newest request may update results.
    private var searchEpoch = 0

    func searchAfterDelay(api: AnixartAPI) {
        currentTask?.cancel()
        let q = query
        currentTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            guard let self else { return }
            await self.performSearch(api: api, query: q)
        }
    }

    func performSearch(api: AnixartAPI, query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            searchEpoch += 1
            results = []
            errorMessage = nil
            return
        }
        searchEpoch += 1
        let epoch = searchEpoch
        isLoading = true
        defer { isLoading = false }
        do {
            let resp = try await api.searchReleases(query: trimmed, page: 0)
            guard epoch == searchEpoch else { return }
            results = resp.items
            errorMessage = nil
        } catch {
            guard epoch == searchEpoch else { return }
            errorMessage = error.localizedDescription
        }
    }
}

struct SearchView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm = SearchViewModel()
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .padding()
            content
        }
        .navigationTitle("Поиск")
        .onAppear { searchFieldFocused = true }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Название, студия, автор…", text: $vm.query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($searchFieldFocused)
                .onChange(of: vm.query) { _ in
                    vm.searchAfterDelay(api: appState.api)
                }
                .onSubmit {
                    Task { await vm.performSearch(api: appState.api, query: vm.query) }
                }
            if !vm.query.isEmpty {
                Button {
                    vm.query = ""
                    vm.results = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.results.isEmpty {
            ProgressView().padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = vm.errorMessage, vm.results.isEmpty {
            ErrorState(message: error) {
                Task { await vm.performSearch(api: appState.api, query: vm.query) }
            }
        } else if vm.query.trimmingCharacters(in: .whitespaces).isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("Начни вводить название аниме")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.results.isEmpty {
            VStack(spacing: 8) {
                Text("Ничего не найдено")
                    .font(.headline)
                Text("Попробуй другой запрос")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 16)], alignment: .leading, spacing: 20) {
                    ForEach(vm.results) { release in
                        NavigationLink(value: release) {
                            ReleaseCard(release: release)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
    }
}
