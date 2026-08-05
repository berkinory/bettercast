import SwiftUI

struct CalculatorSettingsView: View {
    @ObservedObject private var settings = AppCore.shared.settings
    @ObservedObject private var currencyRates = AppCore.shared.currencyRates
    @State private var askingConsent = false

    var body: some View {
        SettingsPane(
            title: "Calculator",
            subtitle: "Calculate directly from launcher search.",
            systemImage: "function",
            tint: Theme.Colors.calculatorAccent
        ) {
            SettingsFeatureToggleRow(
                title: "Calculator",
                systemImage: "function",
                tint: Theme.Colors.calculatorAccent,
                isEnabled: $settings.calculatorEnabled
            )

            SettingsSection(
                header: "Conversions",
                subtitle: "Choose which currency results the calculator can return.",
                systemImage: "arrow.left.arrow.right",
                tint: Theme.Colors.calculatorAccent
            ) {
                SettingsControlRow(
                    title: "Currency conversion",
                    subtitle: "Convert between supported fiat currencies.",
                    destination: .currencyConversion
                ) {
                    Toggle(
                        "Currency conversion",
                        isOn: Binding(
                            get: { settings.currencyConversionEnabled },
                            set: { enabled in setCurrencyConversionEnabled(enabled) }
                        )
                    )
                    .settingsToggle()
                }

                SettingsRowDivider()
                SettingsControlRow(
                    title: "Crypto conversion",
                    subtitle: "Include supported cryptocurrencies in conversions.",
                    destination: .cryptoConversion
                ) {
                    Toggle(
                        "Crypto conversion",
                        isOn: Binding(
                            get: { settings.cryptoConversionEnabled },
                            set: { enabled in setCryptoConversionEnabled(enabled) }
                        )
                    )
                    .settingsToggle()
                    .disabled(!settings.currencyConversionEnabled)
                }
            }
            .disabled(!settings.calculatorEnabled)
            .opacity(settings.calculatorEnabled ? 1 : 0.42)
        }
        .onChange(of: settings.calculatorEnabled) { _, enabled in
            if enabled, settings.currencyConversionEnabled {
                currencyRates.start(cryptoEnabled: settings.cryptoConversionEnabled)
            } else {
                currencyRates.stop()
            }
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
            Text("Allow currency rate downloads?")
                .font(Theme.Typography.headline)
            Text(consentText)
                .font(Theme.Typography.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Allow", action: onAccept)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: 420)
    }

    private var consentText: String {
        includeCrypto
            ? "Downloads fiat rates from Frankfurter and crypto rates from CoinGecko every three hours. Nothing you type is sent."
            : "Downloads fiat rates from Frankfurter every three hours. Nothing you type is sent."
    }
}
