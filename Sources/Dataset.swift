import AppKit

struct ReviewError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct Detection {
    var label: String
    var rect: CGRect
    let element: XMLElement
    var confidence: String? {
        element.elements(forName: "confidence").first?.stringValue
            ?? element.elements(forName: "score").first?.stringValue
    }
}

final class Annotation {
    let imageURL: URL
    let xmlURL: URL
    let document: XMLDocument
    let size: CGSize
    var objects: [Detection] = []

    init(imageURL: URL, size: CGSize, data: Data? = nil) throws {
        self.imageURL = imageURL
        self.xmlURL = imageURL.deletingPathExtension().appendingPathExtension("xml")
        self.size = size
        if data != nil || FileManager.default.fileExists(atPath: xmlURL.path) {
            if let data { document = try XMLDocument(data: data, options: [.nodePreserveAll]) }
            else { document = try XMLDocument(contentsOf: xmlURL, options: [.nodePreserveAll]) }
            guard let root = document.rootElement(), root.name == "annotation" else {
                throw ReviewError(message: "XML root must be annotation: \(xmlURL.lastPathComponent)")
            }
            for element in root.elements(forName: "object") {
                guard let label = element.elements(forName: "name").first?.stringValue,
                      !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      let box = element.elements(forName: "bndbox").first else {
                    throw ReviewError(message: "Incomplete object data: \(xmlURL.lastPathComponent)")
                }
                func coordinate(_ name: String) throws -> Double {
                    guard let text = box.elements(forName: name).first?.stringValue,
                          let value = Double(text), value.isFinite, abs(value) <= Double(Int32.max) else {
                        throw ReviewError(message: "Invalid coordinate \(name): \(xmlURL.lastPathComponent)")
                    }
                    return value
                }
                let x1 = try coordinate("xmin"), y1 = try coordinate("ymin")
                let x2 = try coordinate("xmax"), y2 = try coordinate("ymax")
                // Keep invalid AI boxes visible for repair; do not silently rewrite them on load.
                objects.append(Detection(label: label,
                    rect: CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1), element: element))
            }
        } else {
            let root = XMLElement(name: "annotation")
            root.addAttribute(XMLNode.attribute(withName: "verified", stringValue: "no") as! XMLNode)
            document = XMLDocument(rootElement: root)
            document.characterEncoding = "UTF-8"
            root.addChild(XMLElement(name: "filename", stringValue: imageURL.lastPathComponent))
            root.addChild(XMLElement(name: "path", stringValue: imageURL.path))
            let dimensions = XMLElement(name: "size")
            dimensions.addChild(XMLElement(name: "width", stringValue: String(Int(size.width))))
            dimensions.addChild(XMLElement(name: "height", stringValue: String(Int(size.height))))
            dimensions.addChild(XMLElement(name: "depth", stringValue: "3"))
            root.addChild(dimensions)
            root.addChild(XMLElement(name: "segmented", stringValue: "0"))
        }
    }

    func add(label: String, rect: CGRect) {
        let element = XMLElement(name: "object")
        for (name, value) in [("name", label), ("pose", "Unspecified"), ("truncated", "0"), ("difficult", "0")] {
            element.addChild(XMLElement(name: name, stringValue: value))
        }
        let box = XMLElement(name: "bndbox")
        element.addChild(box)
        document.rootElement()?.addChild(element)
        objects.append(Detection(label: label, rect: rect, element: element))
        update(index: objects.count - 1, label: label, rect: rect)
    }

    func update(index: Int, label: String, rect: CGRect) {
        guard objects.indices.contains(index) else { return }
        objects[index].label = label
        objects[index].rect = rect
        let element = objects[index].element
        element.elements(forName: "name").first?.stringValue = label
        let box = element.elements(forName: "bndbox")[0]
        let values = [("xmin", rect.minX), ("ymin", rect.minY), ("xmax", rect.maxX), ("ymax", rect.maxY)]
        for (name, value) in values {
            if let node = box.elements(forName: name).first { node.stringValue = String(Int(value.rounded())) }
            else { box.addChild(XMLElement(name: name, stringValue: String(Int(value.rounded())))) }
        }
    }

    func remove(index: Int) {
        objects[index].element.detach()
        objects.remove(at: index)
    }

    func save() throws {
        try document.xmlData(options: [.nodePrettyPrint]).write(to: xmlURL, options: .atomic)
    }
}

struct Dataset {
    let folder: URL
    var images: [URL]
    var labels: [String]
    private(set) var labelsByImage: [String: Set<String>] = [:]
    var catalogURL: URL { folder.appendingPathComponent(".label-review-labels.json") }

    init(folder: URL) throws {
        self.folder = folder
        let entries = try FileManager.default.contentsOfDirectory(at: folder,
            includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        let extensions: Set<String> = ["jpg", "jpeg", "png", "bmp", "tif", "tiff", "webp", "heic"]
        images = try entries.filter {
            guard extensions.contains($0.pathExtension.lowercased()) else { return false }
            return try $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
        }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        for image in images {
            let xml = image.deletingPathExtension().appendingPathExtension("xml")
            if !FileManager.default.fileExists(atPath: xml.path) {
                labelsByImage[image.deletingPathExtension().lastPathComponent] = []
            }
        }
        var names: Set<String> = []
        for url in entries where url.pathExtension.lowercased() == "xml" {
            if let doc = try? XMLDocument(contentsOf: url, options: []), let root = doc.rootElement(), root.name == "annotation" {
                var imageLabels: Set<String> = []
                for object in root.elements(forName: "object") {
                    if let name = object.elements(forName: "name").first?.stringValue, !name.isEmpty {
                        names.insert(name); imageLabels.insert(name)
                    }
                }
                // An unreadable object is not evidence that the image has no objects.
                if !imageLabels.isEmpty || root.elements(forName: "object").isEmpty {
                    labelsByImage[url.deletingPathExtension().lastPathComponent] = imageLabels
                }
            }
        }
        let catalog = folder.appendingPathComponent(".label-review-labels.json")
        if FileManager.default.fileExists(atPath: catalog.path) {
            let saved = try JSONDecoder().decode([String].self, from: Data(contentsOf: catalog))
            labels = saved.filter { !$0.isEmpty }
            labels += names.subtracting(Set(labels)).sorted()
        } else { labels = names.sorted() }
    }

    func saveLabels() throws {
        try JSONEncoder().encode(labels).write(to: catalogURL, options: .atomic)
    }

    func matchingImageIndices(labels selected: Set<String>, includeUnlabeled: Bool = false) -> [Int] {
        images.indices.filter { index in
            let labels = labelsByImage[images[index].deletingPathExtension().lastPathComponent]
            return (selected.isEmpty && !includeUnlabeled) ||
                (includeUnlabeled && labels?.isEmpty == true) || !selected.isDisjoint(with: labels ?? [])
        }
    }

    mutating func updateLabels(for image: URL, labels: Set<String>) {
        labelsByImage[image.deletingPathExtension().lastPathComponent] = labels
    }

    func labelIsUsed(_ label: String) throws -> Bool {
        for image in images {
            let xml = image.deletingPathExtension().appendingPathExtension("xml")
            guard FileManager.default.fileExists(atPath: xml.path) else { continue }
            let doc = try XMLDocument(contentsOf: xml, options: [])
            if doc.rootElement()?.elements(forName: "object").contains(where: {
                $0.elements(forName: "name").first?.stringValue == label
            }) == true { return true }
        }
        return false
    }

    func moveToBin(image: URL) throws -> [(from: URL, to: URL)] {
        let fm = FileManager.default
        let bin = folder.appendingPathComponent("bin", isDirectory: true)
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        let xml = image.deletingPathExtension().appendingPathExtension("xml")
        let sources = [image, xml].filter { fm.fileExists(atPath: $0.path) }
        guard sources.contains(image) else { throw ReviewError(message: "Image file not found") }
        // A subfolder on collision preserves the original paired filenames.
        let collision = sources.contains { fm.fileExists(atPath: bin.appendingPathComponent($0.lastPathComponent).path) }
        let destination = collision ? bin.appendingPathComponent(UUID().uuidString, isDirectory: true) : bin
        if collision { try fm.createDirectory(at: destination, withIntermediateDirectories: true) }
        var moved: [(from: URL, to: URL)] = []
        do {
            for source in sources {
                let target = destination.appendingPathComponent(source.lastPathComponent)
                try fm.moveItem(at: source, to: target)
                moved.append((source, target))
            }
        } catch {
            var rollbackErrors: [String] = []
            for pair in moved.reversed() {
                do { try fm.moveItem(at: pair.to, to: pair.from) }
                catch { rollbackErrors.append("\(pair.to.path): \(error.localizedDescription)") }
            }
            throw ReviewError(message: "Move to bin failed: \(error.localizedDescription)" +
                (rollbackErrors.isEmpty ? "" : "\nSome files remain in bin:\n" + rollbackErrors.joined(separator: "\n")))
        }
        return moved
    }
}
