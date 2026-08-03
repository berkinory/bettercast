import SwiftUI

struct ExtensionStoreView: View {
    @ObservedObject private var store = AppCore.shared.extensionStore

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Extension Store")
                        .font(Theme.Typography.title3Semibold)
                    Text("Packages are downloaded from GitHub Releases. No store backend is used.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
                if store.storeNetworkConsentGranted {
                    Button("Disable") { store.setStoreNetworkConsent(false) }
                        .controlSize(.small)
                }
                Button("Refresh") { store.refreshRemoteCatalog() }
                    .disabled(!store.storeNetworkConsentGranted || store.isLoadingCatalog)
            }

            if !store.storeNetworkConsentGranted {
                consentCard
            } else if store.isLoadingCatalog {
                ProgressView("Loading catalog…")
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if store.remotePackages.isEmpty {
                EmptyResults(text: "No verified extensions are available.")
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.sm) {
                        ForEach(store.remotePackages) { package in
                            packageRow(package)
                        }
                    }
                }
                .overlayScroller(disablesElasticity: true)
            }

            if let error = store.lastError {
                Text(error)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.destructive)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 560, height: 460)
        .background(Theme.Colors.panelSurface)
        .task {
            if store.storeNetworkConsentGranted { store.refreshRemoteCatalog() }
        }
    }

    private var consentCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Allow Extension Store downloads")
                .font(Theme.Typography.calloutMedium)
            Text(
                "Opencast will contact GitHub to read a static catalog and download verified .ocx packages only when you choose to install one."
            )
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
            Button("Allow & Refresh") {
                guard
                    NativeConfirmation.show(
                        message: "Allow Extension Store downloads?",
                        informativeText:
                            "Opencast will contact GitHub Releases for the static catalog and selected extension packages.",
                        primaryTitle: "Allow",
                        secondaryTitle: "Cancel"
                    ) == .primary
                else { return }
                store.setStoreNetworkConsent(true)
                store.refreshRemoteCatalog()
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private func packageRow(_ package: ExtensionStorePackage) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            FeatureIcon(systemImage: "puzzlepiece.extension", tint: Theme.Colors.systemAccent, size: Theme.Size.rowIcon)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(package.title)
                    .font(Theme.Typography.calloutMedium)
                Text("v\(package.version) · \(package.description)")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
            Button(actionTitle(for: package)) { store.installRemote(package) }
                .controlSize(.small)
                .disabled(
                    store.downloadingNames.contains(package.name) || installedVersion(for: package) == package.version)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private func installedVersion(for package: ExtensionStorePackage) -> String? {
        store.installed.first(where: { $0.name == package.name })?.report.version
    }

    private func actionTitle(for package: ExtensionStorePackage) -> String {
        if store.downloadingNames.contains(package.name) { return "Installing…" }
        if installedVersion(for: package) == package.version { return "Installed" }
        return installedVersion(for: package) == nil ? "Install" : "Update"
    }
}
