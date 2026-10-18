import AppKit
import CoreGraphics
import Foundation
import SwiftUI

struct WaterEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let milliliters: Int

    init(id: UUID = UUID(), date: Date = Date(), milliliters: Int) {
        self.id = id
        self.date = date
        self.milliliters = milliliters
    }
}

@MainActor
final class WaterStore: ObservableObject {
    private enum Keys {
        static let entries = "waterWidget.entries.v1"
        static let dailyGoal = "waterWidget.dailyGoal.v1"
        static let quickAmount = "waterWidget.quickAmount.v1"
    }

    @Published private(set) var entries: [WaterEntry]
    @Published private(set) var currentDay: Date

    @Published var dailyGoal: Int {
        didSet {
            UserDefaults.standard.set(dailyGoal, forKey: Keys.dailyGoal)
        }
    }

    @Published var quickAmount: Int {
        didSet {
            UserDefaults.standard.set(quickAmount, forKey: Keys.quickAmount)
        }
    }

    private let calendar = Calendar.current

    init() {
        self.currentDay = Self.calendarStartOfToday()

        if let data = UserDefaults.standard.data(forKey: Keys.entries),
           let decoded = try? JSONDecoder().decode([WaterEntry].self, from: data) {
            self.entries = decoded.sorted { $0.date < $1.date }
        } else {
            self.entries = []
        }

        let storedGoal = UserDefaults.standard.object(forKey: Keys.dailyGoal) as? Int
        self.dailyGoal = storedGoal.map { Self.clamped($0, lowerBound: 500, upperBound: 6000) } ?? 2000

        let storedQuickAmount = UserDefaults.standard.object(forKey: Keys.quickAmount) as? Int
        self.quickAmount = storedQuickAmount.map { Self.clamped($0, lowerBound: 0, upperBound: 5000) } ?? 250
    }

    var todayEntries: [WaterEntry] {
        entries
            .filter { calendar.isDate($0.date, inSameDayAs: currentDay) }
            .sorted { $0.date < $1.date }
    }

    var todayTotal: Int {
        todayEntries.reduce(0) { $0 + $1.milliliters }
    }

    var progress: Double {
        guard dailyGoal > 0 else { return 0 }
        return min(Double(todayTotal) / Double(dailyGoal), 1)
    }

    var remaining: Int {
        max(dailyGoal - todayTotal, 0)
    }

    func add(amount: Int) {
        refreshDayIfNeeded()
        let normalized = Self.clamped(amount, lowerBound: 0, upperBound: 5000)
        guard normalized > 0 else { return }
        entries.append(WaterEntry(milliliters: normalized))
        entries.sort { $0.date < $1.date }
        saveEntries()
    }

    func setDailyGoal(_ value: Int) {
        dailyGoal = Self.clamped(value, lowerBound: 500, upperBound: 6000)
    }

    func setQuickAmount(_ value: Int) {
        quickAmount = Self.clamped(value, lowerBound: 0, upperBound: 5000)
    }

    func adjustQuickAmountByWheel(deltaY: CGFloat) {
        guard deltaY != 0 else { return }
        let direction = deltaY > 0 ? 1 : -1
        let increment = Self.nonlinearWheelIncrement(for: abs(deltaY))
        setQuickAmount(quickAmount + (direction * increment))
    }

    func delete(_ entry: WaterEntry) {
        entries.removeAll { $0.id == entry.id }
        saveEntries()
    }

    func update(_ entry: WaterEntry, milliliters: Int) {
        let normalized = Self.clamped(milliliters, lowerBound: 1, upperBound: 5000)
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = WaterEntry(id: entry.id, date: entry.date, milliliters: normalized)
        entries.sort { $0.date < $1.date }
        saveEntries()
    }

    func undoLatestTodayEntry() {
        guard let latest = todayEntries.last else { return }
        delete(latest)
    }

    func resetToday() {
        entries.removeAll { calendar.isDate($0.date, inSameDayAs: currentDay) }
        saveEntries()
    }

    func refreshDayIfNeeded() {
        let today = Self.calendarStartOfToday()
        if !calendar.isDate(today, inSameDayAs: currentDay) {
            currentDay = today
        }
    }

    private func saveEntries() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: Keys.entries)
    }

    private static func calendarStartOfToday() -> Date {
        Calendar.current.startOfDay(for: Date())
    }

    private static func clamped(_ value: Int, lowerBound: Int, upperBound: Int) -> Int {
        min(max(value, lowerBound), upperBound)
    }

    private static func nonlinearWheelIncrement(for magnitude: CGFloat) -> Int {
        let normalized = max(Double(magnitude), 1)
        let accelerated = Int((normalized * normalized / 6).rounded())
        return min(max(accelerated, 1), 100)
    }

    private func calendarStartOfToday() -> Date {
        Self.calendarStartOfToday()
    }
}

@MainActor
final class CupStore: ObservableObject {
    private enum Keys {
        static let capacity = "waterWidget.cup.capacity.v1"
        static let currentAmount = "waterWidget.cup.currentAmount.v1"
        static let baselineAmount = "waterWidget.cup.baselineAmount.v1"
        static let topWidth = "waterWidget.cup.topWidth.v1"
        static let middleWidth = "waterWidget.cup.middleWidth.v1"
        static let bottomWidth = "waterWidget.cup.bottomWidth.v1"
        static let curve = "waterWidget.cup.curve.v1"
        static let cupHeight = "waterWidget.cup.height.v1"
        static let bellyPosition = "waterWidget.cup.bellyPosition.v1"
        static let roundness = "waterWidget.cup.roundness.v1"
        static let fillLevel = "waterWidget.cup.fillLevel.v1"
        static let baselineFillLevel = "waterWidget.cup.baselineFillLevel.v1"
        static let recordMode = "waterWidget.cup.recordMode.v1"
        static let isSettingLevel = "waterWidget.cup.isSettingLevel.v1"
    }

    @Published private(set) var capacity: Int {
        didSet { UserDefaults.standard.set(capacity, forKey: Keys.capacity) }
    }

    @Published private(set) var fillLevel: Double {
        didSet { UserDefaults.standard.set(fillLevel, forKey: Keys.fillLevel) }
    }

    @Published private(set) var baselineFillLevel: Double {
        didSet { UserDefaults.standard.set(baselineFillLevel, forKey: Keys.baselineFillLevel) }
    }

    @Published var topWidth: Double {
        didSet {
            UserDefaults.standard.set(topWidth, forKey: Keys.topWidth)
        }
    }

    @Published var middleWidth: Double {
        didSet {
            UserDefaults.standard.set(middleWidth, forKey: Keys.middleWidth)
        }
    }

    @Published var bottomWidth: Double {
        didSet {
            UserDefaults.standard.set(bottomWidth, forKey: Keys.bottomWidth)
        }
    }

    @Published var curve: Double {
        didSet {
            UserDefaults.standard.set(curve, forKey: Keys.curve)
        }
    }

    @Published var cupHeight: Double {
        didSet {
            UserDefaults.standard.set(cupHeight, forKey: Keys.cupHeight)
        }
    }

    @Published var bellyPosition: Double {
        didSet {
            UserDefaults.standard.set(bellyPosition, forKey: Keys.bellyPosition)
        }
    }

    @Published var roundness: Double {
        didSet {
            UserDefaults.standard.set(roundness, forKey: Keys.roundness)
        }
    }

    @Published private(set) var recordMode: CupRecordMode {
        didSet { UserDefaults.standard.set(recordMode.rawValue, forKey: Keys.recordMode) }
    }

    @Published private(set) var isSettingLevel: Bool {
        didSet { UserDefaults.standard.set(isSettingLevel, forKey: Keys.isSettingLevel) }
    }

    init() {
        let defaults = UserDefaults.standard
        let storedCapacity = defaults.object(forKey: Keys.capacity) as? Int
        let capacity = storedCapacity.map { Self.clamped($0, lowerBound: 50, upperBound: 5000) } ?? 350
        self.capacity = capacity

        let topWidth = Self.double(for: Keys.topWidth, defaultValue: 0.72, lowerBound: 0.35, upperBound: 1.00)
        let middleWidth = Self.double(for: Keys.middleWidth, defaultValue: 0.62, lowerBound: 0.28, upperBound: 1.00)
        let bottomWidth = Self.double(for: Keys.bottomWidth, defaultValue: 0.50, lowerBound: 0.24, upperBound: 1.00)
        let curve = Self.double(for: Keys.curve, defaultValue: 0.05, lowerBound: -1.00, upperBound: 1.00)
        let cupHeight = Self.double(for: Keys.cupHeight, defaultValue: 0.92, lowerBound: 0.35, upperBound: 1.00)
        let bellyPosition = Self.double(for: Keys.bellyPosition, defaultValue: 0.52, lowerBound: 0.25, upperBound: 0.78)
        let roundness = Self.double(for: Keys.roundness, defaultValue: 0.35, lowerBound: 0.00, upperBound: 1.00)

        self.topWidth = topWidth
        self.middleWidth = middleWidth
        self.bottomWidth = bottomWidth
        self.curve = curve
        self.cupHeight = cupHeight
        self.bellyPosition = bellyPosition
        self.roundness = roundness

        let storedMode = defaults.string(forKey: Keys.recordMode).flatMap(CupRecordMode.init(rawValue:))
        self.recordMode = storedMode ?? .dropFromBaseline
        self.isSettingLevel = defaults.object(forKey: Keys.isSettingLevel) as? Bool ?? false

        let storedFillLevel = defaults.object(forKey: Keys.fillLevel) as? Double
        if let storedFillLevel {
            self.fillLevel = Self.clamped(storedFillLevel, lowerBound: 0, upperBound: 1)
        } else {
            let storedCurrent = defaults.object(forKey: Keys.currentAmount) as? Int
            let current = storedCurrent.map { Self.clamped($0, lowerBound: 0, upperBound: capacity) } ?? capacity
            self.fillLevel = Self.fillLevel(forVolume: current, capacity: capacity, shape: Self.shapeSnapshot(
                topWidth: topWidth,
                middleWidth: middleWidth,
                bottomWidth: bottomWidth,
                curve: curve,
                bellyPosition: bellyPosition,
                roundness: roundness
            ))
        }

        let storedBaselineFillLevel = defaults.object(forKey: Keys.baselineFillLevel) as? Double
        if let storedBaselineFillLevel {
            self.baselineFillLevel = Self.clamped(storedBaselineFillLevel, lowerBound: 0, upperBound: 1)
        } else {
            let storedBaseline = defaults.object(forKey: Keys.baselineAmount) as? Int
            let baseline = storedBaseline.map { Self.clamped($0, lowerBound: 0, upperBound: capacity) } ?? capacity
            self.baselineFillLevel = Self.fillLevel(forVolume: baseline, capacity: capacity, shape: Self.shapeSnapshot(
                topWidth: topWidth,
                middleWidth: middleWidth,
                bottomWidth: bottomWidth,
                curve: curve,
                bellyPosition: bellyPosition,
                roundness: roundness
            ))
        }
    }

    var fillFraction: Double {
        fillLevel
    }

    var currentAmount: Int {
        volumeMilliliters(at: fillLevel)
    }

    var baselineAmount: Int {
        volumeMilliliters(at: baselineFillLevel)
    }

    var pendingDrinkAmount: Int {
        switch recordMode {
        case .dropFromBaseline:
            guard !isSettingLevel else { return 0 }
            return max(baselineAmount - currentAmount, 0)
        case .directAmount:
            return currentAmount
        }
    }

    var calculationText: String {
        switch recordMode {
        case .dropFromBaseline:
            if isSettingLevel {
                return "设定中：滚轮只校准基准液面，不会记录。关闭开关后，以当前液面作为基准。"
            }
            return "计算：把杯身按高度分层，按旋转截面 πr² 积分；本次 = V(基准液面) - V(当前液面)。"
        case .directAmount:
            return "计算：同样按 πr² 分层积分；本次 = V(当前液面)，记录后液面清零。"
        }
    }

    func setCapacity(_ value: Int) {
        capacity = Self.clamped(value, lowerBound: 50, upperBound: 5000)
    }

    func setCurrentAmount(_ value: Int) {
        fillLevel = Self.fillLevel(forVolume: value, capacity: capacity, shape: currentShape)
    }

    func adjustLevelByWheel(deltaY: CGFloat) {
        guard deltaY != 0 else { return }
        let increment = Self.nonlinearWheelLevelIncrement(for: abs(deltaY))

        switch recordMode {
        case .dropFromBaseline:
            if isSettingLevel {
                let direction = deltaY > 0 ? 1.0 : -1.0
                setFillLevel(fillLevel + (direction * increment))
            } else {
                setFillLevel(fillLevel - increment)
            }
        case .directAmount:
            let direction = deltaY > 0 ? 1.0 : -1.0
            setFillLevel(fillLevel + (direction * increment))
        }
    }

    func refill() {
        fillLevel = 1
        baselineFillLevel = 1
    }

    func setRecordMode(_ mode: CupRecordMode) {
        recordMode = mode
        isSettingLevel = false
        if mode == .dropFromBaseline {
            baselineFillLevel = fillLevel
        }
    }

    func toggleSettingLevel() {
        guard recordMode == .dropFromBaseline else { return }
        isSettingLevel.toggle()
        if !isSettingLevel {
            baselineFillLevel = fillLevel
        }
    }

    func commitReading() {
        switch recordMode {
        case .dropFromBaseline:
            baselineFillLevel = fillLevel
        case .directAmount:
            fillLevel = 0
            baselineFillLevel = 0
        }
    }

    func applyPreset(_ preset: CupPreset) {
        switch preset {
        case .straight:
            topWidth = 0.74
            middleWidth = 0.74
            bottomWidth = 0.74
            cupHeight = 0.72
            bellyPosition = 0.50
            curve = 0.00
            roundness = 0.10
        case .wideGlass:
            topWidth = 0.96
            middleWidth = 0.92
            bottomWidth = 0.64
            cupHeight = 0.68
            bellyPosition = 0.44
            curve = 0.18
            roundness = 0.58
        case .bowl:
            topWidth = 0.98
            middleWidth = 0.88
            bottomWidth = 0.46
            cupHeight = 0.40
            bellyPosition = 0.36
            curve = 0.44
            roundness = 0.92
        }
    }

    private var currentShape: CupShapeSnapshot {
        Self.shapeSnapshot(
            topWidth: topWidth,
            middleWidth: middleWidth,
            bottomWidth: bottomWidth,
            curve: curve,
            bellyPosition: bellyPosition,
            roundness: roundness
        )
    }

    private func setFillLevel(_ value: Double) {
        fillLevel = Self.clamped(value, lowerBound: 0, upperBound: 1)
    }

    private func volumeMilliliters(at fillLevel: Double) -> Int {
        Int((Double(capacity) * CupShapeMath.volumeFraction(
            forFillLevel: fillLevel,
            topWidth: topWidth,
            middleWidth: middleWidth,
            bottomWidth: bottomWidth,
            curve: curve,
            bellyPosition: bellyPosition,
            roundness: roundness
        )).rounded())
    }

    private static func double(for key: String, defaultValue: Double, lowerBound: Double, upperBound: Double) -> Double {
        let value = UserDefaults.standard.object(forKey: key) as? Double ?? defaultValue
        return clamped(value, lowerBound: lowerBound, upperBound: upperBound)
    }

    private static func clamped(_ value: Int, lowerBound: Int, upperBound: Int) -> Int {
        min(max(value, lowerBound), upperBound)
    }

    private static func clamped(_ value: Double, lowerBound: Double, upperBound: Double) -> Double {
        min(max(value, lowerBound), upperBound)
    }

    private static func nonlinearWheelLevelIncrement(for magnitude: CGFloat) -> Double {
        let normalized = max(Double(magnitude), 1)
        let accelerated = normalized * normalized / 1600
        return min(max(accelerated, 0.004), 0.055)
    }

    private static func shapeSnapshot(
        topWidth: Double,
        middleWidth: Double,
        bottomWidth: Double,
        curve: Double,
        bellyPosition: Double,
        roundness: Double
    ) -> CupShapeSnapshot {
        CupShapeSnapshot(
            topWidth: topWidth,
            middleWidth: middleWidth,
            bottomWidth: bottomWidth,
            curve: curve,
            bellyPosition: bellyPosition,
            roundness: roundness
        )
    }

    private static func fillLevel(forVolume volume: Int, capacity: Int, shape: CupShapeSnapshot) -> Double {
        guard capacity > 0 else { return 0 }
        let target = Self.clamped(Double(volume) / Double(capacity), lowerBound: 0, upperBound: 1)
        var low = 0.0
        var high = 1.0

        for _ in 0..<24 {
            let mid = (low + high) / 2
            let fraction = CupShapeMath.volumeFraction(
                forFillLevel: mid,
                topWidth: shape.topWidth,
                middleWidth: shape.middleWidth,
                bottomWidth: shape.bottomWidth,
                curve: shape.curve,
                bellyPosition: shape.bellyPosition,
                roundness: shape.roundness
            )
            if fraction < target {
                low = mid
            } else {
                high = mid
            }
        }

        return (low + high) / 2
    }
}

enum CupPreset: String, CaseIterable, Identifiable {
    case straight
    case wideGlass
    case bowl

    var id: String { rawValue }

    var title: String {
        switch self {
        case .straight:
            return "直壁杯"
        case .wideGlass:
            return "宽口杯"
        case .bowl:
            return "矮圆杯"
        }
    }
}

enum CupRecordMode: String, CaseIterable, Identifiable {
    case dropFromBaseline
    case directAmount

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dropFromBaseline:
            return "液面下降"
        case .directAmount:
            return "直接水量"
        }
    }
}

struct CupShapeSnapshot {
    let topWidth: Double
    let middleWidth: Double
    let bottomWidth: Double
    let curve: Double
    let bellyPosition: Double
    let roundness: Double
}

enum WidgetLevelMode: String, CaseIterable, Identifiable {
    case desktop
    case floating

    var id: String { rawValue }

    var title: String {
        switch self {
        case .desktop:
            return "桌面"
        case .floating:
            return "置顶"
        }
    }
}

enum WidgetPanel: String, CaseIterable, Identifiable {
    case manual
    case cup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual:
            return "当前"
        case .cup:
            return "水杯"
        }
    }
}

@MainActor
final class WidgetPreferences: ObservableObject {
    private enum Keys {
        static let levelMode = "waterWidget.levelMode.v1"
    }

    var onLevelModeChange: ((WidgetLevelMode) -> Void)?

    @Published var levelMode: WidgetLevelMode {
        didSet {
            UserDefaults.standard.set(levelMode.rawValue, forKey: Keys.levelMode)
            onLevelModeChange?(levelMode)
        }
    }

    init() {
        let stored = UserDefaults.standard.string(forKey: Keys.levelMode)
        self.levelMode = stored.flatMap(WidgetLevelMode.init(rawValue:)) ?? .floating
    }
}

struct WaterWidgetView: View {
    @ObservedObject var store: WaterStore
    @ObservedObject var cupStore: CupStore
    @ObservedObject var preferences: WidgetPreferences

    @State private var isQuickAmountWheelActive = false
    @State private var selectedPanel: WidgetPanel = .manual

    let hideAction: () -> Void
    let quitAction: () -> Void
    let openHistoryAction: () -> Void
    let openCupSettingsAction: () -> Void

    private let quickAmounts = [50, 100, 250, 350, 500]
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 14) {
            header
            switch selectedPanel {
            case .manual:
                manualPanel
            case .cup:
                cupPanel
            }
        }
        .padding(16)
        .frame(width: 340, height: 520)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.22), radius: 18, x: 0, y: 12)
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            store.refreshDayIfNeeded()
        }
    }

    private var manualPanel: some View {
        VStack(spacing: 14) {
            WaterGauge(progress: store.progress, total: store.todayTotal, goal: store.dailyGoal, remaining: store.remaining)
            controls
            goalAndMode
            history
        }
    }

    private var cupPanel: some View {
        CupWidgetPanel(
            store: store,
            cupStore: cupStore,
            openHistoryAction: openHistoryAction,
            openSettingsAction: openCupSettingsAction
        )
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "drop.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.cyan)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.cyan.opacity(0.16)))

            VStack(alignment: .leading, spacing: 2) {
                Text(dateFormatter.string(from: store.currentDay))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("界面", selection: $selectedPanel) {
                ForEach(WidgetPanel.allCases) { panel in
                    Text(panel.title).tag(panel)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 96)
            .help("切换界面")

            Button(action: hideAction) {
                Image(systemName: "minus")
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)
            .background(Circle().fill(Color.primary.opacity(0.07)))
            .help("隐藏")

            Button(action: quitAction) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)
            .background(Circle().fill(Color.primary.opacity(0.07)))
            .help("退出")
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(quickAmounts, id: \.self) { amount in
                    Button {
                        store.add(amount: amount)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                            Text("\(amount)")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(FlatButtonStyle(tint: quickButtonTint(for: amount)))
                    .help("记录 \(amount) ml")
                }
            }

            HStack(spacing: 6) {
                Button {
                    store.setQuickAmount(store.quickAmount - 50)
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "minus")
                            .font(.system(size: 10, weight: .bold))
                        Text("50")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .frame(width: 40, height: 32)
                }
                .buttonStyle(AmountAdjustButtonStyle(accent: Color(red: 0.35, green: 0.70, blue: 0.96)))
                .help("减少 50 ml")

                Button {
                    isQuickAmountWheelActive = true
                } label: {
                    HStack(spacing: 4) {
                        Text("\(store.quickAmount)")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("ml")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 86, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isQuickAmountWheelActive ? Color.cyan.opacity(0.18) : Color.primary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isQuickAmountWheelActive ? Color.cyan.opacity(0.72) : Color.primary.opacity(0.12), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .help("点击后用滚轮调整")
                .background(
                    QuickAmountWheelMonitor(isActive: isQuickAmountWheelActive) { deltaY in
                        store.adjustQuickAmountByWheel(deltaY: deltaY)
                    }
                    .frame(width: 1, height: 1)
                )

                Button {
                    store.setQuickAmount(store.quickAmount + 50)
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text("50")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .frame(width: 40, height: 32)
                }
                .buttonStyle(AmountAdjustButtonStyle(accent: Color(red: 0.35, green: 0.70, blue: 0.96)))
                .help("增加 50 ml")

                Button {
                    store.add(amount: store.quickAmount)
                    isQuickAmountWheelActive = false
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(FlatButtonStyle(tint: Color(red: 0.10, green: 0.55, blue: 0.40)))
                .disabled(store.quickAmount == 0)
                .help("记录自定义水量")

                Button {
                    store.undoLatestTodayEntry()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .frame(width: 34, height: 32)
                }
                .buttonStyle(FlatButtonStyle(tint: Color(red: 0.72, green: 0.32, blue: 0.24)))
                .disabled(store.todayEntries.isEmpty)
                .help("撤销最近一次")
            }
        }
    }

    private var goalAndMode: some View {
        VStack(spacing: 10) {
            HStack {
                Label("目标", systemImage: "target")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Stepper(
                    value: Binding(
                        get: { store.dailyGoal },
                        set: { store.setDailyGoal($0) }
                    ),
                    in: 500...6000,
                    step: 100
                ) {
                    Text("\(store.dailyGoal) ml")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 82, alignment: .trailing)
                }
            }

            Picker("显示层级", selection: $preferences.levelMode) {
                ForEach(WidgetLevelMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .help("桌面模式会停在桌面图标上方、普通窗口下方；置顶模式会浮在普通窗口上方")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.055)))
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    openHistoryAction()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 12)
                        Label("记录", systemImage: "list.bullet")
                            .font(.system(size: 13, weight: .medium))
                        Text("\(store.todayEntries.count)")
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Spacer()
                Button {
                    store.resetToday()
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 28, height: 24)
                }
                .buttonStyle(.plain)
                .disabled(store.todayEntries.isEmpty)
                .help("清空今日记录")
            }

            collapsedHistorySummary
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var collapsedHistorySummary: some View {
        HStack(spacing: 10) {
            Image(systemName: store.todayEntries.isEmpty ? "tray" : "clock")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            if let latest = store.todayEntries.last {
                Text("\(HistoryRow.timeString(for: latest.date))  +\(latest.milliliters) ml")
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
            } else {
                Text("还没有记录")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(store.todayEntries.count) 条")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.11)))
    }

    private func quickButtonTint(for amount: Int) -> Color {
        switch amount {
        case 50:
            return Color(red: 0.32, green: 0.42, blue: 0.68)
        case 100:
            return Color(red: 0.17, green: 0.48, blue: 0.82)
        case 250:
            return Color(red: 0.00, green: 0.55, blue: 0.68)
        case 350:
            return Color(red: 0.28, green: 0.58, blue: 0.36)
        default:
            return Color(red: 0.75, green: 0.46, blue: 0.18)
        }
    }
}

struct CupWidgetPanel: View {
    @ObservedObject var store: WaterStore
    @ObservedObject var cupStore: CupStore

    @State private var isWheelActive = false

    let openHistoryAction: () -> Void
    let openSettingsAction: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            recordModePicker
            settingLevelToggle
            cupHeader
            cupPreview
            cupMetrics
            calculationNote
            cupActions
            Spacer(minLength: 0)
        }
        .onDisappear {
            isWheelActive = false
        }
    }

    private var recordModePicker: some View {
        Picker("记录模式", selection: Binding(
            get: { cupStore.recordMode },
            set: { cupStore.setRecordMode($0) }
        )) {
            ForEach(CupRecordMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .help("切换水杯记录模式")
    }

    private var settingLevelToggle: some View {
        Group {
            if cupStore.recordMode == .dropFromBaseline {
                Button {
                    cupStore.toggleSettingLevel()
                    isWheelActive = cupStore.isSettingLevel
                } label: {
                    HStack(spacing: 10) {
                        ZStack(alignment: cupStore.isSettingLevel ? .trailing : .leading) {
                            Capsule()
                                .fill(cupStore.isSettingLevel ? Color.cyan.opacity(0.72) : Color.secondary.opacity(0.24))
                                .frame(width: 42, height: 22)
                            Circle()
                                .fill(.white)
                                .frame(width: 18, height: 18)
                                .shadow(color: Color.black.opacity(0.18), radius: 2, x: 0, y: 1)
                                .padding(2)
                        }

                        Text(cupStore.isSettingLevel ? "设定液面：开" : "设定液面：关")
                            .font(.system(size: 13, weight: .semibold))

                        Spacer()

                        Text(cupStore.isSettingLevel ? "不可记录" : "可喝水")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(cupStore.isSettingLevel ? Color.cyan.opacity(0.13) : Color.primary.opacity(0.052))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(cupStore.isSettingLevel ? Color.cyan.opacity(0.55) : Color.primary.opacity(0.08), lineWidth: 1)
                )
                .help("开启后只校准基准液面；关闭时保存当前液面为基准")
            }
        }
    }

    private var cupHeader: some View {
        HStack(spacing: 8) {
            Button(action: openHistoryAction) {
                Label("记录", systemImage: "list.bullet")
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(OutlineActionButtonStyle(accent: Color(red: 0.11, green: 0.45, blue: 0.68)))
            .help("打开饮水记录")

            Button(action: openSettingsAction) {
                Image(systemName: "slider.horizontal.3")
                    .frame(width: 38, height: 32)
            }
            .buttonStyle(OutlineActionButtonStyle(accent: Color(red: 0.42, green: 0.36, blue: 0.66)))
            .help("设计水杯")
        }
    }

    private var cupPreview: some View {
        Button {
            isWheelActive = true
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.045))

                CupGraphic(cupStore: cupStore, isActive: isWheelActive)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 24)

                VStack {
                    HStack {
                        Image(systemName: isWheelActive ? "scroll.fill" : "scroll")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isWheelActive ? Color.cyan : .secondary)
                        Spacer()
                        Text("\(cupStore.currentAmount) ml")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                }
                .padding(10)
            }
            .frame(height: 166)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isWheelActive ? Color.cyan.opacity(0.72) : Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("点击后用滚轮调整杯中水量")
        .background(
            QuickAmountWheelMonitor(isActive: isWheelActive) { deltaY in
                cupStore.adjustLevelByWheel(deltaY: deltaY)
            }
            .frame(width: 1, height: 1)
        )
    }

    private var cupMetrics: some View {
        HStack(spacing: 8) {
            CompactMetric(title: cupStore.recordMode == .dropFromBaseline ? "基准" : "容量", value: "\(cupStore.recordMode == .dropFromBaseline ? cupStore.baselineAmount : cupStore.capacity)", unit: "ml")
            CompactMetric(title: "杯中", value: "\(cupStore.currentAmount)", unit: "ml")
            CompactMetric(title: "本次", value: "\(cupStore.pendingDrinkAmount)", unit: "ml")
        }
    }

    private var calculationNote: some View {
        Text(cupStore.calculationText)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.04)))
    }

    private var cupActions: some View {
        HStack(spacing: 8) {
            Button {
                cupStore.refill()
                isWheelActive = false
            } label: {
                Label("满杯", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(FlatButtonStyle(tint: Color(red: 0.16, green: 0.48, blue: 0.72)))

            Button {
                store.add(amount: cupStore.pendingDrinkAmount)
                cupStore.commitReading()
                isWheelActive = false
            } label: {
                Label("记录", systemImage: "checkmark")
                    .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(FlatButtonStyle(tint: Color(red: 0.10, green: 0.55, blue: 0.40)))
            .disabled(cupStore.pendingDrinkAmount == 0 || cupStore.isSettingLevel)
        }
    }
}

struct CompactMetric: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(unit)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.055)))
    }
}

struct CupGraphic: View {
    @ObservedObject var cupStore: CupStore
    let isActive: Bool

    var body: some View {
        GeometryReader { proxy in
            let designAspect: CGFloat = 260 / 340
            let canvasHeight = min(proxy.size.height, proxy.size.width / designAspect)
            let canvasWidth = canvasHeight * designAspect
            let canvasRect = CGRect(
                x: (proxy.size.width - canvasWidth) / 2,
                y: (proxy.size.height - canvasHeight) / 2,
                width: canvasWidth,
                height: canvasHeight
            )
            let drawingWidth = canvasRect.width * 0.82
            let drawingHeight = (canvasRect.height - 12) * CGFloat(cupStore.cupHeight)
            let cupRect = CGRect(
                x: canvasRect.midX - drawingWidth / 2,
                y: canvasRect.maxY - drawingHeight - 6,
                width: drawingWidth,
                height: drawingHeight
            )

            ZStack {
                CupSilhouette(
                    topWidth: cupStore.topWidth,
                    middleWidth: cupStore.middleWidth,
                    bottomWidth: cupStore.bottomWidth,
                    curve: cupStore.curve,
                    bellyPosition: cupStore.bellyPosition,
                    roundness: cupStore.roundness
                )
                .fill(Color.white.opacity(0.12))
                .frame(width: cupRect.width, height: cupRect.height)
                .position(x: cupRect.midX, y: cupRect.midY)

                CupWaterShape(
                    fillFraction: cupStore.fillFraction,
                    topWidth: cupStore.topWidth,
                    middleWidth: cupStore.middleWidth,
                    bottomWidth: cupStore.bottomWidth,
                    curve: cupStore.curve,
                    bellyPosition: cupStore.bellyPosition,
                    roundness: cupStore.roundness
                )
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.48, green: 0.86, blue: 1.00),
                            Color(red: 0.14, green: 0.56, blue: 0.88)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: cupRect.width, height: cupRect.height)
                .position(x: cupRect.midX, y: cupRect.midY)

                CupSilhouette(
                    topWidth: cupStore.topWidth,
                    middleWidth: cupStore.middleWidth,
                    bottomWidth: cupStore.bottomWidth,
                    curve: cupStore.curve,
                    bellyPosition: cupStore.bellyPosition,
                    roundness: cupStore.roundness
                )
                .stroke(isActive ? Color.cyan.opacity(0.78) : Color.primary.opacity(0.28), lineWidth: 2)
                .frame(width: cupRect.width, height: cupRect.height)
                .position(x: cupRect.midX, y: cupRect.midY)
            }
        }
    }
}

struct CupSilhouette: Shape {
    let topWidth: Double
    let middleWidth: Double
    let bottomWidth: Double
    let curve: Double
    let bellyPosition: Double
    let roundness: Double

    func path(in rect: CGRect) -> Path {
        let points = CupShapeMath.edgePoints(
            in: rect,
            topWidth: topWidth,
            middleWidth: middleWidth,
            bottomWidth: bottomWidth,
            curve: curve,
            bellyPosition: bellyPosition,
            roundness: roundness
        )
        guard let firstLeft = points.left.first,
              let lastRight = points.right.last else {
            return Path()
        }

        var path = Path()
        path.move(to: firstLeft)
        for point in points.left.dropFirst() {
            path.addLine(to: point)
        }
        path.addQuadCurve(
            to: lastRight,
            control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.05 * CGFloat(roundness))
        )
        for point in points.right.dropLast().reversed() {
            path.addLine(to: point)
        }
        path.addLine(to: firstLeft)
        path.closeSubpath()
        return path
    }
}

struct CupWaterShape: Shape {
    let fillFraction: Double
    let topWidth: Double
    let middleWidth: Double
    let bottomWidth: Double
    let curve: Double
    let bellyPosition: Double
    let roundness: Double

    func path(in rect: CGRect) -> Path {
        let fill = min(max(CGFloat(fillFraction), 0), 1)
        guard fill > 0 else { return Path() }

        let startT = 1 - fill
        let steps = 54
        let leftStart = CupShapeMath.edgePoint(
            in: rect,
            t: startT,
            isLeft: true,
            topWidth: topWidth,
            middleWidth: middleWidth,
            bottomWidth: bottomWidth,
            curve: curve,
            bellyPosition: bellyPosition,
            roundness: roundness
        )
        let rightStart = CupShapeMath.edgePoint(
            in: rect,
            t: startT,
            isLeft: false,
            topWidth: topWidth,
            middleWidth: middleWidth,
            bottomWidth: bottomWidth,
            curve: curve,
            bellyPosition: bellyPosition,
            roundness: roundness
        )

        var path = Path()
        path.move(to: leftStart)
        path.addLine(to: rightStart)

        for index in 1...steps {
            let t = startT + (1 - startT) * CGFloat(index) / CGFloat(steps)
            path.addLine(
                to: CupShapeMath.edgePoint(
                    in: rect,
                    t: t,
                    isLeft: false,
                    topWidth: topWidth,
                    middleWidth: middleWidth,
                    bottomWidth: bottomWidth,
                    curve: curve,
                    bellyPosition: bellyPosition,
                    roundness: roundness
                )
            )
        }

        path.addQuadCurve(
            to: CupShapeMath.edgePoint(
                in: rect,
                t: 1,
                isLeft: true,
                topWidth: topWidth,
                middleWidth: middleWidth,
                bottomWidth: bottomWidth,
                curve: curve,
                bellyPosition: bellyPosition,
                roundness: roundness
            ),
            control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.05 * CGFloat(roundness))
        )

        for index in stride(from: steps - 1, through: 0, by: -1) {
            let t = startT + (1 - startT) * CGFloat(index) / CGFloat(steps)
            path.addLine(
                to: CupShapeMath.edgePoint(
                    in: rect,
                    t: t,
                    isLeft: true,
                    topWidth: topWidth,
                    middleWidth: middleWidth,
                    bottomWidth: bottomWidth,
                    curve: curve,
                    bellyPosition: bellyPosition,
                    roundness: roundness
                )
            )
        }

        path.closeSubpath()
        return path
    }
}

enum CupShapeMath {
    static func edgePoints(
        in rect: CGRect,
        topWidth: Double,
        middleWidth: Double,
        bottomWidth: Double,
        curve: Double,
        bellyPosition: Double,
        roundness: Double
    ) -> (left: [CGPoint], right: [CGPoint]) {
        let steps = 64
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        left.reserveCapacity(steps + 1)
        right.reserveCapacity(steps + 1)

        for index in 0...steps {
            let t = CGFloat(index) / CGFloat(steps)
            left.append(edgePoint(
                in: rect,
                t: t,
                isLeft: true,
                topWidth: topWidth,
                middleWidth: middleWidth,
                bottomWidth: bottomWidth,
                curve: curve,
                bellyPosition: bellyPosition,
                roundness: roundness
            ))
            right.append(edgePoint(
                in: rect,
                t: t,
                isLeft: false,
                topWidth: topWidth,
                middleWidth: middleWidth,
                bottomWidth: bottomWidth,
                curve: curve,
                bellyPosition: bellyPosition,
                roundness: roundness
            ))
        }

        return (left, right)
    }

    static func edgePoint(
        in rect: CGRect,
        t: CGFloat,
        isLeft: Bool,
        topWidth: Double,
        middleWidth: Double,
        bottomWidth: Double,
        curve: Double,
        bellyPosition: Double,
        roundness: Double
    ) -> CGPoint {
        let halfWidth = halfWidth(
            in: rect,
            t: t,
            topWidth: topWidth,
            middleWidth: middleWidth,
            bottomWidth: bottomWidth,
            curve: curve,
            bellyPosition: bellyPosition,
            roundness: roundness
        )
        let x = isLeft ? rect.midX - halfWidth : rect.midX + halfWidth
        return CGPoint(x: x, y: rect.minY + rect.height * t)
    }

    static func volumeFraction(
        forFillLevel fillLevel: Double,
        topWidth: Double,
        middleWidth: Double,
        bottomWidth: Double,
        curve: Double,
        bellyPosition: Double,
        roundness: Double
    ) -> Double {
        let fill = min(max(CGFloat(fillLevel), 0), 1)
        guard fill > 0 else { return 0 }
        guard fill < 1 else { return 1 }

        let rect = CGRect(x: 0, y: 0, width: 1, height: 1)
        let total = integratedRadiusSquared(
            in: rect,
            from: 0,
            to: 1,
            topWidth: topWidth,
            middleWidth: middleWidth,
            bottomWidth: bottomWidth,
            curve: curve,
            bellyPosition: bellyPosition,
            roundness: roundness
        )
        let filled = integratedRadiusSquared(
            in: rect,
            from: 1 - fill,
            to: 1,
            topWidth: topWidth,
            middleWidth: middleWidth,
            bottomWidth: bottomWidth,
            curve: curve,
            bellyPosition: bellyPosition,
            roundness: roundness
        )

        guard total > 0 else { return Double(fill) }
        return min(max(Double(filled / total), 0), 1)
    }

    private static func integratedRadiusSquared(
        in rect: CGRect,
        from start: CGFloat,
        to end: CGFloat,
        topWidth: Double,
        middleWidth: Double,
        bottomWidth: Double,
        curve: Double,
        bellyPosition: Double,
        roundness: Double
    ) -> CGFloat {
        let steps = 180
        let lower = min(max(start, 0), 1)
        let upper = min(max(end, 0), 1)
        guard upper > lower else { return 0 }

        var total: CGFloat = 0
        var previousT = lower
        var previousRadius = halfWidth(
            in: rect,
            t: previousT,
            topWidth: topWidth,
            middleWidth: middleWidth,
            bottomWidth: bottomWidth,
            curve: curve,
            bellyPosition: bellyPosition,
            roundness: roundness
        )

        for index in 1...steps {
            let t = lower + (upper - lower) * CGFloat(index) / CGFloat(steps)
            let radius = halfWidth(
                in: rect,
                t: t,
                topWidth: topWidth,
                middleWidth: middleWidth,
                bottomWidth: bottomWidth,
                curve: curve,
                bellyPosition: bellyPosition,
                roundness: roundness
            )
            let delta = t - previousT
            total += ((previousRadius * previousRadius) + (radius * radius)) * 0.5 * delta
            previousT = t
            previousRadius = radius
        }

        return total
    }

    private static func halfWidth(
        in rect: CGRect,
        t: CGFloat,
        topWidth: Double,
        middleWidth: Double,
        bottomWidth: Double,
        curve: Double,
        bellyPosition: Double,
        roundness: Double
    ) -> CGFloat {
        let belly = min(max(CGFloat(bellyPosition), 0.22), 0.82)
        let top = min(max(CGFloat(topWidth), 0.20), 1.00)
        let middle = min(max(CGFloat(middleWidth), 0.20), 1.00)
        let bottom = min(max(CGFloat(bottomWidth), 0.18), 1.00)
        let rounded = min(max(CGFloat(roundness), 0), 1)

        let rawProgress: CGFloat
        let start: CGFloat
        let end: CGFloat

        if t <= belly {
            rawProgress = belly == 0 ? 1 : t / belly
            start = top
            end = middle
        } else {
            rawProgress = (t - belly) / max(1 - belly, 0.001)
            start = middle
            end = bottom
        }

        let progress = blendedProgress(rawProgress, roundness: rounded)
        let base = start + (end - start) * progress
        let bulge = sin(.pi * t) * CGFloat(curve) * 0.10
        let multiplier = min(max(base + bulge, 0.16), 0.96)
        return min(rect.width * multiplier / 2, rect.width * 0.48)
    }

    private static func blendedProgress(_ value: CGFloat, roundness: CGFloat) -> CGFloat {
        let x = min(max(value, 0), 1)
        let smooth = x * x * (3 - 2 * x)
        let smoother = x * x * x * (x * (x * 6 - 15) + 10)
        let rounded = smooth * (1 - roundness) + smoother * roundness
        return x * (1 - roundness * 0.35) + rounded * (roundness * 0.35)
    }
}

struct CupSettingsView: View {
    @ObservedObject var cupStore: CupStore

    let closeAction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                preview
                Divider()
                controls
            }
        }
        .frame(minWidth: 640, idealWidth: 700, minHeight: 560, idealHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color(red: 0.11, green: 0.54, blue: 0.74))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.cyan.opacity(0.14)))

            VStack(alignment: .leading, spacing: 2) {
                Text("水杯设定")
                    .font(.system(size: 18, weight: .semibold))
                Text("\(cupStore.capacity) ml")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            Button(action: closeAction) {
                Image(systemName: "xmark")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .background(Circle().fill(Color.primary.opacity(0.07)))
            .help("关闭")
        }
        .padding(16)
    }

    private var preview: some View {
        VStack(spacing: 16) {
            CupGraphic(cupStore: cupStore, isActive: true)
                .frame(width: 260, height: 340)
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.045)))

            Button {
                cupStore.refill()
            } label: {
                Label("设为满杯", systemImage: "arrow.clockwise")
                    .frame(width: 160, height: 34)
            }
            .buttonStyle(FlatButtonStyle(tint: Color(red: 0.16, green: 0.48, blue: 0.72)))
        }
        .frame(width: 320)
        .frame(maxHeight: .infinity)
        .padding(18)
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Stepper(
                    value: Binding(
                        get: { cupStore.capacity },
                        set: { cupStore.setCapacity($0) }
                    ),
                    in: 50...5000,
                    step: 10
                ) {
                    HStack {
                        Label("容量", systemImage: "gauge.with.dots.needle.33percent")
                        Spacer()
                        Text("\(cupStore.capacity) ml")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("杯型预设")
                        .font(.system(size: 13, weight: .medium))

                    HStack(spacing: 8) {
                        ForEach(CupPreset.allCases) { preset in
                            Button {
                                cupStore.applyPreset(preset)
                            } label: {
                                Text(preset.title)
                                    .frame(maxWidth: .infinity, minHeight: 32)
                            }
                            .buttonStyle(OutlineActionButtonStyle(accent: Color(red: 0.11, green: 0.45, blue: 0.68)))
                        }
                    }
                }

                ShapeSlider(title: "杯口宽度", value: $cupStore.topWidth, range: 0.35...1.00)
                ShapeSlider(title: "杯身宽度", value: $cupStore.middleWidth, range: 0.28...1.00)
                ShapeSlider(title: "杯底宽度", value: $cupStore.bottomWidth, range: 0.24...1.00)
                ShapeSlider(title: "水杯高度", value: $cupStore.cupHeight, range: 0.35...1.00)
                ShapeSlider(title: "杯肚位置", value: $cupStore.bellyPosition, range: 0.25...0.78)
                ShapeSlider(title: "侧壁弧度", value: $cupStore.curve, range: -1.00...1.00)
                ShapeSlider(title: "圆润程度", value: $cupStore.roundness, range: 0.00...1.00)
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ShapeSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text(value, format: .number.precision(.fractionLength(2)))
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Slider(value: $value, in: range)
        }
    }
}

struct WaterGauge: View {
    let progress: Double
    let total: Int
    let goal: Int
    let remaining: Int

    var body: some View {
        HStack(spacing: 16) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.white.opacity(0.16))
                    )

                GeometryReader { proxy in
                    let fillHeight = proxy.size.height * progress
                    VStack {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 19, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.10, green: 0.68, blue: 0.88),
                                        Color(red: 0.12, green: 0.45, blue: 0.82)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: max(fillHeight, progress > 0 ? 8 : 0))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(5)

                Image(systemName: "drop")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .padding(.bottom, 24)
            }
            .frame(width: 96, height: 150)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(total) ml")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("目标 \(goal) ml")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: progress)
                    .tint(Color(red: 0.10, green: 0.60, blue: 0.78))

                Text(remaining == 0 ? "已完成今日目标" : "还差 \(remaining) ml")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(remaining == 0 ? Color(red: 0.10, green: 0.50, blue: 0.32) : .secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.052)))
    }
}

struct HistoryRow: View {
    let entry: WaterEntry
    let deleteAction: () -> Void

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func timeString(for date: Date) -> String {
        timeFormatter.string(from: date)
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(Self.timeFormatter.string(from: entry.date))
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .leading)

            Text("+\(entry.milliliters) ml")
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()

            Spacer()

            Button(action: deleteAction) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("删除这条记录")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.13)))
    }
}

struct HistoryManagerView: View {
    @ObservedObject var store: WaterStore

    let closeAction: () -> Void

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            summary
            Divider()
            content
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 560, idealHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            store.refreshDayIfNeeded()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color(red: 0.11, green: 0.54, blue: 0.74))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.cyan.opacity(0.14)))

            VStack(alignment: .leading, spacing: 2) {
                Text("饮水记录")
                    .font(.system(size: 18, weight: .semibold))
                Text(dateFormatter.string(from: store.currentDay))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                closeAction()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .background(Circle().fill(Color.primary.opacity(0.07)))
            .help("关闭")
        }
        .padding(16)
    }

    private var summary: some View {
        HStack(spacing: 12) {
            HistoryMetric(title: "今日总量", value: "\(store.todayTotal)", unit: "ml")
            HistoryMetric(title: "目标", value: "\(store.dailyGoal)", unit: "ml")
            HistoryMetric(title: "记录数", value: "\(store.todayEntries.count)", unit: "条")

            Button {
                store.resetToday()
            } label: {
                Label("清空", systemImage: "trash")
                    .frame(width: 72, height: 36)
            }
            .buttonStyle(OutlineActionButtonStyle(accent: Color(red: 0.74, green: 0.23, blue: 0.18)))
            .disabled(store.todayEntries.isEmpty)
            .help("清空今日记录")
        }
        .padding(16)
    }

    private var content: some View {
        Group {
            if store.todayEntries.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                    Text("还没有记录")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.todayEntries.reversed()) { entry in
                            EditableHistoryRow(entry: entry) { value in
                                store.update(entry, milliliters: value)
                            } deleteAction: {
                                store.delete(entry)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
    }
}

struct HistoryMetric: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(unit)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.055)))
    }
}

struct EditableHistoryRow: View {
    let entry: WaterEntry
    let updateAction: (Int) -> Void
    let deleteAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(HistoryRow.timeString(for: entry.date))
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                Text("单次饮水")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 76, alignment: .leading)

            Button {
                updateAction(entry.milliliters - 50)
            } label: {
                Label("50", systemImage: "minus")
                    .labelStyle(.titleAndIcon)
                    .frame(width: 56, height: 32)
            }
            .buttonStyle(AmountAdjustButtonStyle(accent: Color(red: 0.35, green: 0.70, blue: 0.96)))

            Stepper(
                value: Binding(
                    get: { entry.milliliters },
                    set: { updateAction($0) }
                ),
                in: 1...5000,
                step: 1
            ) {
                Text("\(entry.milliliters) ml")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .frame(width: 96, alignment: .center)
            }

            Button {
                updateAction(entry.milliliters + 50)
            } label: {
                Label("50", systemImage: "plus")
                    .labelStyle(.titleAndIcon)
                    .frame(width: 56, height: 32)
            }
            .buttonStyle(AmountAdjustButtonStyle(accent: Color(red: 0.35, green: 0.70, blue: 0.96)))

            Spacer()

            Button(action: deleteAction) {
                Image(systemName: "trash")
                    .frame(width: 34, height: 32)
            }
            .buttonStyle(OutlineActionButtonStyle(accent: Color(red: 0.74, green: 0.23, blue: 0.18)))
            .help("删除这条记录")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.045)))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

struct FlatButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.76 : 0.94))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct AmountAdjustButtonStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(configuration.isPressed ? 0.78 : 0.96),
                                Color(red: 0.12, green: 0.42, blue: 0.76).opacity(configuration.isPressed ? 0.86 : 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(configuration.isPressed ? 0.20 : 0.28), lineWidth: 1)
            )
            .shadow(color: accent.opacity(configuration.isPressed ? 0.16 : 0.30), radius: 4, x: 0, y: 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct OutlineActionButtonStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(accent)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accent.opacity(configuration.isPressed ? 0.14 : 0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(accent.opacity(0.42), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct QuickAmountWheelMonitor: NSViewRepresentable {
    let isActive: Bool
    let onScroll: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.update(isActive: isActive, onScroll: onScroll)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(isActive: isActive, onScroll: onScroll)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        private var monitor: Any?
        private var isActive = false
        private var onScroll: (CGFloat) -> Void = { _ in }

        deinit {
            stop()
        }

        func update(isActive: Bool, onScroll: @escaping (CGFloat) -> Void) {
            self.isActive = isActive
            self.onScroll = onScroll

            if isActive {
                start()
            } else {
                stop()
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func start() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, self.isActive else { return event }
                let deltaY = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.scrollingDeltaX
                guard deltaY != 0 else { return event }
                self.onScroll(deltaY)
                return nil
            }
        }
    }
}

final class WidgetWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: WidgetWindow?
    private var historyWindow: WidgetWindow?
    private var cupSettingsWindow: WidgetWindow?
    private var statusItem: NSStatusItem?
    private let store = WaterStore()
    private let cupStore = CupStore()
    private let preferences = WidgetPreferences()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        preferences.onLevelModeChange = { [weak self] mode in
            self?.applyWindowLevel(mode)
            self?.refreshStatusMenu()
        }

        makeWindow()
        makeStatusItem()
        applyWindowLevel(preferences.levelMode)
    }

    private func makeWindow() {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: 340, height: 520)
        let origin = NSPoint(
            x: screenFrame.maxX - size.width - 28,
            y: screenFrame.maxY - size.height - 48
        )

        let window = WidgetWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        let view = WaterWidgetView(
            store: store,
            cupStore: cupStore,
            preferences: preferences,
            hideAction: { [weak self] in self?.window?.orderOut(nil) },
            quitAction: { NSApplication.shared.terminate(nil) },
            openHistoryAction: { [weak self] in self?.showHistoryWindow() },
            openCupSettingsAction: { [weak self] in self?.showCupSettingsWindow() }
        )

        window.contentView = DraggableHostingView(rootView: view)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.setFrameAutosaveName("WaterWidgetWindowFrame")
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    private func makeHistoryWindow() -> WidgetWindow {
        let window = WidgetWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        let view = HistoryManagerView(
            store: store,
            closeAction: { [weak self] in self?.historyWindow?.orderOut(nil) }
        )

        window.contentView = NSHostingView(rootView: view)
        window.title = "饮水记录"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.setFrameAutosaveName("WaterWidgetHistoryWindowFrame")
        window.center()
        return window
    }

    private func makeCupSettingsWindow() -> WidgetWindow {
        let window = WidgetWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 620),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        let view = CupSettingsView(
            cupStore: cupStore,
            closeAction: { [weak self] in self?.cupSettingsWindow?.orderOut(nil) }
        )

        window.contentView = NSHostingView(rootView: view)
        window.title = "水杯设定"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.setFrameAutosaveName("WaterWidgetCupSettingsWindowFrame")
        window.center()
        return window
    }

    private func makeStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "drop.fill", accessibilityDescription: "喝水小组件")
        item.button?.imagePosition = .imageOnly
        statusItem = item
        refreshStatusMenu()
    }

    private func refreshStatusMenu() {
        let menu = NSMenu()

        let showItem = NSMenuItem(title: "显示小组件", action: #selector(showWidget), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        let historyItem = NSMenuItem(title: "打开记录", action: #selector(openHistory), keyEquivalent: "")
        historyItem.target = self
        menu.addItem(historyItem)

        let cupSettingsItem = NSMenuItem(title: "水杯设定", action: #selector(openCupSettings), keyEquivalent: "")
        cupSettingsItem.target = self
        menu.addItem(cupSettingsItem)

        let levelItem = NSMenuItem(
            title: preferences.levelMode == .floating ? "切换到桌面模式" : "切换到置顶模式",
            action: #selector(toggleLevelMode),
            keyEquivalent: ""
        )
        levelItem.target = self
        menu.addItem(levelItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    private func applyWindowLevel(_ mode: WidgetLevelMode) {
        guard let window else { return }
        switch mode {
        case .desktop:
            let desktopIconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
            window.level = NSWindow.Level(rawValue: desktopIconLevel + 1)
        case .floating:
            window.level = .floating
        }
        window.orderFrontRegardless()
    }

    @objc private func showWidget() {
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func showHistoryWindow() {
        if historyWindow == nil {
            historyWindow = makeHistoryWindow()
        }

        historyWindow?.orderFrontRegardless()
        historyWindow?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc private func openHistory() {
        showHistoryWindow()
    }

    private func showCupSettingsWindow() {
        if cupSettingsWindow == nil {
            cupSettingsWindow = makeCupSettingsWindow()
        }

        cupSettingsWindow?.orderFrontRegardless()
        cupSettingsWindow?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc private func openCupSettings() {
        showCupSettingsWindow()
    }

    @objc private func toggleLevelMode() {
        preferences.levelMode = preferences.levelMode == .floating ? .desktop : .floating
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

@main
@MainActor
enum WaterWidgetMain {
    private static let appDelegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = appDelegate
        app.run()
    }
}
