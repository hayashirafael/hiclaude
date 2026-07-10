import SwiftUI

struct GeneralTab: View {
    @ObservedObject var state: AppState
    private var strings: L10n { state.strings }

    var body: some View {
        Form {
            Section {
                if LoginItem.isSupported {
                    Toggle(strings.launchAtLogin, isOn: Binding(
                        get: { LoginItem.isEnabled },
                        set: { LoginItem.setEnabled($0) }))
                }
                Toggle(strings.remainingInMenuBar, isOn: $state.showRemainingInBar)
                Picker(strings.languageLabel, selection: $state.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.pickerTitle).tag(language)
                    }
                }
            } footer: {
                Text(strings.remainingInMenuBarFooter)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                LabeledContent(strings.version) {
                    Text(AppVersion.current)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .formStyle(.grouped)
    }
}
