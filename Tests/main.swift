import AppKit

func check(_ condition: @autoclosure () throws -> Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    do {
        let result = try condition()
        assert(result, message, file: file, line: line)
    } catch { fatalError("Unexpected error: \(error)", file: file, line: line) }
}

let fm = FileManager.default
let temp = fm.temporaryDirectory.appendingPathComponent("label-review-tests-" + UUID().uuidString)
try fm.createDirectory(at: temp, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: temp) }
let image = temp.appendingPathComponent("sample.jpeg")
try Data("image fixture".utf8).write(to: image)
let xml = image.deletingPathExtension().appendingPathExtension("xml")
let fixture = """
<annotation verified="no"><filename>sample.jpeg</filename><size><width>1280</width><height>720</height><depth>3</depth></size><custom>preserve me</custom><object><name>dog</name><pose>Unspecified</pose><difficult>1</difficult><confidence>0.85</confidence><bndbox><xmin>10</xmin><ymin>20</ymin><xmax>110</xmax><ymax>220</ymax></bndbox><extra>keep</extra></object></annotation>
"""
try Data(fixture.utf8).write(to: xml)
let original = try Data(contentsOf: xml)
let annotation = try Annotation(imageURL: image, size: CGSize(width: 1280, height: 720))
check(try Data(contentsOf: xml) == original, "Loading must not change source files")
check(annotation.objects.count == 1)
check(annotation.objects[0].rect == CGRect(x: 10, y: 20, width: 100, height: 200))
check(annotation.objects[0].confidence == "0.85")
annotation.update(index: 0, label: "cat", rect: CGRect(x: 25, y: 30, width: 40, height: 50))
annotation.add(label: "stroller", rect: CGRect(x: 100, y: 110, width: 120, height: 130))
try annotation.save()
let reloaded = try Annotation(imageURL: image, size: annotation.size)
check(reloaded.objects.map(\.label) == ["cat", "stroller"])
check(reloaded.objects[0].rect == CGRect(x: 25, y: 30, width: 40, height: 50))
check(reloaded.document.rootElement()?.elements(forName: "custom").first?.stringValue == "preserve me")
check(reloaded.objects[0].element.elements(forName: "extra").first?.stringValue == "keep")
check(reloaded.objects[0].element.elements(forName: "difficult").first?.stringValue == "1")
reloaded.remove(index: 0)
try reloaded.save()
check(try Annotation(imageURL: image, size: annotation.size).objects.count == 1)
var dataset = try Dataset(folder: temp)
check(dataset.images.map { $0.resolvingSymlinksInPath().path } == [image.resolvingSymlinksInPath().path])
check(dataset.labels == ["stroller"])
dataset.labels.append("dog"); try dataset.saveLabels()
check(try Dataset(folder: temp).labels == ["stroller", "dog"])
check(try dataset.labelIsUsed("stroller"))
check(try !dataset.labelIsUsed("dog"))
let moved = try dataset.moveToBin(image: image)
check(moved.count == 2)
check(!fm.fileExists(atPath: image.path) && !fm.fileExists(atPath: xml.path))
check(try Dataset(folder: temp).images.isEmpty, "bin must be excluded")
try Data("second image".utf8).write(to: image)
try Data(fixture.utf8).write(to: xml)
let collision = try dataset.moveToBin(image: image)
check(collision[0].to.deletingLastPathComponent() != moved[0].to.deletingLastPathComponent())
check(collision[0].to.deletingLastPathComponent() == collision[1].to.deletingLastPathComponent())
check(try Data(contentsOf: moved[0].to) == Data("image fixture".utf8), "Never overwrite bin files")
for pair in collision { try fm.moveItem(at: pair.to, to: pair.from) }
check(fm.fileExists(atPath: image.path) && fm.fileExists(atPath: xml.path))
try Data("<annotation><object><name>dog</name></object></annotation>".utf8).write(to: xml)
do {
    _ = try Annotation(imageURL: image, size: annotation.size)
    assertionFailure("Malformed objects should be rejected")
} catch { check(error is ReviewError) }
check(try String(contentsOf: xml, encoding: .utf8).contains("<object><name>dog</name></object>"))
try fm.removeItem(at: xml)
let empty = try Annotation(imageURL: image, size: annotation.size)
check(empty.objects.isEmpty && !fm.fileExists(atPath: xml.path))
empty.add(label: "dog", rect: CGRect(x: 0, y: 0, width: 1, height: 1))
try empty.save()
check(try Annotation(imageURL: image, size: annotation.size).objects.count == 1)
print("PASS: XML round trip, metadata preservation, label catalog, bin pairing/collision/restore, malformed input, missing XML")

let canvas = ImageCanvas(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))
canvas.annotation = empty
func viewPoint(_ point: CGPoint) -> CGPoint {
    CGPoint(x: canvas.imageRect.minX + point.x * canvas.scale, y: canvas.imageRect.minY + point.y * canvas.scale)
}
var created: CGRect?
canvas.onCreate = { label, rect in
    check(label == "cat"); created = rect
    empty.add(label: label, rect: rect)
}
canvas.drawingLabel = "cat"
canvas.beginGesture(at: viewPoint(CGPoint(x: 300, y: 400)))
canvas.continueGesture(at: viewPoint(CGPoint(x: 100, y: 200)))
canvas.finishGesture()
check(created == CGRect(x: 100, y: 200, width: 200, height: 200), "Reverse-direction drawing must normalize")
canvas.drawingLabel = nil
canvas.onChange = { index, rect in empty.update(index: index, label: empty.objects[index].label, rect: rect) }
canvas.beginGesture(at: viewPoint(CGPoint(x: 200, y: 300)))
canvas.continueGesture(at: viewPoint(CGPoint(x: 250, y: 330)))
canvas.finishGesture()
check(empty.objects[1].rect == CGRect(x: 150, y: 230, width: 200, height: 200), "Move box in original pixel coordinates")
canvas.beginGesture(at: viewPoint(CGPoint(x: 350, y: 430)))
canvas.continueGesture(at: viewPoint(CGPoint(x: 400, y: 500)))
canvas.finishGesture()
check(empty.objects[1].rect == CGRect(x: 150, y: 230, width: 250, height: 270), "Resize a corner")
canvas.drawingLabel = "cat"
created = nil
canvas.beginGesture(at: viewPoint(CGPoint(x: 100, y: 100)))
canvas.finishGesture()
check(created == nil, "Clicks must not create zero-area boxes")
canvas.beginGesture(at: viewPoint(CGPoint(x: 100, y: 100)))
canvas.continueGesture(at: viewPoint(CGPoint(x: 200, y: 200)))
canvas.cancelGesture(); canvas.finishGesture()
check(created == nil, "Escape must cancel the pending drawing")
canvas.beginGesture(at: viewPoint(CGPoint(x: 1200, y: 650)))
canvas.continueGesture(at: CGPoint(x: 5000, y: 5000))
canvas.finishGesture()
check(created?.maxX == 1280 && created?.maxY == 720, "New boxes must be clamped to image bounds")
canvas.drawingLabel = nil
canvas.selected = nil
empty.add(label: "small", rect: CGRect(x: 160, y: 240, width: 20, height: 20))
canvas.beginGesture(at: viewPoint(CGPoint(x: 170, y: 250)))
check(canvas.selected == empty.objects.count - 1, "Overlapping hit selection must prefer the smallest box")
canvas.cancelGesture()
print("PASS: drawing/reverse drag, move, corner resize, zero-area rejection, cancel, boundary clipping, overlap selection")

let filterFolder = temp.appendingPathComponent("filter-fixtures", isDirectory: true)
try fm.createDirectory(at: filterFolder, withIntermediateDirectories: true)
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 48,
    bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
bitmap.bitmapData?.initialize(repeating: 220, count: bitmap.bytesPerRow * 48)
let png = bitmap.representation(using: .png, properties: [:])!
for (name, labels) in [("a-dog", ["dog"]), ("b-cat", ["cat"]), ("c-both", ["dog", "cat"]),
                        ("d-stroller", ["stroller"]), ("e-empty", []), ("f-missing", [])] {
    let url = filterFolder.appendingPathComponent(name + ".png")
    try png.write(to: url)
    if name != "f-missing" {
        let model = try Annotation(imageURL: url, size: CGSize(width: 64, height: 48))
        for label in labels { model.add(label: label, rect: CGRect(x: 5, y: 5, width: 10, height: 10)) }
        try model.save()
    }
}
let indexed = try Dataset(folder: filterFolder)
check(indexed.matchingImageIndices(labels: []) == [0, 1, 2, 3, 4, 5])
check(indexed.matchingImageIndices(labels: ["dog"]) == [0, 2])
check(indexed.matchingImageIndices(labels: ["cat"]) == [1, 2])
check(indexed.matchingImageIndices(labels: ["dog", "cat"]) == [0, 1, 2], "Multi-label filters use OR without duplicates")
check(indexed.matchingImageIndices(labels: ["absent"]).isEmpty)
check(indexed.matchingImageIndices(labels: ["Dog"]).isEmpty, "Label matching is exact")
let snapshot = try indexed.images.map { url -> Data? in
    let xml = url.deletingPathExtension().appendingPathExtension("xml")
    return fm.fileExists(atPath: xml.path) ? try Data(contentsOf: xml) : nil
}

_ = NSApplication.shared
let controller = AppDelegate()
controller.window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1200, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
controller.setupLayout()
controller.dataset = indexed
controller.loadImage()
func chooseFilter(_ label: String, enabled: Bool = true) {
    let checkbox = NSButton(checkboxWithTitle: label, target: nil, action: nil)
    checkbox.tag = controller.dataset!.labels.firstIndex(of: label)!
    checkbox.state = enabled ? .on : .off
    controller.toggleFilter(checkbox)
}
chooseFilter("dog")
check(controller.annotation?.imageURL.lastPathComponent == "a-dog.png")
check(controller.countLabel.stringValue == "1 / 2 • 6 total")
controller.next()
check(controller.annotation?.imageURL.lastPathComponent == "c-both.png", "Next skips nonmatching images")
check(controller.annotation?.objects.count == 2, "Filtering images must keep every box visible")
controller.next()
check(controller.annotation?.imageURL.lastPathComponent == "c-both.png", "Next stops at last matching image")
controller.previous()
check(controller.annotation?.imageURL.lastPathComponent == "a-dog.png")
chooseFilter("cat")
check(controller.matchingIndices == [0, 1, 2])
controller.next()
check(controller.annotation?.imageURL.lastPathComponent == "b-cat.png")
controller.clearFilter()
check(controller.annotation?.imageURL.lastPathComponent == "b-cat.png", "Clearing preserves the current image")
let afterFiltering = try indexed.images.map { url -> Data? in
    let xml = url.deletingPathExtension().appendingPathExtension("xml")
    return fm.fileExists(atPath: xml.path) ? try Data(contentsOf: xml) : nil
}
check(snapshot == afterFiltering, "Filtering and navigation never write XML")

chooseFilter("dog")
controller.index = 0; controller.loadImage()
let aDog = controller.annotation!
controller.mutate { aDog.remove(index: 0) }
check(controller.annotation?.imageURL.lastPathComponent == "a-dog.png", "Deleting the last matching label keeps the current image visible")
check(controller.countLabel.stringValue == "Outside filter • 1 matching")
check(controller.matchingIndices == [2])
controller.undoAction()
check(controller.annotation?.imageURL.lastPathComponent == "a-dog.png")
check(controller.matchingIndices == [0, 2], "Undo refreshes the label index")
controller.binImage()
check(controller.annotation?.imageURL.lastPathComponent == "c-both.png")
check(controller.matchingIndices.count == 1)
check(fm.fileExists(atPath: filterFolder.appendingPathComponent("bin/a-dog.png").path))
controller.undoAction()
check(controller.annotation?.imageURL.lastPathComponent == "a-dog.png")
check(controller.matchingIndices == [0, 2], "Restoring a binned pair preserves filtering")
chooseFilter("dog", enabled: false)
chooseFilter("stroller")
let stroller = controller.annotation!
controller.mutate { stroller.update(index: 0, label: "cat", rect: stroller.objects[0].rect) }
check(controller.annotation?.imageURL.lastPathComponent == "d-stroller.png" && controller.canvas.image != nil)
check(controller.countLabel.stringValue == "Outside filter • 0 matching")
controller.saveAction()
check(controller.annotation?.imageURL.lastPathComponent == "d-stroller.png", "Saving again must not hide the edited image")
controller.next()
check(controller.annotation == nil && controller.canvas.image == nil)
check(controller.countLabel.stringValue == "0 / 0")
check(controller.canvas.emptyMessage == "No images match selected labels")
let filesBeforeEmptyBin = try fm.contentsOfDirectory(atPath: filterFolder.path)
controller.binImage(); controller.next(); controller.previous()
check(try fm.contentsOfDirectory(atPath: filterFolder.path) == filesBeforeEmptyBin, "R cannot move a hidden image when no matches exist")
controller.undoAction()
check(controller.annotation?.imageURL.lastPathComponent == "d-stroller.png", "Undo recovers the last matching image from an empty view")
controller.clearFilter()
check(controller.matchingIndices.count == 6)
check(try Dataset(folder: filterFolder).matchingImageIndices(labels: ["dog"]) == [0, 2])
print("PASS: label filters, OR matching, exact matching, filtered navigation/counts, no writes, edit/undo/bin/restore, empty-view safety")

let shortcutFolder = temp.appendingPathComponent("shortcut-fixtures", isDirectory: true)
try fm.createDirectory(at: shortcutFolder, withIntermediateDirectories: true)
let classes = ["dog", "cat", "stroller", "four", "five", "six", "seven", "eight", "nine", "ten"]
for (name, labels) in [("a", ["dog", "cat", "dog", "stroller", "dog", "ten"]), ("b", ["cat"])] {
    let url = shortcutFolder.appendingPathComponent(name + ".png")
    try png.write(to: url)
    let model = try Annotation(imageURL: url, size: CGSize(width: 64, height: 48))
    for label in labels { model.add(label: label, rect: CGRect(x: 5, y: 5, width: 10, height: 10)) }
    try model.save()
}
controller.dataset = try Dataset(folder: shortcutFolder)
controller.dataset?.labels = classes
controller.filterLabels = []; controller.index = 0; controller.history = []
controller.loadImage()
let shortcutFiles = try fm.contentsOfDirectory(at: shortcutFolder, includingPropertiesForKeys: nil)
let shortcutBytes = try shortcutFiles.map { try Data(contentsOf: $0) }
@discardableResult func key(_ code: UInt16, modifiers: NSEvent.ModifierFlags = [], repeatKey: Bool = false) -> Bool {
    let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
        timestamp: 0, windowNumber: controller.window.windowNumber, context: nil,
        characters: "", charactersIgnoringModifiers: "", isARepeat: repeatKey, keyCode: code)!
    return controller.handleKey(event)
}
let labelKeys: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29]
for (number, code) in labelKeys.enumerated() {
    check(key(code, modifiers: .command))
    check(controller.canvas.drawingLabel == classes[number], "Command + number arms the corresponding drawing class")
    check(controller.canvas.selected == nil)
}
check(key(53) && controller.canvas.drawingLabel == nil, "Escape still cancels drawing")
check(!key(12), "Q no longer arms the old shortcut sequence")
check(key(18) && controller.canvas.selected == 0 && controller.canvas.drawingLabel == nil)
check(key(18) && controller.canvas.selected == 2, "Repeated 1 selects the next dog, skipping other classes")
check(key(18) && controller.canvas.selected == 4)
check(key(18, repeatKey: true) && controller.canvas.selected == 4, "Holding a number must not race through boxes")
check(key(18) && controller.canvas.selected == 0, "Selection wraps to the first matching box")
check(key(19) && controller.canvas.selected == 1, "Switching labels starts at the first box")
check(key(19) && controller.canvas.selected == 1, "A single matching box stays selected")
controller.selectObject(at: 2)
check(key(18) && controller.canvas.selected == 4, "Keyboard cycling continues from a clicked box")
controller.selectObject(at: 1)
check(key(18) && controller.canvas.selected == 0, "A clicked box of another class starts the requested class at its first box")
key(53)
check(key(19, modifiers: .command) && controller.canvas.drawingLabel == "cat")
check(key(18) && controller.canvas.drawingLabel == nil && controller.canvas.selected == 0, "Number-only selection cancels drawing")
check(key(23) && controller.canvas.selected == nil && controller.status.stringValue == "No five boxes in this image")
check(key(29) && controller.canvas.selected == 5, "0 selects label 10")
check(key(82) && controller.canvas.selected == 5, "Numpad 0 also selects label 10")
key(53)
check(key(83, modifiers: .command) && controller.canvas.drawingLabel == "dog", "Numpad Command+1 arms drawing")
check(key(83) && controller.canvas.drawingLabel == nil && controller.canvas.selected == 0)
check(!key(18, modifiers: .shift) && controller.canvas.selected == 0)
check(!key(18, modifiers: [.command, .option]) && controller.canvas.selected == 0)
controller.loading = true
check(!key(19) && controller.canvas.selected == 0, "Shortcuts stay suspended during loading")
controller.loading = false
let editor = NSTextView(frame: CGRect(x: 0, y: 0, width: 100, height: 25))
controller.window.contentView?.addSubview(editor)
check(controller.window.makeFirstResponder(editor))
check(!key(19) && controller.canvas.selected == 0, "Typing a number in a field must not change selection")
check(!key(20, modifiers: .command) && controller.canvas.drawingLabel == nil)
controller.window.makeFirstResponder(controller.canvas)
editor.removeFromSuperview()
check(key(2) && controller.annotation?.imageURL.lastPathComponent == "b.png" && controller.canvas.selected == nil)
check(key(18) && controller.canvas.selected == nil, "A new image must not retain the previous image's cycle")
check(key(19) && controller.canvas.selected == 0)
check(key(0) && controller.annotation?.imageURL.lastPathComponent == "a.png")
check(key(18) && controller.canvas.selected == 0)
controller.filterLabels = ["absent"]; controller.loadImage()
check(key(18) && controller.canvas.selected == nil && controller.annotation == nil, "Selection on an empty filter is safe")
controller.clearFilter()
check(controller.history.isEmpty && !controller.dirty, "Selection and arming drawing do not create edits")
check(try shortcutFiles.map { try Data(contentsOf: $0) } == shortcutBytes, "Shortcuts must not write images or annotations")
print("PASS: Command+number drawing, number-only selection/cycling/wrap, clicked selection, numpad, field/loading guards, navigation reset, no writes")

controller.index = 0; controller.filterLabels = ["stroller"]; controller.loadImage()
let deletionImage = controller.annotation!.imageURL
let deletionXML = controller.annotation!.xmlURL
let deletionImageBytes = try Data(contentsOf: deletionImage)
let deletionImageCount = controller.dataset!.images.count
check(key(20) && controller.canvas.selected == 3)
check(key(51), "Delete must remove the selected box")
check(controller.annotation?.imageURL == deletionImage && controller.canvas.image != nil,
      "Deleting the last filtered label must keep the current image visible")
check(fm.fileExists(atPath: deletionImage.path) && fm.fileExists(atPath: deletionXML.path))
check(try Data(contentsOf: deletionImage) == deletionImageBytes)
check(controller.dataset?.images.count == deletionImageCount)
check(!fm.fileExists(atPath: shortcutFolder.appendingPathComponent("bin").path))
check(try Annotation(imageURL: deletionImage, size: CGSize(width: 64, height: 48)).objects.map(\.label) == ["dog", "cat", "dog", "dog", "ten"])
controller.undoAction()
check(controller.annotation?.objects.count == 6 && controller.annotation?.imageURL == deletionImage)
check(key(20) && controller.canvas.selected == 3)
check(key(117), "Forward Delete must also remove only the selected box")
check(controller.annotation?.imageURL == deletionImage && controller.annotation?.objects.count == 5)
check(key(51) && controller.annotation?.objects.count == 5, "Delete without a selected box does nothing")
check(fm.fileExists(atPath: deletionImage.path) && controller.dataset?.images.count == deletionImageCount)
check(key(15) && !fm.fileExists(atPath: deletionImage.path), "Only explicit R moves an edited image that no longer matches the filter")
controller.undoAction()
check(fm.fileExists(atPath: deletionImage.path) && fm.fileExists(atPath: deletionXML.path))
controller.clearFilter()
check(controller.annotation?.imageURL == deletionImage && controller.annotation?.objects.count == 5)
controller.undoAction()
controller.index = 1; controller.filterLabels = []; controller.loadImage()
let singleBoxImage = controller.annotation!.imageURL
let singleBoxXML = controller.annotation!.xmlURL
let singleBoxBytes = try Data(contentsOf: singleBoxImage)
check(key(19) && controller.canvas.selected == 0)
check(key(51) && controller.annotation?.objects.isEmpty == true)
check(controller.annotation?.imageURL == singleBoxImage && controller.canvas.image != nil)
check(fm.fileExists(atPath: singleBoxImage.path) && fm.fileExists(atPath: singleBoxXML.path))
check(try Data(contentsOf: singleBoxImage) == singleBoxBytes)
check(try Annotation(imageURL: singleBoxImage, size: CGSize(width: 64, height: 48)).objects.isEmpty)
controller.undoAction()
controller.filterLabels = ["cat"]; controller.loadImage()
check(key(19) && key(117) && controller.annotation?.objects.isEmpty == true)
check(controller.annotation?.imageURL == singleBoxImage && controller.canvas.image != nil)
check(controller.countLabel.stringValue == "Outside filter • 1 matching")
check(fm.fileExists(atPath: singleBoxImage.path) && fm.fileExists(atPath: singleBoxXML.path))
controller.undoAction()
check(controller.annotation?.imageURL == singleBoxImage && controller.annotation?.objects.count == 1)
print("PASS: Delete/Forward Delete remove only selected boxes, retain images under filters, preserve image bytes, and undo safely")

controller.filterLabels = []; controller.index = 0; controller.loadImage(); controller.history = []
let relabelImage = controller.annotation!.imageURL
let relabelXML = controller.annotation!.xmlURL
let relabelImageBytes = try Data(contentsOf: relabelImage)
controller.annotation!.objects[2].element.addChild(XMLElement(name: "confidence", stringValue: "0.87"))
controller.annotation!.objects[2].element.addChild(XMLElement(name: "custom", stringValue: "preserve me"))
try controller.annotation!.save()
controller.loadImage()
let originalLabels = controller.annotation!.objects.map(\.label)
let originalRects = controller.annotation!.objects.map(\.rect)
check(key(18) && key(18) && controller.canvas.selected == 2)
check(key(19, modifiers: .command))
check(controller.annotation?.objects.map(\.label) == ["dog", "cat", "cat", "stroller", "dog", "ten"])
check(controller.canvas.selected == 2 && controller.canvas.drawingLabel == nil, "Relabel keeps selection and does not arm drawing")
check(controller.annotation?.objects.map(\.rect) == originalRects, "Relabel preserves every box's coordinates")
let savedRelabel = try Annotation(imageURL: relabelImage, size: CGSize(width: 64, height: 48))
check(savedRelabel.objects[2].label == "cat" && savedRelabel.objects[2].confidence == "0.87")
check(savedRelabel.objects[2].element.elements(forName: "custom").first?.stringValue == "preserve me")
check(controller.history.count == 1)
let relabeledBytes = try Data(contentsOf: relabelXML)
check(key(19, modifiers: .command))
check(controller.history.count == 1, "Applying the existing label must not create an edit")
check(try Data(contentsOf: relabelXML) == relabeledBytes, "Applying the existing label must not write XML")
check(key(83, modifiers: .command) && controller.annotation?.objects[2].label == "dog", "Numpad shortcuts also relabel selected boxes")
check(controller.canvas.selected == 2 && controller.canvas.drawingLabel == nil)
controller.undoAction()
check(controller.annotation?.objects[2].label == "cat")
controller.undoAction()
check(controller.annotation?.objects.map(\.label) == originalLabels)
check(controller.annotation?.objects.map(\.rect) == originalRects)

controller.selectObject(at: 5)
check(key(18, modifiers: .command) && controller.annotation?.objects[5].label == "dog", "Click-selected boxes also relabel")
check(key(29, modifiers: .command) && controller.annotation?.objects[5].label == "ten", "Command+0 relabels to class 10")
controller.filterLabels = ["stroller"]; controller.loadImage()
check(key(20) && controller.canvas.selected == 3)
check(key(19, modifiers: .command) && controller.annotation?.objects[3].label == "cat")
check(controller.annotation?.imageURL == relabelImage && controller.canvas.selected == 3)
check(controller.annotation?.objects.count == originalLabels.count && controller.matchingIndices.isEmpty)
check(controller.countLabel.stringValue == "Outside filter • 0 matching", "Relabeling the last matching box keeps the current image visible")
controller.undoAction()
check(controller.annotation?.objects[3].label == "stroller" && controller.matchingIndices == [0])
controller.selectObject(at: 3)
check(key(53) && controller.canvas.selected == nil, "Escape clears selection so drawing remains available")
let beforeDrawingShortcut = try Data(contentsOf: relabelXML)
check(key(19, modifiers: .command) && controller.canvas.drawingLabel == "cat" && controller.canvas.selected == nil)
check(try Data(contentsOf: relabelXML) == beforeDrawingShortcut, "With no selection Command+number still only arms drawing")
key(53)
check(try Data(contentsOf: relabelImage) == relabelImageBytes, "Relabeling must not alter image data")
check(controller.dataset?.images.count == 2)
print("PASS: selected-box Command+number relabel, saved XML/metadata/geometry preservation, same-label no-op, numpad/label 10, undo, filter retention, drawing fallback")

let unlabeledDataset = try Dataset(folder: filterFolder)
check(unlabeledDataset.matchingImageIndices(labels: [], includeUnlabeled: true) == [4, 5])
check(unlabeledDataset.matchingImageIndices(labels: ["dog"], includeUnlabeled: true) == [0, 2, 4, 5])
check(unlabeledDataset.matchingImageIndices(labels: ["absent"], includeUnlabeled: true) == [4, 5])
controller.dataset = unlabeledDataset; controller.index = 0; controller.filterLabels = []; controller.history = []
controller.loadImage()
let noLabelsCheckbox = NSButton(checkboxWithTitle: "No labels", target: nil, action: nil)
noLabelsCheckbox.state = .on
controller.toggleUnlabeledFilter(noLabelsCheckbox)
check(controller.filterActive && controller.matchingIndices == [4, 5])
check(controller.annotation?.imageURL.lastPathComponent == "e-empty.png")
check(controller.countLabel.stringValue == "1 / 2 • 6 total")
controller.next()
check(controller.annotation?.imageURL.lastPathComponent == "f-missing.png")
let missingXML = controller.annotation!.xmlURL
check(!fm.fileExists(atPath: missingXML.path), "Viewing missing annotations must not create XML")
controller.previous()
check(controller.annotation?.imageURL.lastPathComponent == "e-empty.png")
chooseFilter("dog")
check(controller.matchingIndices == [0, 2, 4, 5], "No labels combines with class filters using OR")
chooseFilter("dog", enabled: false)
let emptyModel = controller.annotation!
controller.mutate { emptyModel.add(label: "dog", rect: CGRect(x: 1, y: 2, width: 10, height: 12)) }
check(controller.matchingIndices == [5] && controller.annotation?.imageURL.lastPathComponent == "e-empty.png")
check(controller.countLabel.stringValue == "Outside filter • 1 matching", "Adding a box updates No labels without hiding the image")
controller.selectObject(at: 0); controller.deleteObject()
check(controller.matchingIndices == [4, 5], "Deleting the last box adds the image back to No labels")
controller.undoAction()
check(controller.matchingIndices == [5])
controller.undoAction()
check(controller.matchingIndices == [4, 5] && controller.annotation?.objects.isEmpty == true)
controller.next(); controller.binImage()
check(controller.matchingIndices.count == 1 && !fm.fileExists(atPath: missingXML.path))
controller.undoAction()
check(controller.matchingIndices == [4, 5] && controller.annotation?.imageURL.lastPathComponent == "f-missing.png")
check(!fm.fileExists(atPath: missingXML.path))
controller.clearFilter()
check(!controller.filterActive && !controller.filterUnlabeled && controller.matchingIndices.count == 6)

let invalidFolder = temp.appendingPathComponent("invalid-unlabeled", isDirectory: true)
try fm.createDirectory(at: invalidFolder, withIntermediateDirectories: true)
for (name, xmlText) in [("a-unreadable", "<annotation>"), ("b-wrong-root", "<other/>"),
                        ("c-invalid-object", "<annotation><object><name/></object></annotation>")] {
    try png.write(to: invalidFolder.appendingPathComponent(name + ".png"))
    try Data(xmlText.utf8).write(to: invalidFolder.appendingPathComponent(name + ".xml"))
}
check(try Dataset(folder: invalidFolder).matchingImageIndices(labels: [], includeUnlabeled: true).isEmpty,
      "Unreadable XML and invalid objects must not be classified as unlabeled")
print("PASS: No labels filter, empty/missing XML, OR combination, navigation/counts, annotation edits/undo, bin/restore, clear, invalid XML exclusion")

if CommandLine.arguments.count > 1 {
    let folder = URL(fileURLWithPath: CommandLine.arguments[1])
    let real = try Dataset(folder: folder)
    var count = 0, invalid = 0
    var expectedMatches: [String: Set<Int>] = [:]
    for (index, image) in real.images.enumerated() {
        let model = try Annotation(imageURL: image, size: CGSize(width: 1280, height: 720))
        count += model.objects.count
        invalid += model.objects.filter { $0.rect.width <= 0 || $0.rect.height <= 0 }.count
        for object in model.objects { expectedMatches[object.label, default: []].insert(index) }
    }
    for label in real.labels {
        check(real.matchingImageIndices(labels: [label]) == (expectedMatches[label] ?? []).sorted())
    }
    check(real.matchingImageIndices(labels: Set(real.labels)) == Set(expectedMatches.values.flatMap { $0 }).sorted())
    print("READ-ONLY DATASET: \(real.images.count) images, \(count) objects, labels: \(real.labels), degenerate boxes: \(invalid)")
    print("PASS: real dataset single-label and combined filters agree with parsed annotations")
}
