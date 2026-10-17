import AppKit

func labelColor(_ label: String) -> NSColor {
    let colors: [NSColor] = [.systemBlue, .systemOrange, .systemPink, .systemTeal, .systemPurple, .systemGreen, .systemYellow]
    let hash = label.utf8.reduce(0) { ($0 * 31 + Int($1)) % 997 }
    return colors[hash % colors.count]
}

final class ImageCanvas: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    var image: NSImage?
    var emptyMessage = "Choose a folder to start reviewing"
    var annotation: Annotation?
    var selected: Int? { didSet { needsDisplay = true } }
    var drawingLabel: String? { didSet { needsDisplay = true } }
    var onSelect: ((Int?) -> Void)?
    var onCreate: ((String, CGRect) -> Void)?
    var onChange: ((Int, CGRect) -> Void)?
    private var zoom: CGFloat = 1
    private var pan = CGPoint.zero
    private var start: CGPoint?
    private var original: CGRect?
    private var corner: Int?
    private var preview: CGRect?
    private var panning = false
    private var panStart = CGPoint.zero

    var imageRect: CGRect {
        guard let size = annotation?.size, size.width > 0, size.height > 0 else { return .zero }
        let fit = min(max(1, bounds.width - 64) / size.width, max(1, bounds.height - 64) / size.height)
        let width = size.width * fit * zoom, height = size.height * fit * zoom
        return CGRect(x: (bounds.width - width) / 2 + pan.x, y: (bounds.height - height) / 2 + pan.y, width: width, height: height)
    }
    var scale: CGFloat { imageRect.width / max(1, annotation?.size.width ?? 1) }
    func displayRect(_ rect: CGRect) -> CGRect {
        let frame = imageRect
        return CGRect(x: frame.minX + rect.origin.x * scale, y: frame.minY + rect.origin.y * scale,
                      width: rect.width * scale, height: rect.height * scale)
    }
    func imagePoint(_ point: CGPoint) -> CGPoint {
        let frame = imageRect, size = annotation?.size ?? .zero
        return CGPoint(x: min(size.width, max(0, (point.x - frame.minX) / scale)),
                       y: min(size.height, max(0, (point.y - frame.minY) / scale)))
    }
    func corners(_ rect: CGRect) -> [CGPoint] {
        [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
         CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
    }
    func reset() {
        zoom = 1; pan = .zero; selected = nil; drawingLabel = nil
        cancelGesture(); needsDisplay = true
    }
    func cancelGesture() {
        start = nil; original = nil; corner = nil; preview = nil; panning = false; needsDisplay = true
    }
    func fit() { zoom = 1; pan = .zero; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.10, green: 0.13, blue: 0.17, alpha: 1).setFill()
        bounds.fill()
        guard let image, let annotation else {
            let text = emptyMessage
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 22, weight: .medium), .foregroundColor: NSColor.white]
            let size = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: (bounds.width-size.width)/2, y: bounds.height/2), withAttributes: attrs)
            return
        }
        image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        for (index, object) in annotation.objects.enumerated() {
            drawBox(index == selected ? (preview ?? object.rect) : object.rect,
                    label: object.label, selected: index == selected)
        }
        if let label = drawingLabel, let preview, original == nil { drawBox(preview, label: label, selected: true) }
    }
    func drawBox(_ box: CGRect, label: String, selected: Bool) {
        let rect = displayRect(box), color = labelColor(label)
        color.withAlphaComponent(selected ? 0.15 : 0.04).setFill(); rect.fill()
        color.setStroke()
        let outline = NSBezierPath(rect: rect); outline.lineWidth = selected ? 3 : 1.5; outline.stroke()
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white]
        let textSize = label.size(withAttributes: attrs)
        let tag = CGRect(x: rect.minX, y: max(0, rect.minY - 22), width: textSize.width + 12, height: 22)
        color.withAlphaComponent(0.95).setFill(); tag.fill()
        label.draw(at: CGPoint(x: tag.minX + 6, y: tag.minY + 3), withAttributes: attrs)
        if selected {
            for point in corners(rect) {
                let handle = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
                NSColor.white.setFill(); handle.fill(); color.setStroke(); NSBezierPath(rect: handle).stroke()
            }
        }
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        beginGesture(at: convert(event.locationInWindow, from: nil), pan: event.modifierFlags.contains(.option))
    }
    func beginGesture(at point: CGPoint, pan usePan: Bool = false) {
        guard let annotation else { return }
        if usePan {
            panning = true; start = point; panStart = pan; return
        }
        if drawingLabel != nil {
            guard imageRect.contains(point) else { return }
            selected = nil; start = imagePoint(point); original = nil; preview = nil
            return
        }
        if let selected, annotation.objects.indices.contains(selected) {
            let rect = annotation.objects[selected].rect
            for (index, handle) in corners(displayRect(rect)).enumerated() {
                if hypot(handle.x - point.x, handle.y - point.y) <= 12 {
                    corner = index; original = rect; start = imagePoint(point); return
                }
            }
        }
        // Prefer the smallest box under the pointer when detections overlap.
        let hit = annotation.objects.indices.filter { displayRect(annotation.objects[$0].rect).contains(point) }
            .min { abs(annotation.objects[$0].rect.width * annotation.objects[$0].rect.height) < abs(annotation.objects[$1].rect.width * annotation.objects[$1].rect.height) }
        selected = hit; onSelect?(hit)
        if let hit { start = imagePoint(point); original = annotation.objects[hit].rect; corner = nil }
    }
    override func mouseDragged(with event: NSEvent) {
        continueGesture(at: convert(event.locationInWindow, from: nil))
    }
    func continueGesture(at location: CGPoint) {
        guard let start, let annotation else { return }
        if panning {
            pan = CGPoint(x: panStart.x + location.x - start.x, y: panStart.y + location.y - start.y)
            needsDisplay = true; return
        }
        let point = imagePoint(location)
        if let original {
            if let corner {
                let opposite = corners(original)[(corner + 2) % 4]
                preview = CGRect(x: min(opposite.x, point.x), y: min(opposite.y, point.y),
                                 width: abs(opposite.x - point.x), height: abs(opposite.y - point.y))
            } else {
                preview = CGRect(x: max(0, min(annotation.size.width - original.width, original.minX + point.x - start.x)),
                                 y: max(0, min(annotation.size.height - original.height, original.minY + point.y - start.y)),
                                 width: original.width, height: original.height)
            }
        } else {
            preview = CGRect(x: min(start.x, point.x), y: min(start.y, point.y), width: abs(point.x-start.x), height: abs(point.y-start.y))
        }
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        finishGesture()
    }
    func finishGesture() {
        defer { cancelGesture() }
        guard !panning, let rect = preview, rect.width >= 1, rect.height >= 1 else { return }
        let rounded = CGRect(x: rect.minX.rounded(), y: rect.minY.rounded(),
                             width: rect.maxX.rounded() - rect.minX.rounded(), height: rect.maxY.rounded() - rect.minY.rounded())
        guard rounded.width > 0, rounded.height > 0 else { return }
        if let original, let selected {
            if original != rounded { onChange?(selected, rounded) }
        } else if let drawingLabel { onCreate?(drawingLabel, rounded) }
    }
    override func scrollWheel(with event: NSEvent) {
        guard annotation != nil, start == nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        let previous = imageRect
        let factor = exp(event.scrollingDeltaY * 0.012)
        zoom = min(12, max(1, zoom * factor))
        let current = imageRect
        if previous.width > 0 {
            let ratio = current.width / previous.width
            pan.x += point.x - (current.minX + (point.x - previous.minX) * ratio)
            pan.y += point.y - (current.minY + (point.y - previous.minY) * ratio)
        }
        if zoom == 1 { pan = .zero }
        needsDisplay = true
    }
}
