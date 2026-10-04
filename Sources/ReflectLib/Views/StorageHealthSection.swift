import SwiftUI

/// Concise storage status surface: lists stores that could not be read and
/// offers an explicit, confirmable recovery action per store. Recovery always
/// preserves a verified backup of the damaged bytes before anything changes.
public struct StorageHealthSection: View {
    @EnvironmentObject private var store: AppStore
    @State private var pendingRecovery: StoreName?

    public init() {}

    public var body: some View {
        if !store.storeFailures.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Storage needs attention")
                        .font(.callout.weight(.semibold))
                }

                ForEach(failedStores, id: \.self) { name in
                    row(for: name)
                }

                if let message = store.lastRecoveryMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Damaged files are never overwritten by ordinary saves. Recovery first keeps a verified backup copy in Reflect's data folder, then starts a fresh store.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Storage needs attention")
        }
    }

    private var failedStores: [StoreName] {
        store.storeFailures.keys.sorted { $0.rawValue < $1.rawValue }
    }

    private func row(for name: StoreName) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(name.displayName) store could not be read")
                .font(.callout.weight(.medium))
            Text(store.storeFailures[name]?.userMessage ?? "")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Recover \(name.displayName)…") {
                pendingRecovery = name
            }
            .accessibilityLabel("Recover the \(name.displayName) store")
            .confirmationDialog(
                "Back up and start a fresh \(name.displayName) store?",
                isPresented: recoveryPresented(for: name),
                titleVisibility: .visible
            ) {
                Button("Back Up and Start Fresh", role: .destructive) {
                    store.recoverStore(name)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Reflect copies the damaged file into your Reflect data folder first, then starts a fresh store. The copy stays in the Damaged Backups folder.")
            }
        }
    }

    private func recoveryPresented(for name: StoreName) -> Binding<Bool> {
        Binding(
            get: { pendingRecovery == name },
            set: { if !$0 { pendingRecovery = nil } }
        )
    }
}
