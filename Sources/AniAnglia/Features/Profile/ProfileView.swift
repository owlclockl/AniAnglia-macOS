import SwiftUI

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var profile: Profile?
    @Published var login = ""
    @Published var password = ""
    @Published var isWorking = false
    @Published var errorMessage: String?

    /// Mapping: bookmark category id -> first page of releases (preview).
    @Published var previews: [Int: [Release]] = [:]
    @Published var previewsLoading = false

    func loadCurrentProfile(api: AnixartAPI, auth: AuthStore) async {
        guard let id = auth.profileId else { return }
        do {
            profile = try await api.profile(id: id)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadBookmarkPreviews(api: AnixartAPI) async {
        previewsLoading = true
        defer { previewsLoading = false }
        for cat in [2, 1, 3, 4, 5] {
            do {
                let resp = try await api.bookmarks(category: cat, page: 0)
                previews[cat] = Array(resp.items.prefix(8))
            } catch {
                previews[cat] = []
            }
        }
    }

    func signIn(api: AnixartAPI, auth: AuthStore) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let resp = try await api.signIn(login: login, password: password)
            guard resp.code == 0, let token = resp.profileToken?.token, let pid = resp.profile?.id else {
                errorMessage = readableSignInError(code: resp.code, fallback: resp.message)
                return
            }
            auth.setCredentials(token: token, profileId: pid)
            profile = resp.profile
            errorMessage = nil
            password = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func readableSignInError(code: Int, fallback: String?) -> String {
        switch code {
        case 2: return "Аккаунт не подтверждён по e-mail"
        case 3: return "Неверный логин или пароль"
        case 4: return "Аккаунт заблокирован"
        case 5: return "Включена двухфакторная авторизация — войди через сайт"
        default: return fallback ?? "Не удалось войти (code=\(code))"
        }
    }
}

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var vm = ProfileViewModel()

    /// (categoryId, title, accent color) — order matches what users expect on iOS.
    private let categories: [(Int, String, Color)] = [
        (2, "Смотрю", .indigo),
        (1, "В планах", .yellow),
        (3, "Просмотрено", .green),
        (4, "Отложено", .purple),
        (5, "Брошено", .red)
    ]

    var body: some View {
        Group {
            if auth.isAuthenticated {
                authenticated
            } else {
                signInForm
            }
        }
        .navigationTitle("Профиль")
        .task(id: auth.profileId) {
            await vm.loadCurrentProfile(api: appState.api, auth: auth)
            if auth.isAuthenticated {
                await vm.loadBookmarkPreviews(api: appState.api)
            }
        }
    }

    @ViewBuilder
    private var authenticated: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                profileHeader
                if let profile = vm.profile {
                    statsGrid(for: profile)
                }
                Divider()
                bookmarkSections
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var profileHeader: some View {
        HStack(alignment: .top, spacing: 20) {
            RemoteImage(url: vm.profile?.avatarURL, contentMode: .fill) {
                Circle().fill(Color.secondary.opacity(0.2))
            }
            .frame(width: 110, height: 110)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 1))

            VStack(alignment: .leading, spacing: 6) {
                Text(vm.profile?.login ?? "—")
                    .font(.system(size: 26, weight: .bold))
                if let status = vm.profile?.status, !status.isEmpty {
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let registered = registerDateText {
                    Text(registered)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            VStack(spacing: 8) {
                Button {
                    Task {
                        await vm.loadCurrentProfile(api: appState.api, auth: auth)
                        await vm.loadBookmarkPreviews(api: appState.api)
                    }
                } label: {
                    Label("Обновить", systemImage: "arrow.clockwise")
                }
                Button(role: .destructive) {
                    auth.signOut()
                    vm.profile = nil
                    vm.previews = [:]
                } label: {
                    Label("Выйти", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
    }

    private var registerDateText: String? {
        guard let ts = vm.profile?.registerDate, ts > 0 else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(ts))
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateStyle = .long
        f.timeStyle = .none
        return "С \(f.string(from: date))"
    }

    private func statsGrid(for profile: Profile) -> some View {
        let stats: [(String, Int?, Int)] = [
            ("Смотрю", profile.watchingReleasesCount, 2),
            ("В планах", profile.plannedReleasesCount, 1),
            ("Просмотрено", profile.watchedReleasesCount, 3),
            ("Отложено", profile.holdOnReleasesCount, 4),
            ("Брошено", profile.abandonedReleasesCount, 5)
        ]
        return HStack(spacing: 12) {
            ForEach(stats, id: \.2) { (title, value, cat) in
                Button {
                    appState.selectSidebar(.bookmarks, bookmarkCategory: cat)
                } label: {
                    VStack(spacing: 4) {
                        Text("\(value ?? 0)")
                            .font(.title3.bold().monospacedDigit())
                        Text(title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .help("Открыть «\(title)»")
            }
        }
    }

    @ViewBuilder
    private var bookmarkSections: some View {
        ForEach(categories, id: \.0) { (cat, title, color) in
            let releases = vm.previews[cat] ?? []
            if !releases.isEmpty || vm.previewsLoading {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Circle().fill(color).frame(width: 10, height: 10)
                        Text(title).font(.title3.bold())
                        Spacer()
                        Button("Все →") {
                            appState.selectSidebar(.bookmarks, bookmarkCategory: cat)
                        }
                        .buttonStyle(.borderless)
                    }
                    if releases.isEmpty {
                        Text("Список пуст")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 8)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 14) {
                                ForEach(releases) { release in
                                    NavigationLink(value: release) {
                                        ReleaseCard(release: release)
                                            .frame(width: 160)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.bottom, 4)
                        }
                    }
                }
            }
        }
    }

    private var signInForm: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Вход в Anixart")
                .font(.title2.bold())

            VStack(spacing: 10) {
                TextField("Логин или e-mail", text: $vm.login)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 320)
                SecureField("Пароль", text: $vm.password)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 320)
                    .onSubmit {
                        Task { await vm.signIn(api: appState.api, auth: auth) }
                    }
            }

            if let error = vm.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await vm.signIn(api: appState.api, auth: auth) }
            } label: {
                if vm.isWorking {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Войти")
                        .frame(width: 80)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.login.isEmpty || vm.password.isEmpty || vm.isWorking)

            Text("Анонимный режим работает без входа — можно смотреть каталог, поиск и страницы релизов. Закладки, история, комменты и оценки требуют авторизации.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
                .padding(.top, 16)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
