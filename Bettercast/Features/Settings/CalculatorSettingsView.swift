import SwiftUI

struct CalculatorSettingsView: View {
    @ObservedObject private var settings = AppCore.shared.settings
    @ObservedObject private var currencyRates = AppCore.shared.currencyRates
    @State private var askingConsent = false

    var body: some View {
        SettingsPane(
            title: "Calculator",
            subtitle: "Inline calculations, currency, crypto, and dates.",
            systemImage: "function",
            tint: .green
        ) {
            SettingsSection(header: "Currency") {
                SettingsControlRow(
                    title: "Currency Conversion",
                    subtitle: conversionStatus,
                    systemImage: "dollarsign.arrow.circlepath",
                    tint: .green,
                    statusDot: settings.currencyConversionEnabled && currencyRates.isEnabled ? .green : nil,
                    destination: .currencyConversion
                ) {
                    HStack(spacing: Theme.Spacing.sm) {
                        if settings.currencyConversionEnabled && !currencyRates.isEnabled {
                            Button("Enable Rates…") { askingConsent = true }
                                .controlSize(.small)
                        }
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { settings.currencyConversionEnabled },
                                set: { enabled in setCurrencyConversionEnabled(enabled) }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                }

                SettingsRowDivider()
                SettingsControlRow(
                    title: "Crypto Conversion",
                    subtitle: cryptoStatus,
                    systemImage: "bitcoinsign.circle",
                    tint: .orange,
                    statusDot: settings.cryptoConversionEnabled && currencyRates.isEnabled
                        ? (currencyRates.lastCryptoSync == nil ? .yellow : .green)
                        : nil,
                    destination: .cryptoConversion
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { settings.cryptoConversionEnabled },
                            set: { enabled in setCryptoConversionEnabled(enabled) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(!settings.currencyConversionEnabled)
                }
            }

            SettingsStatusCard(
                title: currencyRates.isEnabled ? "Rates stay on this Mac" : "Offline until enabled",
                message: privacyStatus,
                systemImage: currencyRates.isEnabled ? "internaldrive" : "network.slash",
                tint: currencyRates.isEnabled ? .green : .secondary
            )
        }
        .sheet(isPresented: $askingConsent) {
            CurrencyConsentSheet(
                includeCrypto: settings.cryptoConversionEnabled,
                onCancel: { askingConsent = false },
                onAccept: {
                    askingConsent = false
                    settings.currencyConversionEnabled = true
                    currencyRates.setEnabled(true)
                    currencyRates.start(cryptoEnabled: settings.cryptoConversionEnabled)
                }
            )
        }
    }

    private var conversionStatus: String {
        guard settings.currencyConversionEnabled else {
            return "Off · Last sync: \(syncText(currencyRates.lastFiatSync))"
        }
        guard currencyRates.isEnabled else {
            return "Enable fiat rates · Last sync: Never"
        }
        return "Frankfurter · Last sync: \(syncText(currencyRates.lastFiatSync))"
    }

    private var cryptoStatus: String {
        guard settings.cryptoConversionEnabled else {
            return "Off by default · Last sync: Never"
        }
        guard currencyRates.isEnabled else { return "Enable currency rates first · Last sync: Never" }
        return "CoinGecko · Last sync: \(syncText(currencyRates.lastCryptoSync))"
    }

    private var privacyStatus: String {
        guard settings.currencyConversionEnabled else {
            return "Currency conversion is off. No exchange-rate requests are made."
        }
        guard currencyRates.isEnabled else {
            return "Currency conversion is enabled, but rates remain offline until you approve the provider."
        }
        if settings.cryptoConversionEnabled {
            return
                "Fiat rates come from Frankfurter and crypto rates from CoinGecko every three hours. Nothing you type is sent."
        }
        return
            "Fiat rates come from Frankfurter every three hours. CoinGecko is disabled, so no crypto request is made."
    }

    private func syncText(_ date: Date?) -> String {
        guard let date else { return "Never" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func setCurrencyConversionEnabled(_ enabled: Bool) {
        if enabled {
            guard currencyRates.isEnabled else {
                askingConsent = true
                return
            }
            settings.currencyConversionEnabled = true
            currencyRates.start(cryptoEnabled: settings.cryptoConversionEnabled)
        } else {
            settings.currencyConversionEnabled = false
            currencyRates.stop()
        }
    }

    private func setCryptoConversionEnabled(_ enabled: Bool) {
        settings.cryptoConversionEnabled = enabled
        currencyRates.setCryptoEnabled(enabled)
    }
}

private struct CurrencyConsentSheet: View {
    let includeCrypto: Bool
    let onCancel: () -> Void
    let onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            HStack(spacing: Theme.Spacing.lg) {
                Image(systemName: "network")
                    .font(Theme.Typography.iconXL)
                    .foregroundStyle(.green)
                Text("Enable exchange rates?")
                    .font(Theme.Typography.headline)
            }

            Text(consentText)
                .font(Theme.Typography.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Theme.Spacing.lg) {
                Link(destination: CurrencyRateStore.providerURL) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(CurrencyRateStore.providerURL.host() ?? "Provider")
                        Image(systemName: "arrow.up.right.square")
                    }
                    .font(Theme.Typography.callout)
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

    private var consentText: String {
        let providers =
            includeCrypto
            ? "fiat rates from Frankfurter and crypto rates from CoinGecko" : "fiat rates from Frankfurter"
        return
            "Bettercast downloads \(providers) every three hours and keeps a copy on your Mac. No account, no identifiers, and nothing you type is sent. Turning it off deletes the cached rates."
    }
}
