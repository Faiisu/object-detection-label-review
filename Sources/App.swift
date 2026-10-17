import AppKit

final class TopAlignedStack: NSStackView {
    override var isFlipped: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    let canvas = ImageCanvas()
    let sidebar = TopAlignedStack()
    let folderLabel = NSTextField(labelWithString: "No folder selected")
    let fileLabel = NSTextField(labelWithString: "Label Review")
    let status = NSTextField(labelWithString: "1–9 to select • ⌘1–9 to relabel selected box or draw")
    let countLabel = NSTextField(labelWithString: "")
    let imageNumberField = NSTextField(string: "")
    var dataset: Dataset?
    var filterLabels: Set<String> = []
    var filterUnlabeled = false
    var filterActive: Bool { filterUnlabeled || !filterLabels.isEmpty }
    var matchingIndices: [Int] { dataset?.matchingImageIndices(labels: filterLabels, includeUnlabeled: filterUnlabeled) ?? [] }
    var annotation: Annotation?
    var index = 0
    var dirty = false
    var loading = false
    var monitor: Any?
    enum History {
        case edit(URL, CGSize, Data)
        case bin([(from: URL, to: URL)])
    }
    var history: [History] = []
    var fields: [NSTextField] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        setupMenu()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1380, height: 860),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Label Review • Object Detection Review"
        window.minSize = NSSize(width: 1020, height: 650)
        window.delegate = self
        window.center()
        setupLayout()
        canvas.onSelect = { [weak self] _ in self?.refreshSidebar() }
        canvas.onCreate = { [weak self] label, rect in
            guard let self else { return }
            self.canvas.drawingLabel = nil
            self.mutate {
                self.annotation?.add(label: label, rect: rect)
                self.canvas.selected = (self.annotation?.objects.count ?? 1) - 1
            }
        }
        canvas.onChange = { [weak self] selected, rect in
            guard let self, let object = self.annotation?.objects[selected] else { return }
            self.mutate { self.annotation?.update(index: selected, label: object.label, rect: rect) }
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            return self.handleKey(event) ? nil : event
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refreshSidebar()
        // Open the picker on first launch; later launches resume the last selected folder.
        if let path = UserDefaults.standard.string(forKey: "lastFolder"), FileManager.default.fileExists(atPath: path) {
            openFolder(URL(fileURLWithPath: path, isDirectory: true))
        } else { chooseFolder() }
    }

    func setupMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem(); menu.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit Label Review", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let fileItem = NSMenuItem(); menu.addItem(fileItem)
        let file = NSMenu(title: "File"); fileItem.submenu = file
        let open = file.addItem(withTitle: "Choose folder…", action: #selector(chooseFolder), keyEquivalent: "o"); open.target = self
        let save = file.addItem(withTitle: "Save", action: #selector(saveAction), keyEquivalent: "s"); save.target = self
        let editItem = NSMenuItem(); menu.addItem(editItem)
        let edit = NSMenu(title: "Edit"); editItem.submenu = edit
        let undo = edit.addItem(withTitle: "Undo", action: #selector(undoAction), keyEquivalent: "z"); undo.target = self
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = menu
    }

    func button(_ title: String, _ selector: Selector, tag: Int = 0) -> NSButton {
        let button = NSButton(title: title, target: self, action: selector)
        button.bezelStyle = .rounded; button.tag = tag
        return button
    }
    func text(_ value: String, size: CGFloat = 13, weight: NSFont.Weight = .regular) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: value)
        field.font = NSFont.systemFont(ofSize: size, weight: weight)
        return field
    }
    func row(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views); stack.orientation = .horizontal
        stack.spacing = 8; stack.alignment = .centerY
        return stack
    }
    func setupLayout() {
        let root = NSView(); window.contentView = root
        let top = row([button("Choose folder…  ⌘O", #selector(chooseFolder)), folderLabel,
                       button("Undo  ⌘Z", #selector(undoAction))])
        folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageNumberField.placeholderString = "Image #"
        imageNumberField.alignment = .center
        imageNumberField.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        imageNumberField.target = self
        imageNumberField.action = #selector(jumpToImage(_:))
        imageNumberField.toolTip = "Enter an image number and press Return to jump to it"
        imageNumberField.widthAnchor.constraint(equalToConstant: 62).isActive = true
        let navigation = row([button("◀ Previous  A", #selector(previous)), fileLabel,
                              countLabel, text("Go to", size: 12), imageNumberField,
                              button("Next  D ▶", #selector(next))])
        fileLabel.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
        fileLabel.lineBreakMode = .byTruncatingMiddle
        fileLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        countLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true
        sidebar.orientation = .vertical; sidebar.alignment = .leading; sidebar.spacing = 12
        sidebar.distribution = .fill
        sidebar.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        scroll.documentView = sidebar
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sidebar.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -16),
            sidebar.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            sidebar.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor)
        ])
        let bottom = row([status, button("Fit image", #selector(fitImage)), button("Move image + XML to bin  R", #selector(binImage))])
        status.font = .systemFont(ofSize: 12)
        status.lineBreakMode = .byTruncatingTail
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for view in [top, navigation, canvas, scroll, bottom] {
            view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            top.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            top.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            top.heightAnchor.constraint(equalToConstant: 32),
            navigation.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 8),
            navigation.leadingAnchor.constraint(equalTo: top.leadingAnchor),
            navigation.trailingAnchor.constraint(equalTo: top.trailingAnchor),
            navigation.heightAnchor.constraint(equalToConstant: 30),
            canvas.topAnchor.constraint(equalTo: navigation.bottomAnchor, constant: 12),
            canvas.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: scroll.leadingAnchor),
            canvas.bottomAnchor.constraint(equalTo: bottom.topAnchor, constant: -10),
            scroll.topAnchor.constraint(equalTo: canvas.topAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: canvas.bottomAnchor),
            scroll.widthAnchor.constraint(equalToConstant: 310),
            bottom.leadingAnchor.constraint(equalTo: top.leadingAnchor),
            bottom.trailingAnchor.constraint(equalTo: top.trailingAnchor),
            bottom.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            bottom.heightAnchor.constraint(equalToConstant: 30)
        ])
    }

    func showError(_ error: Error) {
        status.stringValue = "Error • \(error.localizedDescription)"
        let alert = NSAlert(); alert.alertStyle = .warning
        alert.messageText = "Could not complete action"; alert.informativeText = error.localizedDescription
        alert.runModal()
    }
    @objc func chooseFolder() {
        guard !loading, flush() else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false; panel.prompt = "Open dataset"
        panel.message = "Choose a folder containing images and matching Pascal VOC XML files."
        panel.directoryURL = dataset?.folder ?? FileManager.default.homeDirectoryForCurrentUser
        let result = panel.runModal()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
        NSApp.activate(ignoringOtherApps: true)
        if result == .OK, let url = panel.url { openFolder(url) }
    }
    func openFolder(_ url: URL) {
        loading = true; status.stringValue = "Loading images and labels…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try Dataset(folder: url) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.loading = false
                switch result {
                case .success(let data):
                    self.dataset = data; self.history = []; self.dirty = false
                    self.filterLabels = []
                    self.filterUnlabeled = false
                    self.folderLabel.stringValue = url.path
                    self.folderLabel.toolTip = url.path
                    UserDefaults.standard.set(url.path, forKey: "lastFolder")
                    let last = UserDefaults.standard.string(forKey: "position:" + url.path)
                    self.index = data.images.firstIndex(where: { $0.lastPathComponent == last }) ?? 0
                    self.loadImage()
                case .failure(let error): self.showError(error)
                }
            }
        }
    }
    func loadImage() {
        canvas.reset(); annotation = nil; canvas.annotation = nil; canvas.image = nil
        dirty = false
        let matches = matchingIndices
        if !matches.contains(index) { index = matches.first(where: { $0 >= index }) ?? matches.last ?? 0 }
        guard let dataset, !matches.isEmpty, dataset.images.indices.contains(index) else {
            let filtered = filterActive
            fileLabel.stringValue = filtered ? "No images match selected labels" : "No images in this folder"
            canvas.emptyMessage = filtered ? "No images match selected labels" : "Choose a folder to start reviewing"
            countLabel.stringValue = "0 / 0"
            imageNumberField.stringValue = ""
            status.stringValue = filtered ? "Select other labels or click Show all images" : "Choose a folder containing images directly • bin is excluded"
            canvas.needsDisplay = true; refreshSidebar(); return
        }
        let url = dataset.images[index]
        fileLabel.stringValue = url.lastPathComponent
        countLabel.stringValue = "\((matches.firstIndex(of: index) ?? 0) + 1) / \(matches.count)" +
            (filterActive ? " • \(dataset.images.count) total" : "")
        imageNumberField.stringValue = "\((matches.firstIndex(of: index) ?? 0) + 1)"
        UserDefaults.standard.set(url.lastPathComponent, forKey: "position:" + dataset.folder.path)
        do {
            guard let image = NSImage(contentsOf: url),
                  let rep = image.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 else {
                throw ReviewError(message: "Cannot open image: \(url.lastPathComponent)")
            }
            let model = try Annotation(imageURL: url, size: CGSize(width: rep.pixelsWide, height: rep.pixelsHigh))
            annotation = model; canvas.annotation = model; canvas.image = image
            status.stringValue = "1–9 to select • ⌘1–9 to relabel selected box or draw • Auto-save"
        } catch { showError(error) }
        canvas.needsDisplay = true; refreshSidebar()
    }
    @discardableResult func flush() -> Bool {
        guard dirty, let annotation else { return true }
        do {
            try annotation.save(); dirty = false
            dataset?.updateLabels(for: annotation.imageURL, labels: Set(annotation.objects.map(\.label)))
            status.stringValue = "Saved • \(annotation.xmlURL.lastPathComponent)"
            let matches = matchingIndices
            if let position = matches.firstIndex(of: index) {
                countLabel.stringValue = "\(position + 1) / \(matches.count)" +
                    (filterActive ? " • \(dataset?.images.count ?? 0) total" : "")
            } else {
                countLabel.stringValue = "Outside filter • \(matches.count) matching"
                status.stringValue += " • Image kept; no longer matches filter • A/D to continue"
            }
            return true
        } catch { showError(error); return false }
    }
    @objc func saveAction() { _ = flush() }
    func mutate(_ action: () -> Void) {
        guard !loading, let annotation else { return }
        let before = annotation.document.xmlData(options: [.nodePrettyPrint])
        action()
        history.append(.edit(annotation.imageURL, annotation.size, before))
        if history.count > 100 { history.removeFirst() }
        dirty = true
        // Keep the image visible while editing, even when its last matching box was removed.
        _ = flush()
        canvas.needsDisplay = true; refreshSidebar()
    }
    func navigate(_ step: Int) {
        guard !loading, flush(), let dataset, !dataset.images.isEmpty else { return }
        let matches = matchingIndices
        guard let first = matches.first, let last = matches.last else { loadImage(); return }
        let destination = step < 0 ? (matches.last(where: { $0 < index }) ?? first) : (matches.first(where: { $0 > index }) ?? last)
        if destination != index { index = destination; loadImage() }
    }
    @objc func previous() { navigate(-1) }
    @objc func next() { navigate(1) }
    @objc func jumpToImage(_ sender: NSTextField) {
        guard !loading, flush() else { loadImage(); return }
        let matches = matchingIndices
        guard let number = Int(sender.stringValue), matches.indices.contains(number - 1) else {
            status.stringValue = "Enter an image number from 1 to \(matches.count)"
            loadImage()
            return
        }
        let destination = matches[number - 1]
        if destination != index { index = destination; loadImage() }
        window.makeFirstResponder(canvas)
    }
    @objc func fitImage() { canvas.fit() }
    @objc func binImage() {
        guard !loading, flush(), let dataset, dataset.images.indices.contains(index),
              annotation != nil || matchingIndices.contains(index) else { return }
        do {
            let moved = try dataset.moveToBin(image: dataset.images[index])
            history.append(.bin(moved))
            if history.count > 100 { history.removeFirst() }
            self.dataset?.images.remove(at: index)
            index = min(index, max(0, (self.dataset?.images.count ?? 1) - 1))
            loadImage(); status.stringValue = "Moved image and labels to bin • ⌘Z to restore"
        } catch { showError(error) }
    }
    @objc func undoAction() {
        guard !loading, flush(), let last = history.last else { return }
        do {
            switch last {
            case .edit(let image, let size, let data):
                guard let destination = dataset?.images.firstIndex(of: image) else {
                    throw ReviewError(message: "Cannot find the image to undo")
                }
                let restored = try Annotation(imageURL: image, size: size, data: data)
                try restored.save(); index = destination
                dataset?.updateLabels(for: image, labels: Set(restored.objects.map(\.label)))
            case .bin(let moved):
                let fm = FileManager.default
                for pair in moved {
                    guard fm.fileExists(atPath: pair.to.path), !fm.fileExists(atPath: pair.from.path) else {
                        throw ReviewError(message: "Cannot restore: a bin file is missing or the dataset already contains this filename.")
                    }
                }
                var restored: [(from: URL, to: URL)] = []
                do {
                    for pair in moved { try fm.moveItem(at: pair.to, to: pair.from); restored.append(pair) }
                } catch {
                    var failures: [String] = []
                    for pair in restored.reversed() {
                        do { try fm.moveItem(at: pair.from, to: pair.to) }
                        catch { failures.append(pair.from.path) }
                    }
                    throw ReviewError(message: "Restore failed: \(error.localizedDescription)" +
                        (failures.isEmpty ? "" : "\nCheck files that could not be rolled back: " + failures.joined(separator: ", ")))
                }
                if let image = moved.first?.from {
                    dataset?.images.append(image)
                    dataset?.images.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                    index = dataset?.images.firstIndex(of: image) ?? 0
                }
            }
            history.removeLast(); loadImage(); status.stringValue = "Undone"
        } catch { showError(error) }
    }

    func section(_ title: String) {
        let label = text(title, size: 12, weight: .bold); label.textColor = .secondaryLabelColor
        sidebar.addArrangedSubview(label)
    }
    func refreshSidebar() {
        for view in sidebar.arrangedSubviews { sidebar.removeArrangedSubview(view); view.removeFromSuperview() }
        fields = []
        let names = dataset?.labels ?? []
        section("FILTER IMAGES")
        sidebar.addArrangedSubview(text("\(matchingIndices.count) of \(dataset?.images.count ?? 0) images • match any selected option", size: 11))
        let unlabeled = NSButton(checkboxWithTitle: "No labels", target: self, action: #selector(toggleUnlabeledFilter(_:)))
        unlabeled.state = filterUnlabeled ? .on : .off
        unlabeled.isEnabled = !loading && dataset != nil
        unlabeled.toolTip = "Images with no object boxes, including images without XML"
        sidebar.addArrangedSubview(unlabeled)
        for (number, name) in names.enumerated() {
            let checkbox = NSButton(checkboxWithTitle: name, target: self, action: #selector(toggleFilter(_:)))
            checkbox.tag = number
            checkbox.state = filterLabels.contains(name) ? .on : .off
            checkbox.isEnabled = !loading
            sidebar.addArrangedSubview(checkbox)
        }
        let clear = button("Show all images", #selector(clearFilter))
        clear.isEnabled = !loading && filterActive
        sidebar.addArrangedSubview(clear)
        section("LABELS • DRAW SHORTCUTS")
        for (number, name) in names.enumerated() {
            let shortcut = number < 10 ? "⌘\((number + 1) % 10)" : "\(number + 1)"
            let labelButton = button("\(shortcut)   \(name)", #selector(chooseLabel(_:)), tag: number)
            labelButton.contentTintColor = labelColor(name)
            labelButton.toolTip = "Draw a new \(name) box • ⌘number changes a selected box's label"
            sidebar.addArrangedSubview(row([labelButton, button("−", #selector(removeLabel(_:)), tag: number)]))
        }
        sidebar.addArrangedSubview(button("+ Add label", #selector(addLabel)))
        sidebar.addArrangedSubview(text("1–9: select / cycle boxes\n⌘1–9: relabel selected box, otherwise draw\nEsc: clear selection • 0 uses label 10", size: 11))
        section("OBJECTS • \(annotation?.objects.count ?? 0)")
        if let annotation {
            sidebar.addArrangedSubview(text("Image \(Int(annotation.size.width)) × \(Int(annotation.size.height)) px", size: 12))
            for (i, object) in annotation.objects.enumerated() {
                let prefix = canvas.selected == i ? "●" : "○"
                let item = button("\(prefix) \(i+1)  \(object.label)", #selector(selectObject(_:)), tag: i)
                item.contentTintColor = labelColor(object.label)
                sidebar.addArrangedSubview(item)
            }
            if let selected = canvas.selected, annotation.objects.indices.contains(selected) {
                let object = annotation.objects[selected]
                section("BOX DETAILS #\(selected + 1)")
                let popup = NSPopUpButton(); popup.addItems(withTitles: names)
                popup.selectItem(withTitle: object.label)
                popup.target = self; popup.action = #selector(changeObjectLabel(_:))
                sidebar.addArrangedSubview(popup)
                let values = [object.rect.origin.x, object.rect.origin.y, object.rect.width, object.rect.height]
                for (name, value) in zip(["X", "Y", "Width", "Height"], values) {
                    let field = NSTextField(string: String(Int(value)))
                    field.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
                    field.widthAnchor.constraint(equalToConstant: 110).isActive = true
                    fields.append(field); sidebar.addArrangedSubview(row([text(name), field]))
                }
                if object.rect.width <= 0 || object.rect.height <= 0 || object.rect.minX < 0 || object.rect.minY < 0 || object.rect.maxX > annotation.size.width || object.rect.maxY > annotation.size.height {
                    let warning = text("⚠ Box is outside the image or has an invalid size. Edit its coordinates.", size: 12)
                    warning.textColor = .systemOrange; sidebar.addArrangedSubview(warning)
                }
                sidebar.addArrangedSubview(text("Confidence: \(object.confidence ?? "Not provided")", size: 12))
                let flags = ["difficult", "truncated", "pose"].compactMap { name -> String? in
                    object.element.elements(forName: name).first?.stringValue.map { "\(name): \($0)" }
                }
                if !flags.isEmpty { sidebar.addArrangedSubview(text(flags.joined(separator: " • "), size: 11)) }
                sidebar.addArrangedSubview(button("Apply coordinates", #selector(applyCoordinates)))
                sidebar.addArrangedSubview(button("Delete box  Delete", #selector(deleteObject)))
            } else { sidebar.addArrangedSubview(text("Select a box on the image or in the list to inspect it.", size: 12)) }
        }
        section("KEYBOARD & MOUSE")
        sidebar.addArrangedSubview(text("1–9 / 0  Select next box of that label\n⌘1–9 / ⌘0  Relabel selected box, or draw\nA / D  Previous / next image\nR  Move image + XML to bin\nDelete  Remove selected box\nEsc  Cancel drawing / clear selection\n⌘Z  Undo edit / restore image\nScroll  Zoom image\nOption + drag  Pan image\nDrag a corner  Resize box", size: 12))
    }
    @objc func toggleFilter(_ sender: NSButton) {
        guard !loading, flush(), let labels = dataset?.labels, labels.indices.contains(sender.tag) else {
            refreshSidebar(); return
        }
        let label = labels[sender.tag]
        if sender.state == .on { filterLabels.insert(label) }
        else { filterLabels.remove(label) }
        loadImage(); window.makeFirstResponder(canvas)
    }
    @objc func toggleUnlabeledFilter(_ sender: NSButton) {
        guard !loading, dataset != nil, flush() else { refreshSidebar(); return }
        filterUnlabeled = sender.state == .on
        loadImage(); window.makeFirstResponder(canvas)
    }
    @objc func clearFilter() {
        guard !loading, flush() else { return }
        filterLabels = []; filterUnlabeled = false; loadImage(); window.makeFirstResponder(canvas)
    }
    @objc func chooseLabel(_ sender: NSButton) { armLabel(sender.tag) }
    func armLabel(_ number: Int) {
        guard !loading, let labels = dataset?.labels, labels.indices.contains(number), annotation != nil else { NSSound.beep(); return }
        canvas.cancelGesture(); canvas.selected = nil
        canvas.drawingLabel = labels[number]
        status.stringValue = "Draw \(labels[number]) • Drag on the image • Esc to cancel"
        window.makeFirstResponder(canvas); refreshSidebar()
    }
    @objc func selectObject(_ sender: NSButton) {
        selectObject(at: sender.tag)
    }
    func selectObject(at index: Int) {
        guard !loading, annotation?.objects.indices.contains(index) == true else { return }
        canvas.cancelGesture(); canvas.drawingLabel = nil
        canvas.selected = index; window.makeFirstResponder(canvas); refreshSidebar()
    }
    func selectNextObject(labelNumber number: Int) {
        guard let labels = dataset?.labels, labels.indices.contains(number), let annotation else { return }
        let label = labels[number]
        let matches = annotation.objects.indices.filter { annotation.objects[$0].label == label }
        guard let first = matches.first else {
            canvas.cancelGesture(); canvas.drawingLabel = nil; canvas.selected = nil
            status.stringValue = "No \(label) boxes in this image"
            refreshSidebar(); return
        }
        let next: Int
        if let selected = canvas.selected, let position = matches.firstIndex(of: selected) {
            next = matches[(position + 1) % matches.count]
        } else { next = first }
        selectObject(at: next)
        status.stringValue = "Selected \(label) box \((matches.firstIndex(of: next) ?? 0) + 1) / \(matches.count) • Press the number again for next"
    }
    @objc func changeObjectLabel(_ sender: NSPopUpButton) {
        guard let label = sender.titleOfSelectedItem else { return }
        relabelSelectedObject(to: label)
    }
    func relabelSelectedObject(to label: String) {
        guard !loading, let selected = canvas.selected, let annotation,
              annotation.objects.indices.contains(selected), dataset?.labels.contains(label) == true else { return }
        canvas.cancelGesture(); canvas.drawingLabel = nil
        let object = annotation.objects[selected]
        if object.label != label {
            mutate { annotation.update(index: selected, label: label, rect: object.rect) }
        }
        window.makeFirstResponder(canvas)
    }
    @objc func applyCoordinates() {
        guard let selected = canvas.selected, let annotation, fields.count == 4 else { return }
        let values = fields.compactMap { Double($0.stringValue) }
        guard values.count == 4, values.allSatisfy({ $0.isFinite && $0.rounded() == $0 }),
              values[0] >= 0, values[1] >= 0, values[2] >= 1, values[3] >= 1,
              values[0] + values[2] <= annotation.size.width, values[1] + values[3] <= annotation.size.height else {
            showError(ReviewError(message: "Coordinates must be whole pixels, box size at least 1 px, and the box must fit inside the image.")); return
        }
        let rect = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
        mutate { annotation.update(index: selected, label: annotation.objects[selected].label, rect: rect) }
        window.makeFirstResponder(canvas)
    }
    @objc func deleteObject() {
        guard let selected = canvas.selected, annotation?.objects.indices.contains(selected) == true else { return }
        canvas.cancelGesture()
        mutate { annotation?.remove(index: selected); canvas.selected = nil }
    }
    @objc func addLabel() {
        guard !loading, dataset != nil else { return }
        let alert = NSAlert(); alert.messageText = "Add label"
        alert.informativeText = "Enter an object class, such as dog, cat, or stroller."
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 26))
        alert.accessoryView = input; alert.addButton(withTitle: "Add"); alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = input
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 100, !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }), dataset?.labels.contains(name) == false else {
            showError(ReviewError(message: "Label names must be unique, nonempty, and at most 100 characters.")); return
        }
        let old = dataset?.labels
        dataset?.labels.append(name)
        do { try dataset?.saveLabels(); refreshSidebar() }
        catch { dataset?.labels = old ?? []; showError(error) }
    }
    @objc func removeLabel(_ sender: NSButton) {
        guard !loading, flush(), let dataset, dataset.labels.indices.contains(sender.tag) else { return }
        let label = dataset.labels[sender.tag]
        do {
            guard try !dataset.labelIsUsed(label) else {
                throw ReviewError(message: "label \(label) is still used in this dataset. Relabel or remove those boxes first.")
            }
            let old = dataset.labels
            self.dataset?.labels.remove(at: sender.tag)
            do { try self.dataset?.saveLabels() }
            catch { self.dataset?.labels = old; throw error }
            filterLabels.remove(label)
            canvas.drawingLabel = nil; refreshSidebar()
            if !matchingIndices.contains(index) || annotation == nil { loadImage() }
        } catch { showError(error) }
    }
    func handleKey(_ event: NSEvent) -> Bool {
        guard !loading, NSApp.modalWindow == nil, !(window.firstResponder is NSTextView) else { return false }
        let digits: [UInt16: Int] = [18: 0, 19: 1, 20: 2, 21: 3, 23: 4, 22: 5, 26: 6, 28: 7, 25: 8, 29: 9,
                                    83: 0, 84: 1, 85: 2, 86: 3, 87: 4, 88: 5, 89: 6, 91: 7, 92: 8, 82: 9]
        if let number = digits[event.keyCode] {
            guard event.modifierFlags.intersection([.shift, .control, .option]).isEmpty else { return false }
            if !event.isARepeat {
                if event.modifierFlags.contains(.command) {
                    if let selected = canvas.selected, annotation?.objects.indices.contains(selected) == true {
                        if let labels = dataset?.labels, labels.indices.contains(number) {
                            relabelSelectedObject(to: labels[number])
                        }
                    } else { armLabel(number) }
                }
                else { selectNextObject(labelNumber: number) }
            }
            return true
        }
        if event.modifierFlags.contains(.command) {
            switch event.keyCode {
            case 31: chooseFolder(); return true
            case 1: saveAction(); return true
            case 6: undoAction(); return true
            default: return false
            }
        }
        guard !event.modifierFlags.contains(.control), !event.modifierFlags.contains(.option) else { return false }
        switch event.keyCode {
        case 0: previous(); return true
        case 2: next(); return true
        case 15: if !event.isARepeat { binImage() }; return true
        case 51, 117: deleteObject(); return true
        case 53:
            canvas.cancelGesture(); canvas.drawingLabel = nil; canvas.selected = nil
            refreshSidebar()
            status.stringValue = "Drawing / selection cleared • ⌘1–9 to draw a new box"; return true
        default: return false
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { flush() ? .terminateNow : .terminateCancel }
    func windowShouldClose(_ sender: NSWindow) -> Bool { flush() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

#if !TESTING
@main
struct LabelReviewApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
#endif
