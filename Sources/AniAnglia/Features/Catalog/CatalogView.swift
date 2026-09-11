import SwiftUI

@MainActor
final class CatalogViewModel: ObservableObject {
    @Published var releases: [Release] = []
    @Published var page = 0
    @Published var totalPages: Int?
    @Published var isLoading = false
    @Published var errorMessage: String?

    @Published var sort: Int = 3 // Popular
    @Published var category: Int? = nil
    @Published var status: Int? = nil
    @Published var startYear: Int? = nil
    @Published var endYear: Int? = nil
    @Published var genres: Set<String> = []
    @Published var excludeGenres: Bool = false

    func reload(api: AnixartAPI) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let resp = try await fetch(api: api, page: 0)
            releases = resp.items
            totalPages = resp.totalPageCount
            page = 0
            errorMessage = nil
        } catch {
            releases = []
            errorMessage = error.localizedDescription
        }
    }

    func loadMore(api: AnixartAPI) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let next = page + 1
        do {
            let resp = try await fetch(api: api, page: next)
            releases.append(contentsOf: resp.items)
            totalPages = resp.totalPageCount
            // Advance the page only on success, so a failed request
            // doesn't leave a hole in the listing.
            page = next
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func fetch(api: AnixartAPI, page: Int) async throws -> ReleasesResponse {
        try await api.filter(
            page: page,
            sort: sort,
            category: category,
            status: status,
            startYear: startYear,
            endYear: endYear,
            genres: Array(genres),
            excludeGenres: excludeGenres
        )
    }

    func canLoadMore() -> Bool {
        if let total = totalPages, total > 0 { return page + 1 < total }
        return !releases.isEmpty
    }
}

struct CatalogView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var vm = CatalogViewModel()

    private let sortOptions: [(Int, String)] = [
        (3, "По популярности"),
        (1, "По оценке"),
        (0, "По обновлению"),
        (2, "По году")
    ]
    private let categoryOptions: [(Int?, String)] = [
        (nil, "Все категории"),
        (1, "Сериал"),
        (2, "Фильм"),
        (3, "OVA"),
        (4, "ONA"),
        (5, "Спешл")
    ]
    private let statusOptions: [(Int?, String)] = [
        (nil, "Любой статус"),
        (1, "Вышел"),
        (2, "Анонс"),
        (3, "Онгоинг")
    ]
    private var yearOptions: [Int] {
        let currentYear = Calendar.current.component(.year, from: Date())
        return Array(stride(from: currentYear, through: 1960, by: -1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                filtersBar
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
            }
            Divider()
            content
        }
        .navigationTitle("Каталог")
        .task {
            if vm.releases.isEmpty {
                await vm.reload(api: appState.api)
            }
        }
    }

    private var filtersBar: some View {
        HStack(spacing: 8) {
            Picker("Сортировка", selection: $vm.sort) {
                ForEach(sortOptions, id: \.0) { Text($0.1).tag($0.0) }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 220)

            Picker("Категория", selection: $vm.category) {
                ForEach(categoryOptions, id: \.1) { Text($0.1).tag($0.0) }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 200)

            Picker("Статус", selection: $vm.status) {
                ForEach(statusOptions, id: \.1) { Text($0.1).tag($0.0) }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 200)

            Picker("С года", selection: $vm.startYear) {
                Text("С").tag(Int?.none)
                ForEach(yearOptions, id: \.self) { Text(String($0)).tag(Int?.some($0)) }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 120)

            Picker("По год", selection: $vm.endYear) {
                Text("По").tag(Int?.none)
                ForEach(yearOptions, id: \.self) { Text(String($0)).tag(Int?.some($0)) }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 120)

            GenresPickerButton(selected: $vm.genres, exclude: $vm.excludeGenres)

            Spacer()

            Button("Применить") {
                Task { await vm.reload(api: appState.api) }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.releases.isEmpty {
            ProgressView().padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = vm.errorMessage, vm.releases.isEmpty {
            ErrorState(message: error) {
                Task { await vm.reload(api: appState.api) }
            }
        } else if vm.releases.isEmpty {
            Text("Ничего не найдено")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 16)], alignment: .leading, spacing: 20) {
                    ForEach(vm.releases) { release in
                        NavigationLink(value: release) {
                            ReleaseCard(release: release)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()

                if vm.canLoadMore() {
                    Button {
                        Task { await vm.loadMore(api: appState.api) }
                    } label: {
                        if vm.isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Показать ещё")
                                .padding(.horizontal, 24)
                        }
                    }
                    .buttonStyle(.bordered)
                    .padding(.bottom, 20)
                }
            }
        }
    }
}
