import SwiftUI
import AppKit

public struct SettingsView: View {
    @EnvironmentObject private var store: AppStore

    @State private var newExclusion = ""
    @State private var showsPrivacyDetails = false
    @State private var showsLocalDataDetails: Bool
    @State private var showsAbout = false

    /// The synthetic UI fixture expands Local data so storage recovery states
    /// can be captured; the shipped app starts collapsed.
    public init(expandsLocalData: Bool = false) {
        _showsLocalDataDetails = State(initialValue: expandsLocalData)
    }

    private var readyAgents: [AnalysisAgentStatus] {
        store.analysisAgents.filter(\.isReady)
    }

    private var selectedAgent: AnalysisAgentStatus? {
        guard let kind = store.settings.analysisAgent else { return nil }
        return readyAgents.first { $0.kind == kind }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                analysisCard
                secondaryRows

                Button("About Reflect") {
                    showsAbout = true
                }
                .buttonStyle(.link)
                .padding(.leading, 4)
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 42)
            .padding(.top, 42)
            .padding(.bottom, 42)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(ReflectPalette.page)
        .navigationTitle("Settings")
        .onAppear {
            // Settings renders immediately; the first appearance checks once.
            // Later appearances keep the retained result and never relaunch
            // discovery on their own.
            store.ensureAnalysisAvailabilityChecked()
        }
        .onDisappear {
            // A pending check never blocks leaving or closing Settings; stop
            // it so no child process outlives the visible consumer.
            store.cancelAnalysisAvailabilityCheck()
        }
        .sheet(isPresented: $showsAbout) {
            AboutView()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Settings")
                .font(.system(size: 32, weight: .bold, design: .rounded))
            Text("Choose how Reflect reviews your selected evidence.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var analysisCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("AI analysis")
                    .font(.title2.weight(.bold))
                Text("Choose an agent already signed in on this Mac.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 26)
            .padding(.top, 24)
            .padding(.bottom, 18)

            analysisToggle
                .padding(.horizontal, 26)

            Divider()
                .padding(.horizontal, 26)
                .padding(.top, 18)

            Text("Available agents")
                .font(.headline)
                .padding(.horizontal, 26)
                .padding(.top, 18)
                .padding(.bottom, 10)

            if store.isCheckingAnalysisAgents {
                checkingRow
                    .padding(.horizontal, 26)
                    .padding(.bottom, 18)
            }

            if readyAgents.isEmpty {
                if !store.isCheckingAnalysisAgents {
                    // Honest three-state rendering: while checking show the
                    // checking row; before any completed check show a neutral
                    // state (a canceled or not-yet-run check found nothing
                    // YET — it did not find "no agents"); only after a
                    // completed check may the app claim none was found.
                    if store.analysisAgentsLastChecked == nil {
                        notCheckedYetState
                            .padding(.horizontal, 26)
                            .padding(.bottom, 18)
                    } else {
                        emptyAgentState
                            .padding(.horizontal, 26)
                            .padding(.bottom, 18)
                    }
                }
            } else {
                agentTiles
                    .padding(.horizontal, 26)
                    .padding(.bottom, 18)

                if let selectedAgent {
                    modelPicker(for: selectedAgent)
                        .padding(.horizontal, 26)
                        .padding(.bottom, 18)
                } else if store.settings.analysisAgent != nil {
                    Text("The saved agent is not currently ready on this Mac. Refresh availability or choose another agent.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 26)
                        .padding(.bottom, 18)
                }
            }

            if !store.isCheckingAnalysisAgents, let lastChecked = store.analysisAgentsLastChecked {
                Text("Last checked at \(lastChecked.formatted(date: .omitted, time: .standard)).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 26)
                    .padding(.bottom, 18)
            }

            privacyNote
                .padding(.horizontal, 26)
                .padding(.bottom, 24)
        }
        .background(ReflectPalette.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(ReflectPalette.outline, lineWidth: 1)
        }
    }

    /// Every control persists through the store's staged update API, so a
    /// failed preference write stays unpublished: the control re-reads the
    /// published value and the failure surfaces through `store.lastError`.
    private var analysisToggle: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(ReflectPalette.accent)
            Text("Analysis")
                .font(.body.weight(.medium))
            Spacer()
            Toggle("Analysis", isOn: Binding(
                get: { store.settings.aiEnabled },
                set: { enabled in store.updateSettings { $0.aiEnabled = enabled } }
            ))
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Analysis")
        .accessibilityValue(store.settings.aiEnabled ? "On" : "Off")
    }

    /// Shown while discovery is pending. Before any result exists this is the
    /// only agent state (checking, not "none found"); with retained results it
    /// says so explicitly instead of hiding the previous statuses.
    private var checkingRow: some View {
        let firstCheck = store.analysisAgents.isEmpty
        return HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 3) {
                Text(firstCheck ? "Checking for installed agents…" : "Refreshing agent availability…")
                    .font(.callout.weight(.medium))
                if let lastChecked = store.analysisAgentsLastChecked {
                    Text("Showing results from the last check at \(lastChecked.formatted(date: .omitted, time: .standard)).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(firstCheck ? "Checking for installed agents" : "Refreshing agent availability")
    }

    /// Neutral state before the first completed check: no result exists yet,
    /// so Reflect must not claim that no agent was found.
    private var notCheckedYetState: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("Agent availability hasn't been checked yet.")
                    .font(.callout.weight(.medium))
            }
            Text("Choose Refresh to check which supported agents are installed and signed in on this Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Refresh") {
                store.refreshAnalysisAvailability()
            }
            .accessibilityLabel("Refresh agent availability")
        }
        .padding(16)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }

    private var emptyAgentState: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("No supported authenticated agent found.")
                    .font(.callout.weight(.medium))
            }
            Text("Reflect shows an agent only after its supported CLI is installed and its documented local authentication check reports a signed-in account.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Refresh") {
                store.refreshAnalysisAvailability()
            }
            .accessibilityLabel("Refresh agent availability")
        }
        .padding(16)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }

    private var agentTiles: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                ForEach(readyAgents) { agentTile($0) }
            }
            VStack(spacing: 10) {
                ForEach(readyAgents) { agentTile($0) }
            }
        }
    }

    private func agentTile(_ status: AnalysisAgentStatus) -> some View {
        let isSelected = store.settings.analysisAgent == status.kind
        return Button {
            store.updateSettings { $0.analysisAgent = status.kind }
        } label: {
            HStack(spacing: 12) {
                AnalysisAgentIconView(kind: status.kind)
                VStack(alignment: .leading, spacing: 5) {
                    Text(status.kind.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Ready")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.green)
                    }
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(ReflectPalette.accent)
                        .accessibilityHidden(true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(
                isSelected ? ReflectPalette.accent.opacity(0.10) : Color.primary.opacity(0.025),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? ReflectPalette.accent : ReflectPalette.outline, lineWidth: isSelected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(status.kind.displayName), Ready")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .reflectClickableHover(RoundedRectangle(cornerRadius: 10))
    }

    private func modelPicker(for agent: AnalysisAgentStatus) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 14) {
                Text("Model")
                    .font(.body.weight(.medium))
                Spacer()
                Picker("Model", selection: modelBinding(for: agent.kind)) {
                    ForEach(agent.kind.modelOptions) { option in
                        Text(option.title).tag(option.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(minWidth: 190, alignment: .trailing)
            }
            Text("Models available from \(agent.kind.displayName)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
    }

    private func modelBinding(for kind: AnalysisAgentKind) -> Binding<String> {
        Binding(
            get: { store.settings.model(for: kind) ?? "" },
            set: { newValue in store.updateSettings { $0.setModel(newValue, for: kind) } }
        )
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.shield")
                .font(.title3)
                .foregroundStyle(ReflectPalette.yours)
            Text("Only selected evidence is sent when you press Run in Today. The chosen agent may send that evidence to its service using the account already signed in to that agent.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(ReflectPalette.yours.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    private var secondaryRows: some View {
        VStack(spacing: 0) {
            compactRow(
                icon: "doc.text",
                title: "Privacy & exclusions",
                actionTitle: showsPrivacyDetails ? "Hide" : "Manage",
                action: { showsPrivacyDetails.toggle() }
            )

            if showsPrivacyDetails {
                privacyDetails
            }

            Divider()

            compactRow(
                icon: "externaldrive",
                title: "Local data",
                actionTitle: showsLocalDataDetails ? "Hide" : "Open",
                action: { showsLocalDataDetails.toggle() }
            )

            if showsLocalDataDetails {
                localDataDetails
            }
        }
        .background(ReflectPalette.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(ReflectPalette.outline, lineWidth: 1)
        }
    }

    private func compactRow(icon: String, title: String, actionTitle: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 24)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.body.weight(.medium))
            Spacer()
            Button(actionTitle, action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("\(actionTitle) \(title)")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var privacyDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Any path containing one of these tokens is skipped during imports. Matching is case-insensitive. Exclusions apply before anything is read.")
                .font(.callout)
                .foregroundStyle(.secondary)

            ForEach(store.settings.exclusions, id: \.self) { token in
                HStack {
                    Text(token)
                        .font(.callout.monospaced())
                    Spacer()
                    Button(role: .destructive) {
                        store.updateSettings { $0.exclusions.removeAll { $0 == token } }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove exclusion \(token)")
                }
            }

            HStack {
                TextField("Add exclusion token", text: $newExclusion)
                    .onSubmit(addExclusion)
                Button("Add", action: addExclusion)
                    .disabled(newExclusion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Text("All processing is local during import. Personal session data is never copied into the app bundle or repository.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 16)
    }

    private var localDataDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            StorageHealthSection()
            Text(store.dataDirectory.path)
                .font(.caption.monospaced())
                .textSelection(.enabled)
            HStack {
                Button("Reveal data folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([store.dataDirectory])
                }
                Button("Re-count sources") {
                    store.refreshAvailability()
                }
            }
            Text("Events, corrections, reports, settings, and import state stay in Reflect's Application Support folder.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 16)
    }

    private func addExclusion() {
        let token = newExclusion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        if !store.settings.exclusions.contains(token) {
            store.updateSettings { $0.exclusions.append(token) }
        }
        newExclusion = ""
    }
}

private struct AnalysisAgentIconView: View {
    let kind: AnalysisAgentKind

    var body: some View {
        Group {
            if let image = AnalysisAgentIconResolver.image(for: kind) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: kind.iconSystemName)
                    .font(.title2)
                    .foregroundStyle(ReflectPalette.accent)
            }
        }
        .frame(width: 42, height: 42)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityHidden(true)
    }
}
