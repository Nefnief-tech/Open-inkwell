import SwiftUI

struct SettingsView: View {
    @AppStorage("fingerDrawing") private var fingerDrawing = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $fingerDrawing) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Finger Drawing")
                            Text("When off, only the Apple Pencil draws — during character capture and while writing.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Drawing")
                } footer: {
                    Text("Palm rejection is automatic while the Apple Pencil is in use. The Apple Pencil (USB-C) supports tilt and low-latency input; pressure sensitivity is not available on this hardware model.")
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.4.0")
                    LabeledContent("Storage", value: "On device (Documents)")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
