import SwiftUI

enum ExtensionStoreSort: String, CaseIterable {
    case installed
    case name

    var title: String {
        switch self {
        case .installed: return "Installed"
        case .name: return "By Name"
        }
    }

    var systemImage: String {
        switch self {
        case .installed: return "checkmark.circle"
        case .name: return "textformat"
        }
    }
}

struct ExtensionStoreSortButton: View {
    let sort: ExtensionStoreSort
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: sort.systemImage).symbolRenderingMode(.hierarchical)
                Text(sort.title)
                Image(systemName: "chevron.down").font(Theme.Typography.keyCap)
            }
            .font(Theme.Typography.bar)
            .foregroundStyle(Theme.Colors.textSecondary)
            .padding(.horizontal, Theme.Spacing.md)
            .frame(height: 28)
            .contentShape(Capsule())
            .background(Capsule().fill(hovered ? Theme.Colors.rowHover : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .fixedSize()
    }
}

struct ExtensionStoreItem: Identifiable {
    let id: String
    let package: ExtensionStorePackage?
    let installed: InstalledExtension?

    var title: String { package?.title ?? installed?.title ?? id }
    var description: String { package?.description ?? "Installed extension" }
}

struct ExtensionStorePaletteView: View {
    @ObservedObject private var store = AppCore.shared.extensionStore

    let items: [ExtensionStoreItem]
    let selection: Int
    let scroll: ListScrollIntent
    let onSelect: (Int) -> Void
    let onActivate: () -> Void
    let onActions: (Int) -> Void

    var body: some View {
        Group {
            if store.isLoadingCatalog && items.isEmpty {
                ProgressView("Loading extensions…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = store.lastError, items.isEmpty {
                EmptyResults(text: error)
            } else if items.isEmpty {
                EmptyResults(text: "No extensions found")
            } else {
                PaletteListLayout(
                    scroll: scroll,
                    scrollTarget: items.indices.contains(selection) ? items[selection].id : nil
                ) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            ExtensionStoreRow(
                                item: item,
                                isDownloading: item.package.map { store.downloadingNames.contains($0.name) } ?? false,
                                selected: index == selection,
                                onInstall: {
                                    onSelect(index)
                                    onActivate()
                                }
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(index) }
                            .onRightClick {
                                onSelect(index)
                                onActions(index)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.xs)
                    .padding(.bottom, Theme.Spacing.md)
                }
            }
        }
        .task {
            if store.remotePackages.isEmpty { store.refreshRemoteCatalog() }
        }
    }
}

private struct ExtensionStoreRow: View {
    let item: ExtensionStoreItem
    let isDownloading: Bool
    let selected: Bool
    let onInstall: () -> Void

    private var actionTitle: String {
        if isDownloading { return "Installing…" }
        guard let package = item.package else { return "Installed" }
        if item.installed?.report.version == package.version { return "Installed" }
        return item.installed == nil ? "Install" : "Update"
    }

    var body: some View {
        PaletteRow(selected: selected) {
            FeatureIcon(
                systemImage: "puzzlepiece.extension.fill",
                tint: Theme.Colors.systemAccent,
                size: Theme.Size.rowIcon
            )
        } content: {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(item.title)
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                Text(item.description)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(2)
            }
        } trailing: {
            Button(actionTitle, action: onInstall)
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
                .buttonStyle(.plain)
                .disabled(
                    isDownloading || item.package == nil
                        || item.installed?.report.version == item.package?.version)
        }
    }
}
