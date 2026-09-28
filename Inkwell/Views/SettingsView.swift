import SwiftUI

struct SettingsView: View {
    @AppStorage("fingerDrawing") private var fingerDrawing = true
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $fingerDrawing) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Finger Drawing")
                            Text("When off, only the Apple Pencil draws — fingers scroll.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Drawing")
                } footer: {
                    Text("Palm rejection is automatic while the Apple Pencil is in use. The Apple Pencil (USB-C) supports tilt and low-latency input; pressure sensitivity is not available on this hardware model.")
                }

                Section("Library") {
                    LabeledContent("Notebooks", value: "\(library.notebooks.count)")
                    LabeledContent("Pages", value: "\(library.notebooks.reduce(0) { $0 + $1.pages.count })")
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.0")
                    LabeledContent("Storage", value: "On device (Documents/Notebooks)")
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
