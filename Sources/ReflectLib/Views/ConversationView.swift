import SwiftUI

// MARK: - View

/// The conversation home: the stored conversation list, the durable transcript
/// of the selected conversation, and a composer whose text is persisted as
/// that conversation's unsent draft.
///
/// Send, Stop, and retry-save are wired to the injected `ConversationService`.
/// Sending happens only on an explicit Send action; the service persists the
/// user message before any invocation, so the view clears the composer only
/// after the send is accepted, and it preserves the text whenever the message
/// save failed. Stop is offered while a run is active (once the durable user
/// message's request ID is observed) and retry-save never re-invokes.
///
/// The production convenience initializer still constructs its service over
/// the refusal-only transport, so production sends remain explicitly
/// unavailable: Send is disabled with an explanation and no provider can ever
/// be invoked from this view's production path.
public struct ConversationView: View {
    @StateObject private var model: ConversationModel

    /// Production entry point: builds the service over the default local store
    /// with the production approved-context provider and the user's settings
    /// configuration. The transport stays refusal-only in this slice, so the
    /// model is marked unavailable: Send never attempts an invocation.
    /// A store that cannot be opened produces the honest startup-failure state
    /// instead of an empty view.
    public init() {
        let persistence = PersistenceController(directory: PersistenceController.defaultDirectory())
        do {
            let service = try ConversationService(
                persistence: persistence,
                contextProvider: RetrievalConversationContextProvider(persistence: persistence),
                responder: UnavailableConversationTransport(),
                configuration: SettingsConversationConfigurationProvider {
                    (try? persistence.loadSettings()) ?? AppSettings.default()
                }
            )
            self.init(service: service, sendsUnavailable: true)
        } catch {
            self.init(startupFailure: Self.startupFailureMessage(from: error))
        }
    }

    /// Injected entry point for fixtures and tests: the caller owns the
    /// service and therefore the store location and the transport seams.
    /// Send, Stop, and retry-save are wired; the service remains the
    /// authoritative gate on every send. `sendsUnavailable: true` reproduces
    /// the production no-transport state for any service.
    public init(service: ConversationService, sendsUnavailable: Bool = false) {
        _model = StateObject(wrappedValue: ConversationModel(service: service, sendsUnavailable: sendsUnavailable))
    }

    private init(startupFailure: String) {
        _model = StateObject(wrappedValue: ConversationModel(startupFailure: startupFailure))
    }

    public var body: some View {
        Group {
            if let failure = model.startupFailure {
                startupFailureView(failure)
            } else {
                content
            }
        }
        .navigationTitle("Conversation")
        .background(ReflectPalette.page)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("conversationView")
        .task { await model.load() }
        .onDisappear { model.viewDidDisappear() }
    }

    // MARK: Layout

    private var content: some View {
        HSplitView {
            conversationListPane
                .frame(minWidth: 220, idealWidth: 250, maxWidth: 320, maxHeight: .infinity)

            transcriptPane
                .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 640, minHeight: 420)
    }

    private var conversationListPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Conversations")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await model.createConversation() }
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Create a new conversation")
                .accessibilityLabel("New Conversation")
                .accessibilityIdentifier("conversationNewButton")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if model.conversations.isEmpty {
                VStack(spacing: 8) {
                    Text("No conversations yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("New Conversation") {
                        Task { await model.createConversation() }
                    }
                    .accessibilityIdentifier("conversationListCreateButton")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: Binding(
                    get: { model.selectedConversationID },
                    set: { newValue in Task { await model.select(newValue) } }
                )) {
                    ForEach(model.conversations) { record in
                        ConversationListRow(record: record)
                            .tag(record.id)
                    }
                }
                .listStyle(.inset)
                .accessibilityIdentifier("conversationList")
                .accessibilityLabel("Conversations")
            }
        }
    }

    private var transcriptPane: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if model.conversations.isEmpty {
                noConversationsState
            } else if model.selectedConversationID == nil {
                Text("Select a conversation.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    transcript
                    requestStatus
                }

                Divider()

                composer
                    .disabled(model.selectedConversationID == nil)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Conversation")
                .font(.title2.weight(.semibold))
                .accessibilityIdentifier("conversationTitle")

            Text(headerExplanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("conversationExplanation")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .accessibilityElement(children: .combine)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if model.messages.isEmpty {
                        emptyTranscript
                    } else {
                        ForEach(model.messages) { message in
                            ConversationMessageRow(message: message)
                        }
                    }
                }
                .padding()
            }
            .onChange(of: model.messages) { _ in
                guard let last = model.messages.last else { return }
                proxy.scrollTo(last.id, anchor: .bottom)
            }
            .accessibilityIdentifier("conversationTranscript")
            .accessibilityLabel("Stored conversation messages")
        }
    }

    private var emptyTranscript: some View {
        VStack(spacing: 10) {
            Text("No messages yet in this conversation.")
                .font(.callout.weight(.medium))
            Text(emptyTranscriptExplanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("conversationEmptyTranscript")
        .accessibilityLabel("No messages yet in this conversation. \(emptyTranscriptExplanation)")
    }

    private var noConversationsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("No Conversations Yet")
                .font(.title3.weight(.medium))

            Text(noConversationsExplanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            Button("New Conversation") {
                Task { await model.createConversation() }
            }
            .accessibilityLabel("New Conversation")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("conversationEmptyState")
        .accessibilityLabel("No conversations yet. \(noConversationsExplanation)")
    }

    // MARK: Request status

    /// The honest run status strip between the transcript and the composer:
    /// a running state with Stop while this conversation's send is in flight,
    /// the interrupted state after a process ended mid-run, and the retained
    /// response retry when a generated response could not be saved. Durable
    /// canceled/failed/invalid outcomes are already rendered as notes on the
    /// request's own message row, so they are not duplicated here.
    @ViewBuilder
    private var requestStatus: some View {
        if let runningText = model.activeRunStatusText {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)

                Text(runningText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if model.canStopActiveRun {
                    Button("Stop") {
                        Task { await model.stopActiveRun() }
                    }
                    .controlSize(.small)
                    .help("Stop waiting for the response. Anything the agent already received cannot be retracted.")
                    .accessibilityIdentifier("conversationStopButton")
                    .accessibilityLabel("Stop sending")
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("conversationRunStatus")
        } else if model.showsInterruptedState {
            HStack(spacing: 8) {
                Text("This request was interrupted before an outcome was recorded. Whether it reached the agent is unknown.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("conversationInterruptedStatus")
        } else if model.canRetryResponseSave {
            HStack(spacing: 8) {
                Text("The response was generated but could not be saved. Retrying saves the same response without contacting the agent again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Retry") {
                    Task { await model.retryUnsavedResponse() }
                }
                .buttonStyle(.link)
                .font(.caption)
                .accessibilityLabel("Retry saving the response")
                .accessibilityIdentifier("conversationRetrySaveButton")

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("conversationRetryStatus")
        }
    }

    // MARK: Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let failure = model.actionFailure {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(alignment: .bottom, spacing: 10) {
                draftEditor

                Button {
                    Task { model.sendCurrentDraft() }
                } label: {
                    Label("Send", systemImage: "paperplane.fill")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canSend)
                .help(sendButtonHelp)
                .accessibilityIdentifier("conversationSendButton")
                .accessibilityLabel("Send")
            }

            if model.draftSaveFailed {
                HStack(spacing: 8) {
                    Text("Your draft could not be saved to the store. The text stays in the composer and is retried when you edit, switch conversations, or leave this view.")
                        .font(.caption)
                        .foregroundStyle(.red)
                    Button("Retry") {
                        Task { await model.persistDraftNow() }
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                    .accessibilityLabel("Retry saving the draft")
                }
            }

            Text(composerCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("conversationSendUnavailableNote")
        }
        .padding()
    }

    private var draftEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: Binding(
                get: { model.draft },
                set: { model.draftEdited(to: $0) }
            ))
            .font(.callout)
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(minHeight: 64, maxHeight: 120)
            .background(RoundedRectangle(cornerRadius: 8).fill(ReflectPalette.card))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(ReflectPalette.outline, lineWidth: 0.5)
            )
            .accessibilityLabel("Message draft")
            .accessibilityHint(composerAccessibilityHint)
            .accessibilityIdentifier("conversationComposer")

            if model.draft.isEmpty {
                Text("Write a message…")
                    .font(.callout)
                    .foregroundStyle(Color(nsColor: .placeholderTextColor))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: Copy

    private var headerExplanation: String {
        if model.sendsUnavailable {
            return "Sending is unavailable because conversation configuration is not ready. Drafts are saved locally."
        }
        return "Sending happens only when you choose Send and uses the configured agent with approved context only. Drafts are saved locally."
    }

    private var emptyTranscriptExplanation: String {
        if model.sendsUnavailable {
            return "Sending is unavailable because conversation configuration is not ready. Anything you write below is kept as this conversation's draft."
        }
        return "Anything you write below is kept as this conversation's draft until you send it."
    }

    private var noConversationsExplanation: String {
        if model.sendsUnavailable {
            return "Create a conversation to keep your writing and drafts in one place. Sending becomes available once conversation configuration is ready."
        }
        return "Create a conversation to keep your writing and drafts in one place, then send whenever you are ready."
    }

    private var sendButtonHelp: String {
        if model.sendsUnavailable {
            return "Sending is unavailable because conversation configuration is not ready."
        }
        if let reason = model.sendUnavailableReason {
            return reason
        }
        if model.isSending {
            return "A message is already being sent. You can stop it while it runs."
        }
        if model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Write a message first."
        }
        return "Send this message."
    }

    private var composerCaption: String {
        if model.sendsUnavailable {
            return "Sending is unavailable: conversation configuration is not ready. Your text is kept as a draft for this conversation."
        }
        if model.isSendingSendingElsewhere {
            return "A message is still being sent in another conversation, so sending is paused here until it finishes."
        }
        return "Your text is kept as a draft for this conversation until you send it."
    }

    private var composerAccessibilityHint: String {
        if model.sendsUnavailable {
            return "Your text is saved as a draft for this conversation. Sending is currently unavailable."
        }
        return "Your text is saved as a draft for this conversation until you send it."
    }

    private func startupFailureView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Conversations Unavailable")
                .font(.title3.weight(.medium))

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Conversations unavailable. \(message)")
    }

    private static func startupFailureMessage(from error: Error) -> String {
        if case let ConversationService.ServiceError.storeDamaged(message) = error {
            return message
        }
        return "The conversations store could not be opened, so conversations are unavailable right now. Recover the store from Settings and reopen this view."
    }
}

// MARK: - Rows

/// One conversation row in the list: creation date, message count, and the
/// last time the conversation changed (messages or draft).
private struct ConversationListRow: View {
    let record: ConversationRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Fmt.dateTime(record.createdAt))
                .font(.callout.weight(.medium))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Conversation created \(Fmt.dateTime(record.createdAt)). \(record.messageIDs.count) \(record.messageIDs.count == 1 ? "message" : "messages"). Updated \(Fmt.relative(record.updatedAt))."
        )
    }

    private var subtitle: String {
        let count = record.messageIDs.count
        let noun = count == 1 ? "message" : "messages"
        return "\(count) \(noun) · updated \(Fmt.relative(record.updatedAt))"
    }
}

/// One stored message. Yours carries the Design A teal dot; assistant messages
/// carry the outline diamond used for generated content, so speaker provenance
/// stays visually distinct without implying anything about competence.
private struct ConversationMessageRow: View {
    let message: ConversationMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            mark
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(message.speaker == .user ? "You" : "Assistant")
                        .font(.caption.weight(.semibold))
                    Text(Fmt.time(message.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(message.text)
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                if let note = outcomeNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(ReflectPalette.card))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(ReflectPalette.outline, lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var mark: some View {
        if message.speaker == .user {
            YourMark()
        } else {
            SuggestedMark()
        }
    }

    /// The durable request outcome, shown only when it is not a plain
    /// completed response. The notes are the store's own safe English.
    private var outcomeNote: String? {
        switch message.requestOutcome {
        case nil, .completed:
            return nil
        case .canceled:
            return "Stopped before a response was saved."
        case .failed(let note), .invalidResponse(let note), .responseSaveFailed(let note):
            return note
        }
    }

    private var accessibilityText: String {
        let speaker = message.speaker == .user ? "Your message" : "Assistant message"
        var text = "\(speaker) at \(Fmt.time(message.createdAt)): \(message.text)"
        if let note = outcomeNote {
            text += ". \(note)"
        }
        return text
    }
}

// MARK: - Model

/// Main-actor state for the conversation view. All reads and writes go through
/// the injected `ConversationService`; nothing here touches files directly,
/// invokes an agent, or reads imported histories.
///
/// Send lifecycle: an explicit Send snapshots the composer text and launches
/// `send` in a task. Because that call awaits the whole run, a watcher polls
/// the durable messages for the newly persisted user message and captures its
/// request ID — the earliest moment Stop can mean anything, since the service
/// invokes nothing before that message is saved — and then keeps polling
/// `requestState(_:)` and `messages(in:)` while the run stays active, so the
/// running, interrupted, completed, canceled, failed, invalid, and
/// response-save-failed states shown are always the service's own honest
/// derived state. Every completion and refresh is gated on the conversation
/// and request IDs it belongs to, so a late or out-of-order completion can
/// never land in another conversation's state. Selection changes and the view
/// disappearing flush the draft and stop only this UI polling; a running
/// provider request is never stopped implicitly.
@MainActor
final class ConversationModel: ObservableObject {
    @Published private(set) var conversations: [ConversationRecord] = []
    @Published private(set) var selectedConversationID: String?
    @Published private(set) var messages: [ConversationMessage] = []
    @Published private(set) var draft = ""
    @Published private(set) var draftSaveFailed = false
    @Published private(set) var actionFailure: String?
    /// Sticky safe reason from the most recent refused send. The view has no
    /// configuration read seam, so the service's authoritative per-send
    /// outcome is the only availability signal; the reason stays visible
    /// until the next attempt re-checks configuration.
    @Published private(set) var sendUnavailableReason: String?
    @Published private(set) var isSending = false
    @Published private(set) var activeRequestID: String?
    /// Derived state of the selected conversation's most recent request, as
    /// reported by the service. Request IDs gate every update.
    @Published private(set) var latestRequestState: ConversationRequestState?

    /// True only for the production entry point, whose responder is still
    /// refusal-only: Send stays disabled and explains itself, and no send is
    /// ever attempted, so no provider can be invoked from production.
    let sendsUnavailable: Bool

    /// Set only when the service itself could not be constructed (a damaged
    /// store): the view then shows this message instead of conversation UI.
    let startupFailure: String?

    private let service: ConversationService?
    private var draftSaveTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?
    private var requestWatchTask: Task<Void, Never>?
    private var hasLoaded = false
    /// The conversation whose send is in flight, if any. Gates every run
    /// status and completion so runs never cross conversations.
    private var sendingConversationID: String?
    /// The number of user messages in the sending conversation before the
    /// current send, so a watcher started at any time can identify the run's
    /// own newly persisted message by position.
    private var watchPriorUserMessageCount: Int?

    init(service: ConversationService, sendsUnavailable: Bool = false) {
        self.service = service
        self.sendsUnavailable = sendsUnavailable
        self.startupFailure = nil
    }

    init(startupFailure: String) {
        self.service = nil
        self.sendsUnavailable = true
        self.startupFailure = startupFailure
    }

    // MARK: Derived send state

    /// Send is offered only for an injected, wired service with a nonempty
    /// draft and no send in flight. Production (`sendsUnavailable`) never
    /// enables Send, and a refused configuration keeps the reason visible.
    var canSend: Bool {
        guard !sendsUnavailable, service != nil, !isSending else { return false }
        guard selectedConversationID != nil else { return false }
        return !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canStopActiveRun: Bool {
        isSending && activeRequestID != nil && service != nil
    }

    var canRetryResponseSave: Bool {
        guard let state = selectedRequestState else { return false }
        if case .responseSaveFailed = state.phase {
            return state.retryAvailable
        }
        return false
    }

    var showsInterruptedState: Bool {
        guard !isSending, let state = selectedRequestState else { return false }
        if case .interrupted = state.phase { return true }
        return false
    }

    /// The running-status text for the selected conversation, or nil when no
    /// run of this view is in flight there.
    var activeRunStatusText: String? {
        guard isSending, sendingConversationID == selectedConversationID else { return nil }
        return activeRequestID == nil
            ? "Saving your message…"
            : "Waiting for the response. You can stop while it runs."
    }

    /// True when a run is in flight in a conversation other than the one
    /// currently selected.
    var isSendingSendingElsewhere: Bool {
        isSending && sendingConversationID != selectedConversationID
    }

    var selectedRequestState: ConversationRequestState? {
        guard let state = latestRequestState, state.conversationID == selectedConversationID else { return nil }
        return state
    }

    // MARK: Loading and selection

    func load() async {
        guard let service, !hasLoaded else { return }
        hasLoaded = true
        let records = await service.conversations()
        conversations = records.sorted { $0.updatedAt > $1.updatedAt }
        if selectedConversationID == nil {
            selectedConversationID = conversations.first?.id
        }
        await refreshSelectedConversation()
    }

    func select(_ id: String?) async {
        guard id != selectedConversationID else { return }
        draftSaveTask?.cancel()
        draftSaveTask = nil
        // Stop this view's UI polling for the old conversation. The send
        // task and the service's run are never touched here: switching
        // conversations must not silently stop a running provider request.
        requestWatchTask?.cancel()
        requestWatchTask = nil

        var switchFailure: String?
        if let previousID = selectedConversationID {
            let saved = await saveDraft(draft, for: previousID)
            if !saved {
                switchFailure = "Your draft for the previous conversation could not be saved, so that text was not stored."
            }
        }

        selectedConversationID = id
        actionFailure = switchFailure
        await refreshSelectedConversation()
        resumeRunWatchIfNeeded()
    }

    private func refreshSelectedConversation() async {
        guard let service else { return }
        guard let id = selectedConversationID else {
            messages = []
            draft = ""
            latestRequestState = nil
            return
        }
        let currentMessages = await service.messages(in: id)
        guard selectedConversationID == id else { return }
        messages = currentMessages
        let storedDraft = conversations.first { $0.id == id }?.draftText ?? ""
        draft = storedDraft
        draftSaveFailed = false
        await refreshRequestState(for: currentMessages, conversationID: id)
    }

    /// Transcript-only refresh: never touches the composer text, so a mid-run
    /// or late refresh cannot clobber typing. Applies only while the same
    /// conversation stays selected.
    private func refreshTranscript(for conversationID: String) async {
        guard let service, selectedConversationID == conversationID else { return }
        let currentMessages = await service.messages(in: conversationID)
        guard selectedConversationID == conversationID else { return }
        messages = currentMessages
        await refreshRequestState(for: currentMessages, conversationID: conversationID)
    }

    /// Publishes the service's derived state for the most recent request of
    /// the given messages. The request ID gates the update: only a state that
    /// belongs to this conversation, while it is still selected, is published.
    private func refreshRequestState(for currentMessages: [ConversationMessage], conversationID: String) async {
        guard let service else { return }
        guard selectedConversationID == conversationID else { return }
        guard let requestID = currentMessages.last(where: { $0.speaker == .user })?.requestID else {
            latestRequestState = nil
            return
        }
        let state = await service.requestState(requestID)
        guard state?.requestID == requestID, state?.conversationID == conversationID, selectedConversationID == conversationID else { return }
        latestRequestState = state
    }

    // MARK: Creating

    func createConversation() async {
        guard let service else { return }
        await persistDraftNow()
        do {
            let record = try await service.createConversation()
            conversations.append(record)
            conversations.sort { $0.updatedAt > $1.updatedAt }
            selectedConversationID = record.id
            messages = []
            draft = ""
            draftSaveFailed = false
            latestRequestState = nil
            actionFailure = nil
        } catch {
            actionFailure = "The new conversation could not be created because saving failed. Nothing was added. Try again."
        }
    }

    // MARK: Send, stop, retry

    /// Explicit send: only this action starts a request. The composer text is
    /// left in place until the service accepts the message; a refused or
    /// failed send therefore keeps the draft exactly as typed.
    func sendCurrentDraft() {
        guard canSend, let service, let conversationID = selectedConversationID else { return }
        let submittedText = draft
        let priorUserMessageCount = messages.filter { $0.speaker == .user }.count
        isSending = true
        sendingConversationID = conversationID
        activeRequestID = nil
        actionFailure = nil
        watchPriorUserMessageCount = priorUserMessageCount

        sendTask = Task { [service] in
            let outcome = await service.send(submittedText, in: conversationID)
            await self.finishSend(outcome, submittedText: submittedText, conversationID: conversationID)
        }
        spawnRequestWatch(for: conversationID, service: service)
    }

    /// Starts the run watcher, if one is not already running. Only used for
    /// an in-flight run of this model.
    private func spawnRequestWatch(for conversationID: String, service: ConversationService) {
        guard requestWatchTask == nil, let priorUserMessageCount = watchPriorUserMessageCount else { return }
        requestWatchTask = Task { [service] in
            await self.watchForActiveRequest(
                conversationID: conversationID,
                priorUserMessageCount: priorUserMessageCount,
                service: service
            )
        }
    }

    /// Resumes UI polling when the conversation whose run is still in flight
    /// is selected again. Selection changes stop the poll only; the service's
    /// run keeps going, so returning re-engages the watcher with the same
    /// send-time snapshot and Stop stays available once the request ID is
    /// observed.
    private func resumeRunWatchIfNeeded() {
        guard let service, let conversationID = selectedConversationID,
              isSending, sendingConversationID == conversationID
        else { return }
        spawnRequestWatch(for: conversationID, service: service)
    }

    /// Watches the in-flight run for the sending conversation. First it polls
    /// the durable messages for the newly persisted user message to capture
    /// its request ID — the earliest moment a Stop can refer to anything,
    /// because the service invokes nothing before that save. It then polls
    /// `requestState(_:)` and `messages(in:)` while the run stays active so
    /// the visible states stay the service's own. Every update is gated on
    /// the conversation and request IDs it belongs to; the task is canceled
    /// by completion, selection change, or the view disappearing, never as a
    /// way to stop the provider request itself.
    private func watchForActiveRequest(
        conversationID: String,
        priorUserMessageCount: Int,
        service: ConversationService
    ) async {
        while !Task.isCancelled, isSending, sendingConversationID == conversationID, activeRequestID == nil {
            let current = await service.messages(in: conversationID)
            guard isSending, sendingConversationID == conversationID, activeRequestID == nil else { return }
            let userMessages = current.filter { $0.speaker == .user }
            if userMessages.count > priorUserMessageCount, let requestID = userMessages.last?.requestID {
                guard isSending, sendingConversationID == conversationID, activeRequestID == nil else { return }
                activeRequestID = requestID
                await refreshTranscript(for: conversationID)
                break
            }
            try? await Task.sleep(nanoseconds: 60_000_000)
        }

        while !Task.isCancelled, isSending, sendingConversationID == conversationID, activeRequestID != nil {
            await refreshTranscript(for: conversationID)
            guard isSending, sendingConversationID == conversationID else { return }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
    }

    /// One send's completion. Guarded on the sending conversation so a stale
    /// completion can never land in another conversation's state.
    private func finishSend(_ outcome: ConversationSendOutcome, submittedText: String, conversationID: String) async {
        guard sendingConversationID == conversationID else { return }
        isSending = false
        sendingConversationID = nil
        activeRequestID = nil
        watchPriorUserMessageCount = nil
        requestWatchTask?.cancel()
        requestWatchTask = nil
        sendTask = nil

        guard let service else { return }
        switch outcome {
        case .accepted(let requestID):
            // The user message is durably saved, so the composer may now be
            // cleared — but only if the composer still holds the submitted
            // text (or nothing): text typed during the run is a new draft and
            // stays. The durable draft is cleared with the same guard so the
            // composer and the stored draft never disagree; a failed clear
            // keeps the text and shows the draft-save failure.
            let composerHoldsSubmittedText = selectedConversationID != conversationID
                || draft.isEmpty
                || draft == submittedText
            if composerHoldsSubmittedText {
                let cleared = await saveDraft("", for: conversationID)
                if cleared, selectedConversationID == conversationID {
                    draft = ""
                }
            }
            await refreshTranscript(for: conversationID)
            let state = await service.requestState(requestID)
            guard state?.conversationID == conversationID, selectedConversationID == conversationID else { return }
            latestRequestState = state
        case .configurationUnavailable(let reason):
            sendUnavailableReason = reason
            actionFailure = reason
        case .saveFailed(let unsentText):
            if selectedConversationID == conversationID {
                draft = unsentText
            }
            actionFailure = "Your message could not be saved, so nothing was sent. The text stays in the composer."
        case .emptyMessage:
            actionFailure = "Write a message before sending."
        case .conversationNotFound:
            actionFailure = "This conversation no longer exists, so nothing was sent."
        case .runAlreadyActive:
            actionFailure = "A message is already being sent in this conversation."
        }
    }

    /// Stops the in-flight run for the captured request ID. The service
    /// records the honest canceled outcome; the send task then completes and
    /// `finishSend` refreshes the transcript with that durable state.
    func stopActiveRun() async {
        guard let service, isSending, let requestID = activeRequestID else { return }
        await service.stop(requestID: requestID)
    }

    /// Retries persisting a retained response. The service never contacts the
    /// agent again for this; without a retained response (for example after a
    /// relaunch) it reports that nothing can be saved.
    func retryUnsavedResponse() async {
        guard let service, let conversationID = selectedConversationID else { return }
        let outcome = await service.retryUnsavedResponse(in: conversationID)
        switch outcome {
        case .persisted:
            actionFailure = nil
            await refreshTranscript(for: conversationID)
        case .stillFailed:
            actionFailure = "The response still could not be saved. It stays retained only while Reflect is open; try again."
        case .noRetainedResponse:
            actionFailure = "There is no retained response to save for this conversation."
        }
    }

    // MARK: Drafts

    /// Composer edits: update the visible text and schedule a debounced
    /// durable save so drafts survive route changes and relaunches.
    func draftEdited(to text: String) {
        draft = text
        draftSaveTask?.cancel()
        guard let id = selectedConversationID else { return }
        let pending = text
        draftSaveTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await saveDraft(pending, for: id)
        }
    }

    /// Saves the current draft immediately (selection change, create, retry).
    func persistDraftNow() async {
        draftSaveTask?.cancel()
        draftSaveTask = nil
        guard let id = selectedConversationID else { return }
        _ = await saveDraft(draft, for: id)
    }

    /// Fire-and-forget flush when the view leaves the hierarchy: the draft is
    /// saved and this view's run polling stops, but a running provider request
    /// is never stopped here — the send task keeps going and its completion
    /// lands identity-gated in the model.
    func viewDidDisappear() {
        flushDraft()
        requestWatchTask?.cancel()
        requestWatchTask = nil
    }

    /// Fire-and-forget flush when the view leaves the hierarchy. A failed
    /// save is retried here too: the text stays in the composer either way.
    func flushDraft() {
        draftSaveTask?.cancel()
        draftSaveTask = nil
        guard let id = selectedConversationID else { return }
        let pending = draft
        Task { await saveDraft(pending, for: id) }
    }

    @discardableResult
    private func saveDraft(_ text: String, for id: String) async -> Bool {
        guard let service else { return false }
        do {
            try await service.setDraft(text.isEmpty ? nil : text, for: id)
            if selectedConversationID == id {
                draftSaveFailed = false
            }
            if let index = conversations.firstIndex(where: { $0.id == id }) {
                conversations[index].draftText = text.isEmpty ? nil : text
            }
            return true
        } catch {
            if selectedConversationID == id {
                draftSaveFailed = true
            }
            return false
        }
    }
}

// MARK: - Refusal-only transport

/// Refusal-only transport still used by the production convenience
/// initializer in this slice: production sending stays explicitly
/// unavailable, the view disables Send for it, so `respond` is never called.
/// It throws instead of producing a reply so a mistaken invocation can never
/// fabricate an assistant message or contact anything.
private struct UnavailableConversationTransport: ConversationResponding, Sendable {
    struct TransportUnavailable: Error {}

    func respond(to request: ConversationRequest, context: ContextEnvelope) async throws -> ConversationResponse {
        throw TransportUnavailable()
    }
}
