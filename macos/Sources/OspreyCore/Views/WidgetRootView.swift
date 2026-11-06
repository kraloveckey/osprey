import AppKit
import SwiftUI

// MARK: - Section identity

/// Ordered list of section slots. The order is fixed; visibility flags select which
/// slots appear in the grid. Using an enum makes ForEach ids stable and unique.
enum WidgetSection: Int, CaseIterable, Identifiable {
    case cpu, memory, disk, power, network, processes
    var id: Int { rawValue }
}

// MARK: - Size presets

/// One-tap presets that set the visible section mix and grid layout.
/// nil activePreset means the user has a custom selection that matches none of the presets.
private enum SizePreset: CaseIterable {
    case small, medium, large, extraLarge

    var sections: Set<WidgetSection> {
        switch self {
        case .small:      return [.cpu, .memory]
        case .medium:     return [.cpu, .memory, .disk, .power]
        case .large:      return Set(WidgetSection.allCases)
        case .extraLarge: return Set(WidgetSection.allCases)
        }
    }

    var columns: Int {
        switch self {
        case .small, .medium, .large: return 2
        case .extraLarge:             return 3
        }
    }

    var label: String {
        switch self {
        case .small:      return "S"
        case .medium:     return "M"
        case .large:      return "L"
        case .extraLarge: return "XL"
        }
    }

    var helpText: String {
        switch self {
        case .small:      return "Small – CPU & Memory (1×2)"
        case .medium:     return "Medium – CPU, Memory, Disk & Power (2×2)"
        case .large:      return "Large – All sections (Vertical 2×3)"
        case .extraLarge: return "Extra Large – All sections (Wide 3×2)"
        }
    }
}

// MARK: - WidgetRootView

/// Root widget view: an always-visible title bar (app icon + name on the
/// left, size/zoom/lock controls on the right), a dynamic grid of sections
/// on a dark backdrop, and resize handles on the right edge, the bottom edge
/// and the bottom-right corner.
///
/// Size model: the height always equals the measured content height
/// (`WidgetGeometry.naturalHeight`), so nothing is clipped and no empty
/// bands appear. The right edge changes only the width (columns widen);
/// the bottom edge and the corner zoom the whole widget proportionally.
public struct WidgetRootView: View {
    let store: MetricsStore
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var geometry = WidgetGeometry.shared

    @AppStorage(WidgetSettings.positionLockedKey) private var positionLocked = false
    @AppStorage(WidgetSettings.widgetVisibleKey)  private var widgetVisible  = true
    @AppStorage(WidgetSettings.alwaysOnTopKey)    private var alwaysOnTop    = false
    @AppStorage(WidgetSettings.widgetWidthKey)    private var widgetWidth    = WidgetSettings.defaultWidth
    @AppStorage(WidgetSettings.widgetHeightKey)   private var widgetHeight   = 0.0
    @AppStorage(WidgetSettings.widgetColumnsKey)  private var widgetColumns  = WidgetSettings.defaultColumns
    @AppStorage(WidgetSettings.widgetScaleKey)    private var widgetScale    = WidgetSettings.defaultScale

    // Appearance
    @AppStorage(WidgetSettings.backgroundOpacityKey)
    private var backgroundOpacity = WidgetSettings.defaultOpacity
    @AppStorage(WidgetSettings.fontSizeKey)
    private var fontSize = WidgetSettings.defaultFontSize
    @AppStorage(WidgetSettings.fontStyleKey)
    private var fontStyle = WidgetSettings.defaultFontStyle.rawValue

    // Section visibility
    @AppStorage(WidgetSettings.showHeaderKey)    private var showHeader    = true
    @AppStorage(WidgetSettings.showCPUKey)       private var showCPU       = true
    @AppStorage(WidgetSettings.showMemoryKey)    private var showMemory    = true
    @AppStorage(WidgetSettings.showDiskKey)      private var showDisk      = true
    @AppStorage(WidgetSettings.showPowerKey)     private var showPower     = true
    @AppStorage(WidgetSettings.showNetworkKey)   private var showNetwork   = true
    @AppStorage(WidgetSettings.showProcessesKey) private var showProcesses = true

    @State private var dragStartWidth: Double?
    @State private var dragStartMouse: CGPoint?
    @State private var dragStart: DragStart?
    @State private var liveResizeFactor = 1.0
    @State private var liveResizeTargetScale: Double?

    /// Size, zoom and mouse position captured when a proportional
    /// (bottom/corner) drag begins.
    private struct DragStart {
        let scale: Double
        let width: Double
        let height: Double
        let mouse: CGPoint
    }

    /// Mouse movement since `start`, in screen points (x right, y down).
    ///
    /// Deliberately *not* `DragGesture.translation`: that is measured in the
    /// window's own coordinates, and the window moves and resizes while it is
    /// being dragged – the translation then changes even with the mouse held
    /// still, which resized the window again: the shaking.
    private static func mouseDelta(from start: CGPoint) -> CGSize {
        let now = NSEvent.mouseLocation
        return CGSize(width: now.x - start.x, height: start.y - now.y)
    }

    /// Rows of the section grid for the current column mode.
    private var gridRows: [[WidgetSection]] {
        widgetColumns == 3
            ? rowsFor3Columns(from: enabledSections)
            : enabledSections.chunks(of: 2)
    }

    private var outerPadding: CGFloat { 12 * cs }

    /// Measured content height at the current zoom, or nil before the first
    /// layout pass. The widget is always exactly this tall: nothing is ever
    /// clipped and there are never empty bands.
    private var naturalHeight: Double? {
        geometry.naturalHeight > 0 ? ceil(Double(geometry.naturalHeight) * widgetScale) : nil
    }

    /// Height the widget is drawn at (matches the window height that
    /// AppDelegate.syncWindowSize sets). nil = let the content decide.
    private var displayHeight: CGFloat? {
        naturalHeight.map { CGFloat($0) }
    }

    private var displayWidth: CGFloat {
        CGFloat(WidgetSettings.clampWidth(widgetWidth, columns: widgetColumns, scale: widgetScale))
    }

    /// Content scale = zoom. Dragging the bottom edge or the corner changes
    /// the zoom continuously, so the whole widget grows or shrinks evenly.
    private var cs: CGFloat { CGFloat(widgetScale) }

    private var rowSpacing: CGFloat { (widgetColumns == 3 ? 12 : 10) * cs }

    /// Responsive column width: whatever the widget width leaves after the
    /// padding (2 × 12) and the 20 pt column gaps, all at content scale.
    private var columnWidth: CGFloat {
        let totalWidth = WidgetSettings.clampWidth(widgetWidth, columns: widgetColumns, scale: widgetScale)
        let columns = CGFloat(max(1, widgetColumns))
        let fixed = (columns - 1) * 20 * cs + 2 * outerPadding
        return max(310 * cs, (totalWidth - fixed) / columns)
    }

    /// Ordered list of enabled section slots.
    private var enabledSections: [WidgetSection] {
        WidgetSection.allCases.filter { section in
            switch section {
            case .cpu:       return showCPU
            case .memory:    return showMemory
            case .disk:      return showDisk
            case .power:     return showPower
            case .network:   return showNetwork
            case .processes: return showProcesses
            }
        }
    }

    /// nil when the current section mix doesn't match any preset.
    private var activePreset: SizePreset? {
        let current = Set(WidgetSection.allCases.filter { section in
            switch section {
            case .cpu:       return showCPU
            case .memory:    return showMemory
            case .disk:      return showDisk
            case .power:     return showPower
            case .network:   return showNetwork
            case .processes: return showProcesses
            }
        })
        if current == SizePreset.small.sections { return .small }
        if current == SizePreset.medium.sections { return .medium }
        if current == SizePreset.large.sections {
            return widgetColumns == 3 ? .extraLarge : .large
        }
        return nil
    }

    private func applyPreset(_ preset: SizePreset) {
        widgetColumns = preset.columns
        showCPU       = preset.sections.contains(.cpu)
        showMemory    = preset.sections.contains(.memory)
        showDisk      = preset.sections.contains(.disk)
        showPower     = preset.sections.contains(.power)
        showNetwork   = preset.sections.contains(.network)
        showProcesses = preset.sections.contains(.processes)
        widgetHeight  = 0 // Snap to natural snug height for new preset

        switch preset {
        case .small:
            widgetWidth = 540 * widgetScale
        case .medium:
            widgetWidth = WidgetSettings.defaultWidth * widgetScale
        case .large:
            widgetWidth = WidgetSettings.defaultWidth * widgetScale
        case .extraLarge:
            widgetWidth = WidgetSettings.defaultWideWidth * widgetScale
        }
    }

    /// Organizes sections into a 3-column wide layout (3×2).
    /// Places CPU/Disk in Column 1, Memory/Power in Column 2, and Network/Processes in Column 3 (the right side).
    private func rowsFor3Columns(from sections: [WidgetSection]) -> [[WidgetSection]] {
        let col1Candidates: [WidgetSection] = [.cpu, .disk]
        let col2Candidates: [WidgetSection] = [.memory, .power]
        let col3Candidates: [WidgetSection] = [.network, .processes]

        let col1 = col1Candidates.filter { sections.contains($0) }
        let col2 = col2Candidates.filter { sections.contains($0) }
        let col3 = col3Candidates.filter { sections.contains($0) }

        var row0: [WidgetSection] = []
        var row1: [WidgetSection] = []

        if let c1 = col1.first { row0.append(c1) }
        if let c2 = col2.first { row0.append(c2) }
        if let c3 = col3.first { row0.append(c3) }

        if col1.count > 1 { row1.append(col1[1]) }
        if col2.count > 1 { row1.append(col2[1]) }
        if col3.count > 1 { row1.append(col3[1]) }

        var result: [[WidgetSection]] = []
        if !row0.isEmpty { result.append(row0) }
        if !row1.isEmpty { result.append(row1) }

        let handled = Set(row0 + row1)
        let remaining = sections.filter { !handled.contains($0) }
        if !remaining.isEmpty {
            for chunk in remaining.chunks(of: 3) {
                result.append(Array(chunk))
            }
        }

        return result.isEmpty ? sections.chunks(of: 3).map { Array($0) } : result
    }

    public init(store: MetricsStore) {
        self.store = store
    }

    public var body: some View {
        let allHidden = !showHeader && enabledSections.isEmpty

        SpreadVStack(
            spacing: rowSpacing,
            pinnedCount: showHeader && !allHidden ? 2 : 1,
            pinnedSpacing: 10 * cs,
            distribution: .children,
            reportsNaturalHeight: 2 * outerPadding,
            reportScale: cs
        ) {
            titleBar
            if allHidden {
                Text("All sections hidden")
                    .foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                if showHeader {
                    HeaderView(info: store.systemInfo, score: store.healthScore)
                }
                ForEach(Array(gridRows.enumerated()), id: \.offset) { _, row in
                    gridRow(row)
                }
            }
        }
        .font(Theme.font(
            size: WidgetSettings.clampFontSize(fontSize) * cs,
            style: WidgetSettings.resolveFontStyle(fontStyle)
        ))
        .environment(\.contentScale, cs)
        .padding(outerPadding)
        .frame(
            width: displayWidth,
            height: displayHeight,
            alignment: .topLeading
        )
        .modifier(WidgetBackground(opacity: backgroundOpacity))
        .overlay(alignment: .trailing) {
            resizeHandle
        }
        .overlay(alignment: .bottom) {
            bottomResizeHandle
        }
        .overlay(alignment: .bottomTrailing) {
            cornerResizeHandle
        }
        // During a proportional drag, transform the already-rendered widget
        // as one composited layer. Its internal layout remains frozen until
        // mouse-up, eliminating the expensive text/grid re-layout that made
        // bottom and corner resizing visibly stutter.
        .compositingGroup()
        .scaleEffect(CGFloat(liveResizeFactor), anchor: .topLeading)
        .frame(
            width: displayWidth * CGFloat(liveResizeFactor),
            height: displayHeight.map { $0 * CGFloat(liveResizeFactor) },
            alignment: .topLeading
        )
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenInspectorWindow"))) { notif in
            if let id = notif.object as? String {
                openWindow(id: id)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .onReceive(DistributedNotificationCenter.default().publisher(for: NSNotification.Name("com.kraloveckey.osprey.openWindow"))) { notif in
            if let id = notif.object as? String {
                openWindow(id: id)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    // MARK: - Grid row

    /// One grid row: fixed-width columns; every cell stretches to the row
    /// height so its section can spread its lines over the full cell.
    private func gridRow(_ row: [WidgetSection]) -> some View {
        HStack(alignment: .top, spacing: 20 * cs) {
            ForEach(0..<widgetColumns, id: \.self) { column in
                if column < row.count {
                    sectionView(for: row[column])
                        .frame(width: columnWidth, alignment: .topLeading)
                        .frame(maxHeight: .infinity, alignment: .top)
                } else {
                    Color.clear.frame(width: columnWidth, height: 0)
                }
            }
        }
    }

    // MARK: - Title bar


    /// Always-visible first row: Osprey logo and title on the left,
    /// advisory warning badge in the center, and controls on the right.
    private var titleBar: some View {
        HStack(spacing: 8 * cs) {
            HStack(spacing: 6 * cs) {
                Image(nsImage: OspreyMark.image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 20 * cs, height: 20 * cs)
                    .accessibilityHidden(true)
                Text("Osprey")
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.header)
            }

            if let adv = store.advisory, adv.shouldReboot {
                Button {
                    AdvisoryCollector.sendNativeNotification(
                        title: "Osprey Advisory",
                        body: adv.summary
                    )
                } label: {
                    HStack(spacing: 3 * cs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9 * cs))
                        Text("\(adv.swapUsedFormatted) Swap")
                            .font(.system(size: 10 * cs, weight: .bold))
                    }
                    .padding(.horizontal, 6 * cs)
                    .padding(.vertical, 2 * cs)
                    .background(Theme.danger.opacity(0.2))
                    .foregroundStyle(Theme.danger)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(adv.summary)
            }

            Spacer()
            HStack(spacing: 4 * cs) {
                activityMonitorButton
                sizeButtons
                zoomButtons
                lockButton
                hideButton
            }
        }
    }


    // MARK: - Section factory

    @ViewBuilder
    private func sectionView(for section: WidgetSection) -> some View {
        switch section {
        case .cpu:
            CPUSectionView(snapshot: store.cpu, history: store.cpuHistory.values, temperature: store.cpuTemperature).equatable()
        case .memory:
            MemorySectionView(snapshot: store.memory, swap: store.advisory?.swapUsedFormatted).equatable()
        case .disk:
            DiskSectionView(
                usage: store.diskUsage,
                io: store.diskIO,
                smart: store.smart,
                readHistory: store.diskReadHistory.values,
                writeHistory: store.diskWriteHistory.values
            ).equatable()

        case .power:
            PowerSectionView(snapshot: store.power).equatable()
        case .network:
            NetworkSectionView(
                rates: store.netRates,
                info: store.networkInfo,
                downloadHistory: store.netInHistory.values,
                uploadHistory: store.netOutHistory.values
            ).equatable()
        case .processes:
            ProcessesSectionView(processes: store.topProcesses).equatable()
        }
    }

    // MARK: - Resize handles

    /// Invisible strip along the right edge; drag it to resize the widget width.
    /// Disabled while the position is locked.
    private var resizeHandle: some View {
        Color.clear
            .frame(width: 12)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { inside in
                guard !positionLocked else { return }
                if inside {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { _ in
                        guard !positionLocked else { return }
                        let start = dragStartWidth ?? widgetWidth
                        let mouse = dragStartMouse ?? NSEvent.mouseLocation
                        dragStartWidth = start
                        dragStartMouse = mouse
                        let dx = Self.mouseDelta(from: mouse).width
                        widgetWidth = WidgetSettings.clampWidth(start + dx, columns: widgetColumns, scale: widgetScale)
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                        dragStartMouse = nil
                    }
            )
    }

    /// Height the widget currently has on screen.
    private var currentHeight: Double {
        naturalHeight ?? WidgetSettings.minHeight
    }

    /// Largest zoom that still fits on screen for the exact size captured at
    /// drag start (not merely the minimum width for the current column count).
    private func maxZoomForScreen(start: DragStart) -> Double {
        let safeScale = max(start.scale, 0.01)
        let perUnitWidth = start.width / safeScale
        let perUnitHeight = start.height / safeScale
        let byWidth = perUnitWidth > 0 ? WidgetSettings.screenMaxWidth() / perUnitWidth : WidgetSettings.maxScale
        let byHeight = perUnitHeight > 0 ? WidgetSettings.screenMaxHeight() / perUnitHeight : WidgetSettings.maxScale
        return min(WidgetSettings.maxScale, byWidth, byHeight)
    }

    /// Proportional resize from a drag: the zoom follows the size ratio
    /// relative to where the drag started, the width follows the zoom.
    /// No measuring feeds back into the size, so it can't oscillate.
    private func previewDragZoom(ratio: Double, start: DragStart) {
        let target = start.scale * ratio
        let maximum = max(WidgetSettings.minScale, maxZoomForScreen(start: start))
        let clamped = min(max(target, WidgetSettings.minScale), maximum)
        let factor = clamped / max(start.scale, 0.01)
        guard abs(factor - liveResizeFactor) > 0.0001 else { return }

        liveResizeTargetScale = clamped
        liveResizeFactor = factor
        NotificationCenter.default.post(
            name: .ospreyWidgetLiveResize,
            object: NSValue(size: NSSize(
                width: start.width * factor,
                height: start.height * factor
            ))
        )
    }

    /// Commits one real SwiftUI layout after the composited live preview.
    private func finishDragZoom() {
        defer {
            dragStart = nil
            liveResizeTargetScale = nil
        }

        guard let start = dragStart, let targetScale = liveResizeTargetScale else {
            liveResizeFactor = 1
            NotificationCenter.default.post(name: .ospreyWidgetLiveResizeEnded, object: nil)
            return
        }

        let factor = targetScale / max(start.scale, 0.01)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            widgetScale = targetScale
            widgetWidth = WidgetSettings.clampWidth(
                start.width * factor,
                columns: widgetColumns,
                scale: targetScale
            )
            liveResizeFactor = 1
        }
        NotificationCenter.default.post(name: .ospreyWidgetLiveResizeEnded, object: nil)
    }

    /// Strip along the bottom edge: drag to zoom the whole widget (width
    /// follows proportionally). Double-click resets the zoom to 100 %.
    private var bottomResizeHandle: some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .frame(height: 14)
                .contentShape(Rectangle())

            // Subtle grab pill indicator in center
            Capsule()
                .fill(Color.white.opacity(0.20))
                .frame(width: 36, height: 3)
                .padding(.bottom, 3)
        }
        .frame(maxWidth: .infinity)
        .onHover { inside in
            guard !positionLocked else { return }
            if inside {
                NSCursor.resizeUpDown.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { _ in
                    guard !positionLocked else { return }
                    let start = dragStart ?? DragStart(
                        scale: widgetScale, width: widgetWidth, height: currentHeight, mouse: NSEvent.mouseLocation
                    )
                    dragStart = start
                    let dy = Self.mouseDelta(from: start.mouse).height
                    previewDragZoom(ratio: (start.height + dy) / start.height, start: start)
                }
                .onEnded { _ in finishDragZoom() }
        )
        .onTapGesture(count: 2) {
            guard !positionLocked else { return }
            setZoom(to: 1.0)
        }
    }

    /// Corner handle: drag to zoom the whole widget proportionally. The mouse
    /// delta is projected onto the widget diagonal so small changes in drag
    /// direction cannot make the controlling axis flip and jitter.
    private var cornerResizeHandle: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())

            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 6 * cs, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.30))
                // 6 pt glyph + 5 pt inset stays inside the 12 pt
                // content margin at every zoom level.
                .padding(.trailing, 5 * cs)
                .padding(.bottom, 5 * cs)
        }
        .onHover { inside in
            guard !positionLocked else { return }
            if inside {
                NSCursor.crosshair.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { _ in
                    guard !positionLocked else { return }
                    let start = dragStart ?? DragStart(
                        scale: widgetScale, width: widgetWidth, height: currentHeight, mouse: NSEvent.mouseLocation
                    )
                    dragStart = start
                    let delta = Self.mouseDelta(from: start.mouse)
                    let diagonalSquared = start.width * start.width + start.height * start.height
                    let ratio = 1 + (
                        delta.width * start.width + delta.height * start.height
                    ) / max(diagonalSquared, 1)
                    previewDragZoom(ratio: ratio, start: start)
                }
                .onEnded { _ in finishDragZoom() }
        )
        .onTapGesture(count: 2) {
            guard !positionLocked else { return }
            setZoom(to: 1.0)
        }
    }

    // MARK: - Zoom controls

    private var zoomButtons: some View {
        HStack(spacing: 1 * cs) {
            Button {
                adjustZoom(by: -0.05)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 9 * cs, weight: .bold))
                    .foregroundStyle(widgetScale > WidgetSettings.minScale ? Theme.header : Theme.dim.opacity(0.3))
                    .frame(width: 14 * cs, height: 20 * cs)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(widgetScale <= WidgetSettings.minScale)
            .help("Zoom out")

            Button {
                setZoom(to: 1.0)
            } label: {
                Text("\(Int(round(widgetScale * 100)))%")
                    .font(.system(size: 9 * cs, weight: .medium, design: .monospaced))
                    .foregroundStyle(abs(widgetScale - 1.0) > 0.01 ? Theme.accent : Theme.dim)
                    .frame(width: 32 * cs, height: 20 * cs)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Reset zoom to 100%")

            Button {
                adjustZoom(by: 0.05)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 9 * cs, weight: .bold))
                    .foregroundStyle(widgetScale < WidgetSettings.maxScale ? Theme.header : Theme.dim.opacity(0.3))
                    .frame(width: 14 * cs, height: 20 * cs)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(widgetScale >= WidgetSettings.maxScale)
            .help("Zoom in")
        }
        .padding(.horizontal, 2 * cs)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func adjustZoom(by delta: Double) {
        let oldScale = widgetScale
        let newScale = WidgetSettings.clampScale(oldScale + delta)
        guard abs(newScale - oldScale) > 0.001 else { return }
        setZoom(to: newScale)
    }

    private func setZoom(to newScale: Double) {
        let oldScale = widgetScale
        let clamped = WidgetSettings.clampScale(newScale)
        widgetScale = clamped
        let ratio = clamped / max(0.1, oldScale)
        widgetWidth = WidgetSettings.clampWidth(widgetWidth * ratio, columns: widgetColumns, scale: clamped)
    }

    // MARK: - Size preset buttons

    private var sizeButtons: some View {
        HStack(spacing: 0 * cs) {
            ForEach(SizePreset.allCases, id: \.label) { preset in
                Button { applyPreset(preset) } label: {
                    Text(preset.label)
                        .font(.system(size: 11 * cs, weight: .medium))
                        .foregroundStyle(activePreset == preset ? Theme.header : Theme.dim)
                        .frame(width: (preset == .extraLarge ? 20 : 16) * cs, height: 20 * cs)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(preset.helpText)
            }
        }
    }

    // MARK: - Lock button

    private var lockButton: some View {
        Button {
            positionLocked.toggle()
        } label: {
            Image(systemName: positionLocked ? "lock.fill" : "lock.open")
                .font(.system(size: 11 * cs, weight: .medium))
                .foregroundStyle(positionLocked ? Theme.warning : Theme.dim)
                .frame(width: 20 * cs, height: 20 * cs) // hit area slightly larger than the icon
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(positionLocked
            ? "Position and size are locked – click to unlock"
            : "Click to lock the widget position and size")
    }

    // MARK: - Hide button

    private var hideButton: some View {
        Button {
            widgetVisible = false
            alwaysOnTop = false
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 11 * cs, weight: .bold))
                .foregroundStyle(Theme.dim)
                .frame(width: 20 * cs, height: 20 * cs)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Close / hide widget – summon again anytime from the menu bar icon")
    }

    // MARK: - Activity Monitor button

    private var activityMonitorButton: some View {
        Button {
            AppLauncher.openActivityMonitor()
        } label: {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 11 * cs, weight: .bold))
                .foregroundStyle(Theme.dim)
                .frame(width: 20 * cs, height: 20 * cs)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open Activity Monitor")
    }
}


// MARK: - Background

/// NSVisualEffectView wrapper – gives the same frosted-glass material native desktop
/// widgets use (.hudWindow + behindWindow blending). Stays active regardless of
/// window focus since the widget never becomes key.
private struct FrostView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .sidebar
        v.blendingMode = .behindWindow
        v.state = .active
        v.appearance = NSAppearance(named: .darkAqua)
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct WidgetBackground: ViewModifier {
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .background(
                Theme.background.opacity(WidgetSettings.clampOpacity(opacity)),
                in: RoundedRectangle(cornerRadius: 12)
            )
    }
}

// MARK: - Array chunking helper

private extension Array {
    /// Splits the array into sub-arrays of at most `size` elements.
    func chunks(of size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
