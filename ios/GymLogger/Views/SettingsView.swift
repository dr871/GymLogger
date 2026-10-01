import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var store: Store
    /// The file to share, carried into the sheet by `.sheet(item:)`. With
    /// `isPresented` the sheet's content closure is captured before the new
    /// URL lands, so it opened empty with nothing to share.
    @State private var pendingExport: ExportFile?
    @State private var exportError: String?

    struct ExportFile: Identifiable {
        let id = UUID()
        let url: URL
    }
    @State private var showImporter = false
    @State private var pendingRestore: Store.PendingRestore?
    @State private var confirmRestore = false
    @State private var restoreError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Workouts")

                    NavigationLink {
                        WorkoutsView()
                    } label: {
                        WorkoutRow(
                            name: "Workouts",
                            detail: "\(store.data.templates.count) workout\(store.data.templates.count == 1 ? "" : "s") · design and edit"
                        )
                    }
                    .buttonStyle(.plain)

                    SectionHeader(title: "Defaults")

                    LabeledField(label: "Rest timer (seconds)") {
                        RepsField(value: Binding(
                            get: { store.data.settings.defaultRestSec },
                            set: { if let v = $0 { store.data.settings.defaultRestSec = v } }
                        ), placeholder: "90")
                    }

                    SectionHeader(title: "Rest alerts")

                    if store.notificationsAllowed {
                        Text("Notifications on. Rest finishing will reach you with the app closed or the phone locked.")
                            .font(.app(13))
                            .foregroundStyle(Palette.muted)
                    } else if store.notificationsDenied {
                        // iOS returns false without a prompt once denied; the
                        // only route back is the system Settings page.
                        Button("Turn on alerts in Settings") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .buttonStyle(BigButtonStyle())
                    } else {
                        Button("Enable rest-finished alerts") {
                            Task { await store.requestNotificationPermission() }
                        }
                        .buttonStyle(BigButtonStyle())

                        Text("Without this the timer still runs, but it can only buzz while the app is open.")
                            .font(.app(13))
                            .foregroundStyle(Palette.muted)
                    }

                    SectionHeader(title: "Backup")

                    Text("Exports everything — exercises, workouts and every session — as a JSON file.")
                        .font(.app(13))
                        .foregroundStyle(Palette.muted)

                    Button("Export all data (JSON)") {
                        if let url = store.exportFile() {
                            pendingExport = ExportFile(url: url)
                        } else {
                            // Never fail silently: the whole point of this
                            // button is getting the history off the phone.
                            exportError = "The backup file couldn't be written. Free up some space and try again."
                        }
                    }
                    .buttonStyle(BigButtonStyle())

                    Text(exportStatus)
                        .font(.app(13))
                        .foregroundStyle(Palette.muted)

                    Text("A copy is also kept up to date in the Files app: On My iPhone › GymLogger › GymLogger-backup.json.")
                        .font(.app(13))
                        .foregroundStyle(Palette.muted)
                        .padding(.top, 12)

                    SectionHeader(title: "Restore")

                    Text("Loads a backup file and replaces everything on this phone with it. You'll see what's in the file before anything changes.")
                        .font(.app(13))
                        .foregroundStyle(Palette.muted)

                    Button("Restore from backup…") { showImporter = true }
                        .buttonStyle(BigButtonStyle())

                    Text("All data lives on this phone only. Deleting the app erases it.")
                        .font(.app(13))
                        .foregroundStyle(Palette.muted)
                        .padding(.top, 12)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 24)
            }
            .navigationTitle("Settings")
            .screen()
            .sheet(item: $pendingExport) { export in
                ShareSheet(items: [export.url]) { completed in
                    if completed { store.markExported() }
                }
            }
            .alert("Can't export", isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportError ?? "")
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    do {
                        pendingRestore = try store.previewRestore(url: url)
                        confirmRestore = true
                    } catch RestoreError.tooNew(let fileVersion, _) {
                        restoreError = "That backup was made by a newer version of GymLogger (format \(fileVersion)). Update the app, then restore — loading it here would quietly drop whatever this version doesn't understand."
                    } catch RestoreError.empty {
                        restoreError = "That file has no exercises or sessions in it, so there is nothing to restore."
                    } catch {
                        restoreError = "That file isn't a GymLogger backup, or it couldn't be read."
                    }
                case .failure:
                    restoreError = "Couldn't open that file."
                }
            }
            .alert("Replace everything on this phone?", isPresented: $confirmRestore, presenting: pendingRestore) { pending in
                Button("Replace", role: .destructive) { store.commitRestore(pending) }
                Button("Cancel", role: .cancel) {}
            } message: { pending in
                Text(restoreSummary(pending.preview))
            }
            .alert("Can't restore", isPresented: Binding(
                get: { restoreError != nil },
                set: { if !$0 { restoreError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(restoreError ?? "")
            }
            .task { await store.refreshNotificationStatus() }
        }
    }

    private var exportStatus: String {
        guard let days = store.daysSinceExport else { return "Never exported off this phone." }
        if days == 0 { return "Last exported today." }
        return "Last exported \(days) day\(days == 1 ? "" : "s") ago."
    }

    /// What the file holds versus what it will overwrite, in one breath.
    private func restoreSummary(_ p: RestorePreview) -> String {
        var lines = ["The backup has \(p.exerciseCount) exercises, \(p.templateCount) workout\(p.templateCount == 1 ? "" : "s") and \(p.sessionCount) finished session\(p.sessionCount == 1 ? "" : "s")."]
        if let first = p.firstSession, let last = p.lastSession {
            lines.append("Sessions run from \(Format.date(first)) to \(Format.date(last)).")
        }
        let current = store.data.finishedSessions.count
        lines.append("This replaces the \(current) session\(current == 1 ? "" : "s") currently on this phone. Export first if you want to keep them.")
        return lines.joined(separator: "\n\n")
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    /// Called with true only when the user actually completed a share, so the
    /// "last exported" record isn't set by merely opening and dismissing.
    var onFinish: (Bool) -> Void = { _ in }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in onFinish(completed) }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
