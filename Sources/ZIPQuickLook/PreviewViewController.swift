import AppKit
import QuickLookUI
import OSLog

final class PreviewViewController: NSViewController, @MainActor QLPreviewingController {
    private let logger = Logger(subsystem: "ru.dedlyosha.ZIP.QuickLook", category: "preview")
    private var archiveURL: URL?
    private var checkboxes: [NSButton] = []
    private let stack = NSStackView()
    private let scroll = NSScrollView()
    private let status = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let extract = NSButton(title: "", target: nil, action: nil)

    override var nibName: NSNib.Name? {
        NSNib.Name("PreviewViewController")
    }

    override func loadView() {
        logger.notice("loadView")
        super.loadView()
        view.autoresizesSubviews = true

        titleLabel.stringValue = localized("quicklook.title")
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.frame = NSRect(x: 18, y: 440, width: 684, height: 24)
        titleLabel.autoresizingMask = [.width, .minYMargin]
        view.addSubview(titleLabel)

        scroll.frame = NSRect(x: 18, y: 64, width: 684, height: 364)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = stack
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        stack.frame = NSRect(x: 0, y: 0, width: 684, height: 1)
        view.addSubview(scroll)

        extract.title = localized("quicklook.extract")
        extract.target = self
        extract.action = #selector(chooseDestinationAndExtract)
        extract.frame = NSRect(x: 18, y: 16, width: 190, height: 32)
        extract.autoresizingMask = [.maxXMargin, .maxYMargin]
        view.addSubview(extract)

        status.frame = NSRect(x: 220, y: 20, width: 482, height: 22)
        status.autoresizingMask = [.width, .maxYMargin]
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingMiddle
        view.addSubview(status)

        preferredContentSize = view.frame.size
        logger.notice("loaded nib view \(self.view.frame.width)x\(self.view.frame.height)")
    }

    func preparePreviewOfFile(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        logger.notice("preparePreview: \(url.lastPathComponent, privacy: .public)")
        archiveURL = url
        clearContent()
        showArchive()
        do {
            let paths = try listFiles(in: url)
            logger.notice("listed \(paths.count) files")
            checkboxes = paths.map { path in
                let checkbox = NSButton(checkboxWithTitle: path, target: nil, action: nil)
                checkbox.state = .on
                checkbox.tag = 0
                checkbox.identifier = NSUserInterfaceItemIdentifier(path)
                stack.addArrangedSubview(checkbox)
                return checkbox
            }
            let contentHeight = max(1, paths.count) * 26 + 16
            stack.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: CGFloat(contentHeight))
            stack.needsLayout = true
            stack.layoutSubtreeIfNeeded()
            logger.notice("view frame \(self.view.frame.width)x\(self.view.frame.height), stack \(self.stack.frame.width)x\(self.stack.frame.height)")
            completionHandler(nil)
        } catch {
            logger.error("prepare failed: \(String(reflecting: error), privacy: .public)")
            completionHandler(error)
        }
    }

    private func clearContent() {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        checkboxes = []
        status.stringValue = ""
    }

    private func showArchive() {
        titleLabel.stringValue = localized("quicklook.title")
        extract.isHidden = false
        extract.isEnabled = true
    }

    @objc private func chooseDestinationAndExtract() {
        guard let archiveURL else { return }
        let selected = checkboxes.compactMap { $0.state == .on ? $0.identifier?.rawValue : nil }
        guard !selected.isEmpty else {
            status.stringValue = localized("quicklook.nothingSelected")
            return
        }
        logger.notice("choose destination for \(selected.count) files")

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = archiveURL.deletingLastPathComponent()
        panel.prompt = localized("quicklook.chooseDestination")
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            self?.logger.notice("destination panel response \(response.rawValue)")
            guard response == .OK, let destination = panel.url else { return }
            self?.extract(selected, from: archiveURL, to: destination)
        }
        if let window = view.window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    private func extract(_ selected: [String], from archive: URL, to destination: URL) {
        let archiveAccess = archive.startAccessingSecurityScopedResource()
        let destinationAccess = destination.startAccessingSecurityScopedResource()
        defer {
            if archiveAccess { archive.stopAccessingSecurityScopedResource() }
            if destinationAccess { destination.stopAccessingSecurityScopedResource() }
        }

        let duplicatedPaths = selected.compactMap { strdup($0) }
        defer {
            for pointer in duplicatedPaths { free(pointer) }
        }
        guard duplicatedPaths.count == selected.count else {
            status.stringValue = String.localizedStringWithFormat(
                localized("quicklook.extractFailed"),
                localized("quicklook.cannotRead")
            )
            return
        }
        let pathPointers: [UnsafePointer<CChar>?] = duplicatedPaths.map { UnsafePointer($0) }
        let extracted = archive.path.withCString { archivePath in
            destination.path.withCString { destinationPath in
                pathPointers.withUnsafeBufferPointer { buffer in
                    ZIPArchiveExtractSelected(archivePath, destinationPath, buffer.baseAddress, buffer.count)
                }
            }
        }
        if extracted >= 0 {
            status.stringValue = String.localizedStringWithFormat(localized("quicklook.extractComplete"), Int(extracted))
        } else {
            let detail = ZIPArchiveLastError().map(String.init(cString:)) ?? localized("quicklook.cannotRead")
            status.stringValue = String.localizedStringWithFormat(localized("quicklook.extractFailed"), detail)
        }
    }

    private func listFiles(in archive: URL) throws -> [String] {
        let hasSecurityScope = archive.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope { archive.stopAccessingSecurityScopedResource() }
        }
        guard let reader = archive.path.withCString({ ZIPArchiveReaderCreate($0) }) else {
            throw NSError(domain: "ZIPQuickLook", code: 2, userInfo: [NSLocalizedDescriptionKey: localized("quicklook.cannotRead")])
        }
        defer { ZIPArchiveReaderFree(reader) }

        var paths: [String] = []
        while true {
            var rawPath: UnsafePointer<CChar>?
            var isDirectory: Int32 = 0
            let status = ZIPArchiveReaderNext(reader, &rawPath, &isDirectory)
            if status == 0 { break }
            guard status > 0 else {
                let message = ZIPArchiveReaderError(reader).map(String.init(cString:)) ?? localized("quicklook.cannotRead")
                throw NSError(domain: "ZIPQuickLook", code: 3, userInfo: [NSLocalizedDescriptionKey: message])
            }
            guard isDirectory == 0, let rawPath, let path = String(validatingCString: rawPath),
                  !path.hasPrefix("/"), !path.hasPrefix("\\"),
                  !path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).contains("..") else { continue }
            paths.append(path)
        }
        return paths.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, bundle: Bundle(for: Self.self), comment: "")
    }
}
