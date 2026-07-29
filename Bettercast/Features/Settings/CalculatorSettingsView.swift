import SwiftUI

struct CalculatorSettingsView: View {
    @ObservedObject private var currencyRates = AppCore.shared.currencyRates
    @State private var askingConsent = false
    @State private var refreshing = false
    @State private var refreshFailed = false

    var body: some View {
        SettingsPane(
            title: "Calculator",
            subtitle: "Inline calculations and currency conversion.",
            systemImage: "function",
            tint: .green
        ) {
            SettingsSection(header: "Currency") {
                SettingsControlRow(
                    title: "Currency Conversion",
                    subtitle: conversionStatus,
                    systemImage: "dollarsign.arrow.circlepath",
                    tint: .green,
                    statusDot: currencyRates.isEnabled ? .green : nil,
                    destination: .currencyConversion
                ) {
                    if currencyRates.isEnabled {
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { true },
                                set: { enabled in
                                    if !enabled { currencyRates.setEnabled(false) }
                                }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    } else {
                        Button("Enable…") { askingConsent = true }
                            .controlSize(.small)
                    }
                }

                if currencyRates.isEnabled {
                    SettingsRowDivider()
                    SettingsControlRow(
                        title: "Exchange Rates",
                        subtitle: ratesStatus,
                        systemImage: "arrow.triangle.2.circlepath",
                        tint: .green,
                        destination: .exchangeRates
                    ) {
                        Button(refreshing ? "Updating…" : "Update Now") {
                            refreshing = true
                            Task {
                                let landed = await currencyRates.refreshNow()
                                refreshFailed = !landed
                                refreshing = false
                            }
                        }
                        .controlSize(.small)
                        .disabled(refreshing)
                    }
                }
            }

            SettingsStatusCard(
                title: currencyRates.isEnabled ? "Rates stay on this Mac" : "Offline by default",
                message: privacyStatus,
                systemImage: currencyRates.isEnabled ? "internaldrive" : "network.slash",
                tint: currencyRates.isEnabled ? .green : .secondary
            )
        }
        .sheet(isPresented: $askingConsent) {
            CurrencyConsentSheet(
                onCancel: { askingConsent = false },
                onAccept: {
                    askingConsent = false
                    currencyRates.setEnabled(true)
                }
            )
        }
    }

    private var conversionStatus: String {
        currencyRates.isEnabled
            ? "Convert inline: “100 dollars to yen” or “€20 to GBP”."
            : "Download daily rates to enable currency queries."
    }

    private var privacyStatus: String {
        if currencyRates.isEnabled {
            return
                "Bettercast downloads a daily rate table from \(CurrencyRateStore.provider). Nothing you type is sent."
        }
        return "No service is contacted until you explicitly enable currency conversion."
    }

    private var ratesStatus: String {
        if refreshing { return "Downloading the latest rates…" }
        if refreshFailed { return "Couldn't reach \(CurrencyRateStore.provider). Try again." }
        guard let fetched = currencyRates.rates?.fetchedAt else {
            return "\(CurrencyRateStore.provider) · not downloaded yet."
        }
        let stamp = fetched.formatted(date: .abbreviated, time: .shortened)
        return "\(CurrencyRateStore.provider) · updated \(stamp)."
    }
}

private struct CurrencyConsentSheet: View {
    let onCancel: () -> Void
    let onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            HStack(spacing: Theme.Spacing.lg) {
                Image(systemName: "network")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.green)
                Text("Turn on currency conversion?")
                    .font(.headline)
            }

            Text(
                "Bettercast downloads exchange rates from \(CurrencyRateStore.provider) once a day and "
                    + "keeps a copy on your Mac. No account, no identifiers, nothing you type. "
                    + "Turning it off deletes the cached rates."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Theme.Spacing.lg) {
                Link(destination: CurrencyRateStore.providerURL) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(CurrencyRateStore.providerURL.host() ?? "Provider")
                        Image(systemName: "arrow.up.right.square")
                    }
                    .font(.callout)
                }
                Spacer()
                Button("Not Now", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Enable", action: onAccept)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: 420)
    }
}
