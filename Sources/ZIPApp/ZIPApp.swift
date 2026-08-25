import AppKit
import SwiftUI

@main
struct ZIPApp: App {
    @NSApplicationDelegateAdaptor(ZipAppDelegate.self) private var appDelegate

    var body: some Scene { Settings { EmptyView() } }
}

@MainActor
final class ZipAppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { showHelper(for: $0) }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        showHelper(for: URL(fileURLWithPath: filename))
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func showHelper(for archive: URL) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = archive.lastPathComponent
        window.contentView = NSHostingView(rootView: ContentView(initialArchiveURL: archive))
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        windows.append(window)
    }
}

struct ContentView: View {
    private enum BackgroundResult<Value: Sendable>: Sendable {
        case success(Value)
        case passwordRequired
        case cancelled
        case failure(String)
    }

    private let initialArchiveURL: URL
    @State private var archiveURL: URL?
    @State private var entries: [ArchiveEntry] = []
    @State private var selected = Set<String>()
    @State private var message: String?
    @State private var password = ""
    @State private var pendingPasswordArchive: URL?
    @State private var passwordError: String?
    @State private var isShowingPasswordSheet = false
    @State private var isPickingDestination = false
    @State private var activeOperation: ArchiveOperation?
    @State private var operationLabel: String?

    init(initialArchiveURL: URL) {
        self.initialArchiveURL = initialArchiveURL
    }

    private var files: [ArchiveEntry] { entries.filter { !$0.isDirectory } }
    private var archiveTree: [ArchiveNode] { ArchiveTree.make(entries) }
    private var isMultiVolume: Bool { archiveURL.map(ArchiveVolume.isFirstPart) ?? false }
    private var isOperating: Bool { activeOperation != nil }

    var body: some View {
        NavigationSplitView {
            List {
                Section(L("sidebar.archive")) {
                    if let archiveURL {
                        Label(archiveURL.lastPathComponent, systemImage: "archivebox")
                            .lineLimit(2)
                        Text(String(format: L("sidebar.files"), files.count))
                            .foregroundStyle(.secondary)
                        if isMultiVolume {
                            Label(L("volume.set"), systemImage: "square.stack.3d.up")
                            Text(L("volume.helper"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section(L("sidebar.selection")) {
                    Label(String(format: L("sidebar.selected"), selected.count), systemImage: "checkmark.circle")
                    Button(L("deselect.all"), systemImage: "xmark.circle") { selected.removeAll() }
                        .disabled(selected.isEmpty || isOperating)
                }

                Section(L("sidebar.security")) {
                    if password.isEmpty {
                        Label(L("password.notSet"), systemImage: "lock")
                            .foregroundStyle(.secondary)
                    } else {
                        Label(L("password.inUse"), systemImage: "lock.fill")
                        Button(L("password.clear"), systemImage: "key.slash") { password = "" }
                    }
                    Text(L("password.helper"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            Group {
                if archiveURL == nil {
                    ContentUnavailableView(
                        L("helper.loading.title"),
                        systemImage: "archivebox",
                        description: Text(L("helper.loading.message"))
                    )
                } else {
                    Table(archiveTree, children: \.children, selection: $selected) {
                        TableColumn(L("table.name")) { node in
                            Label(nodeName(node), systemImage: nodeIcon(node))
                        }
                        .width(min: 300, ideal: 560)

                        TableColumn(L("table.size")) { node in
                            Text(sizeText(node.entry.size))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .width(min: 88, ideal: 104, max: 140)
                    }
                    .alternatingRowBackgrounds()
                }
            }
            .navigationTitle(archiveURL?.lastPathComponent ?? L("app.title"))
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        reloadArchive()
                    } label: {
                        Label(L("reload.archive"), systemImage: "arrow.clockwise")
                    }
                    .disabled(archiveURL == nil || isOperating)
                    .keyboardShortcut("r", modifiers: .command)

                    Button {
                        isPickingDestination = true
                    } label: {
                        Label(L("extract.selected"), systemImage: "archivebox")
                    }
                    .disabled(selected.isEmpty || isOperating)
                    .keyboardShortcut("e", modifiers: .command)
                }
            }
        }
        .frame(minWidth: 820, minHeight: 540)
        .safeAreaInset(edge: .bottom) {
            if let operationLabel {
                HStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                    Text(operationLabel)
                    Spacer()
                    Button(L("operation.cancel"), role: .cancel) { cancelOperation() }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)
            }
        }
        .fileImporter(isPresented: $isPickingDestination, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let destination = urls.first, let archiveURL else { return }
            extract(to: destination, archive: archiveURL)
        }
        .alert(L("app.title"), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button(L("ok"), role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
        .onAppear { open(initialArchiveURL, resetPassword: true) }
        .sheet(isPresented: $isShowingPasswordSheet, onDismiss: { passwordError = nil }) {
            passwordSheet
        }
    }

    private var passwordSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 28))
                .foregroundStyle(.tint)
            Text(L("password.title"))
                .font(.title2.weight(.semibold))
            Text(String(format: L("password.message"), pendingPasswordArchive?.lastPathComponent ?? ""))
                .foregroundStyle(.secondary)
            SecureField(L("password.placeholder"), text: $password)
                .textFieldStyle(.roundedBorder)
            if let passwordError {
                Text(passwordError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button(L("password.cancel"), role: .cancel) {
                    pendingPasswordArchive = nil
                    isShowingPasswordSheet = false
                }
                Button(L("password.open")) { openWithPassword() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
    }

    private func open(_ url: URL, resetPassword: Bool) {
        guard !isOperating else { return }
        if resetPassword { password = "" }
        let operation = ArchiveOperation()
        let currentPassword = password
        activeOperation = operation
        operationLabel = L("operation.listing")

        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> BackgroundResult<[ArchiveEntry]> in
                do {
                    return .success(try ArchiveEngine.shared.list(url, password: currentPassword, operation: operation))
                } catch is CancellationError {
                    return .cancelled
                } catch ArchiveError.passwordRequired {
                    return .passwordRequired
                } catch {
                    return .failure(error.localizedDescription)
                }
            }.value
            finishListing(result, archive: url, operation: operation)
        }
    }

    private func openWithPassword() {
        guard let pendingPasswordArchive else { return }
        isShowingPasswordSheet = false
        open(pendingPasswordArchive, resetPassword: false)
    }

    private func accept(_ listedEntries: [ArchiveEntry], from url: URL) {
        entries = listedEntries
        selected.removeAll()
        archiveURL = url
    }

    private func reloadArchive() {
        guard let archiveURL else { return }
        open(archiveURL, resetPassword: false)
    }

    private func extract(to destination: URL, archive: URL) {
        guard !isOperating else { return }
        let operation = ArchiveOperation()
        let paths = entries.filter { entry in
            !entry.isDirectory && selected.contains { selectedPath in
                entry.path == selectedPath || entry.path.hasPrefix(selectedPath + "/")
            }
        }.map(\.path)
        guard !paths.isEmpty else { return }
        let currentPassword = password
        activeOperation = operation
        operationLabel = L("operation.extracting")

        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> BackgroundResult<Void> in
                do {
                    try ArchiveEngine.shared.extract(paths, from: archive, to: destination, password: currentPassword, operation: operation)
                    return .success(())
                } catch is CancellationError {
                    return .cancelled
                } catch ArchiveError.passwordRequired {
                    return .passwordRequired
                } catch {
                    return .failure(error.localizedDescription)
                }
            }.value
            finishExtraction(result, archive: archive, paths: paths, operation: operation)
        }
    }

    private func finishListing(_ result: BackgroundResult<[ArchiveEntry]>, archive: URL, operation: ArchiveOperation) {
        guard activeOperation === operation else { return }
        activeOperation = nil
        operationLabel = nil
        switch result {
        case .success(let entries):
            passwordError = nil
            isShowingPasswordSheet = false
            accept(entries, from: archive)
        case .passwordRequired:
            pendingPasswordArchive = archive
            passwordError = password.isEmpty ? nil : L("password.wrong")
            isShowingPasswordSheet = true
        case .failure(let text):
            archiveURL = nil
            entries = []
            selected.removeAll()
            message = text
        case .cancelled:
            break
        }
    }

    private func finishExtraction(_ result: BackgroundResult<Void>, archive: URL, paths: [String], operation: ArchiveOperation) {
        guard activeOperation === operation else { return }
        activeOperation = nil
        operationLabel = nil
        switch result {
        case .success:
            message = String(format: L("extract.complete"), paths.count)
        case .passwordRequired:
            pendingPasswordArchive = archive
            passwordError = L("password.wrong")
            isShowingPasswordSheet = true
        case .failure(let text):
            message = text
        case .cancelled:
            break
        }
    }

    private func cancelOperation() {
        activeOperation?.cancel()
        activeOperation = nil
        operationLabel = nil
    }

    private func sizeText(_ size: Int64?) -> String {
        guard let size else { return "—" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private func nodeName(_ node: ArchiveNode) -> String {
        node.entry.path.components(separatedBy: "/").last ?? node.entry.path
    }

    private func nodeIcon(_ node: ArchiveNode) -> String {
        node.entry.isDirectory ? "folder" : "doc"
    }

}
