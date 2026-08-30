import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @State private var exportURL: URL?
    @State private var showShare = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Workouts")

                    ForEach(store.data.templates) { template in
                        NavigationLink {
                            TemplateEditorView(templateId: template.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.name)
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundColor(Palette.text)
                                    Text("\(template.items.count) exercises")
                                        .font(.system(size: 14))
                                        .foregroundColor(Palette.muted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundColor(Palette.ghost)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                            .frame(minHeight: Metrics.tap)
                            .background(Palette.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Palette.line, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Button("+ New workout") {
                        let template = WorkoutTemplate(name: "New workout", items: [])
                        store.data.templates.append(template)
                    }
                    .buttonStyle(BigButtonStyle())

                    SectionHeader(title: "Defaults")

                    LabeledField(label: "Rest timer (seconds)") {
                        RepsField(value: Binding(
                            get: { store.data.settings.defaultRestSec },
                            set: { store.data.settings.defaultRestSec = max(5, $0 ?? 90) }
                        ), placeholder: "90")
                    }

                    LabeledField(label: "Weight increase step (kg)") {
                        WeightField(value: Binding(
                            get: { store.data.settings.defaultIncrement },
                            set: { store.data.settings.defaultIncrement = max(0.5, $0 ?? 2.5) }
                        ), placeholder: "2.5")
                    }

                    SectionHeader(title: "Rest alerts")

                    if store.notificationsAllowed {
                        Text("Notifications on. Rest finishing will reach you with the app closed or the phone locked.")
                            .font(.system(size: 13))
                            .foregroundColor(Palette.muted)
                    } else {
                        Button("Enable rest-finished alerts") {
                            Task { await store.requestNotificationPermission() }
                        }
                        .buttonStyle(BigButtonStyle())

                        Text("Without this the timer still runs, but it can only buzz while the app is open.")
                            .font(.system(size: 13))
                            .foregroundColor(Palette.muted)
                    }

                    SectionHeader(title: "Backup")

                    Text("Exports everything — exercises, workouts and every session — as a JSON file.")
                        .font(.system(size: 13))
                        .foregroundColor(Palette.muted)

                    Button("Export all data (JSON)") {
                        exportURL = store.exportFile()
                        showShare = exportURL != nil
                    }
                    .buttonStyle(BigButtonStyle())

                    Text("All data lives on this phone only. Deleting the app erases it, so export now and then.")
                        .font(.system(size: 13))
                        .foregroundColor(Palette.muted)
                        .padding(.top, 12)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 24)
            }
            .navigationTitle("Settings")
            .screen()
            .sheet(isPresented: $showShare) {
                if let exportURL {
                    ShareSheet(items: [exportURL])
                }
            }
            .task { await store.refreshNotificationStatus() }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
