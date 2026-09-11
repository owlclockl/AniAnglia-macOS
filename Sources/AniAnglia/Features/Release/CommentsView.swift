import SwiftUI

@MainActor
final class CommentsViewModel: ObservableObject {
    let releaseId: Int64
    @Published var comments: [ReleaseComment] = []
    @Published var sort: Int = 2 // 0=new, 1=old, 2=top
    @Published var isLoading = false
    @Published var page = 0
    @Published var totalPages: Int?
    @Published var errorMessage: String?

    // Compose state
    @Published var draft: String = ""
    @Published var draftSpoiler: Bool = false
    @Published var isPosting: Bool = false
    @Published var postError: String?

    /// Local override of vote state for snappy UI (commentId -> +1/-1).
    @Published var voteOverrides: [Int64: Int] = [:]

    init(releaseId: Int64) {
        self.releaseId = releaseId
    }

    func currentVote(for comment: ReleaseComment) -> Int {
        if let v = voteOverrides[comment.id] { return v }
        return comment.vote ?? 0
    }

    func vote(_ comment: ReleaseComment, value: Int, api: AnixartAPI) async {
        let current = currentVote(for: comment)
        let next = current == value ? 0 : value // tap same again to undo
        voteOverrides[comment.id] = next
        do {
            _ = try await api.voteComment(commentId: comment.id, value: next)
        } catch {
            voteOverrides[comment.id] = current
            errorMessage = error.localizedDescription
        }
    }

    func submitDraft(api: AnixartAPI) async -> Bool {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        isPosting = true
        postError = nil
        defer { isPosting = false }
        do {
            let resp = try await api.addComment(releaseId: releaseId, message: trimmed, parentCommentId: nil, isSpoiler: draftSpoiler)
            if resp.code == 0 {
                draft = ""
                draftSpoiler = false
                await reload(api: api)
                return true
            } else {
                postError = resp.message ?? "Не удалось отправить (code=\(resp.code))"
                return false
            }
        } catch {
            postError = error.localizedDescription
            return false
        }
    }

    func reload(api: AnixartAPI) async {
        isLoading = true
        page = 0
        errorMessage = nil
        do {
            let resp = try await api.releaseComments(releaseId: releaseId, page: 0, sort: sort)
            comments = resp.content
            totalPages = resp.totalPageCount
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadMore(api: AnixartAPI) async {
        guard !isLoading, canLoadMore else { return }
        isLoading = true
        let next = page + 1
        do {
            let resp = try await api.releaseComments(releaseId: releaseId, page: next, sort: sort)
            comments.append(contentsOf: resp.content)
            page = next
            totalPages = resp.totalPageCount
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    var canLoadMore: Bool {
        guard let total = totalPages else { return true }
        return page + 1 < total
    }
}

struct CommentsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var vm: CommentsViewModel

    init(releaseId: Int64) {
        _vm = StateObject(wrappedValue: CommentsViewModel(releaseId: releaseId))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Комментарии")
                    .font(.title3.bold())
                if let total = vm.totalPages, total > 0 {
                    Text("(\(vm.comments.count))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Сортировка", selection: $vm.sort) {
                    Text("Популярные").tag(2)
                    Text("Новые").tag(0)
                    Text("Старые").tag(1)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .onChange(of: vm.sort) { _ in
                    Task { await vm.reload(api: appState.api) }
                }
            }

            if auth.isAuthenticated {
                composer
            } else {
                Text("Чтобы оставить комментарий, войди в аккаунт через кнопку «Войти» справа сверху.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if vm.comments.isEmpty && vm.isLoading {
                ProgressView().frame(maxWidth: .infinity, alignment: .center).padding()
            } else if vm.comments.isEmpty {
                Text("Пока нет комментариев")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(vm.comments) { comment in
                        CommentRow(
                            comment: comment,
                            currentVote: vm.currentVote(for: comment),
                            canVote: auth.isAuthenticated,
                            onVote: { value in
                                Task { await vm.vote(comment, value: value, api: appState.api) }
                            }
                        )
                    }
                    if vm.canLoadMore {
                        Button {
                            Task { await vm.loadMore(api: appState.api) }
                        } label: {
                            HStack {
                                if vm.isLoading { ProgressView().controlSize(.small) }
                                Text("Показать ещё")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .padding(.top, 8)
                    }
                }
            }
        }
        .task { await vm.reload(api: appState.api) }
    }

    @ViewBuilder
    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                if vm.draft.isEmpty {
                    Text("Напиши свой комментарий…")
                        .foregroundStyle(.tertiary)
                        .padding(8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $vm.draft)
                    .frame(minHeight: 60, maxHeight: 120)
                    .padding(4)
                    .scrollContentBackground(.hidden)
            }
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            HStack {
                Toggle("Спойлер", isOn: $vm.draftSpoiler)
                    .toggleStyle(.checkbox)
                if let err = vm.postError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
                Spacer()
                Button {
                    Task { _ = await vm.submitDraft(api: appState.api) }
                } label: {
                    if vm.isPosting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Отправить")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.isPosting || vm.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

private struct CommentRow: View {
    let comment: ReleaseComment
    let currentVote: Int
    let canVote: Bool
    let onVote: (Int) -> Void

    private var displayedScore: Int {
        let base = (comment.voteCount ?? 0)
        let serverVote = comment.vote ?? 0
        return base - serverVote + currentVote
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RemoteImage(url: comment.profile?.avatarURL, contentMode: .fill) {
                Circle().fill(Color.secondary.opacity(0.2))
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(comment.profile?.login ?? "—")
                        .font(.callout.bold())
                    Text(comment.formattedDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if comment.isEdited == true {
                        Text("(ред.)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let ep = comment.postedAtEpisode, ep > 0 {
                        Text("после \(ep) серии")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if comment.isSpoiler == true {
                    SpoilerText(text: comment.message)
                } else {
                    Text(comment.message)
                        .font(.callout)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 12) {
                    Button {
                        onVote(1)
                    } label: {
                        Image(systemName: currentVote == 1 ? "hand.thumbsup.fill" : "hand.thumbsup")
                            .foregroundStyle(currentVote == 1 ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canVote)

                    Text("\(displayedScore)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 20)

                    Button {
                        onVote(-1)
                    } label: {
                        Image(systemName: currentVote == -1 ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                            .foregroundStyle(currentVote == -1 ? Color.red : .secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canVote)

                    if let replies = comment.replyCount, replies > 0 {
                        Text("Ответов: \(replies)")
                            .font(.caption)
                            .foregroundStyle(.tint)
                    }
                }
                .font(.callout)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SpoilerText: View {
    let text: String
    @State private var revealed = false

    var body: some View {
        if revealed {
            Text(text)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Button {
                revealed = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "eye.slash")
                    Text("Спойлер — нажми, чтобы показать")
                }
                .font(.callout)
                .padding(8)
                .background(Color.secondary.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
    }
}
