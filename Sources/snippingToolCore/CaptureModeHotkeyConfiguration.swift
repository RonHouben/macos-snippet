import Foundation

public struct HotkeyModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt8

    public static let command = HotkeyModifiers(rawValue: 1 << 0)
    public static let shift = HotkeyModifiers(rawValue: 1 << 1)
    public static let option = HotkeyModifiers(rawValue: 1 << 2)
    public static let control = HotkeyModifiers(rawValue: 1 << 3)

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public var displayText: String {
        var pieces: [String] = []

        if contains(.control) {
            pieces.append("⌃")
        }
        if contains(.option) {
            pieces.append("⌥")
        }
        if contains(.shift) {
            pieces.append("⇧")
        }
        if contains(.command) {
            pieces.append("⌘")
        }

        return pieces.joined()
    }

    public var title: String {
        var pieces: [String] = []

        if contains(.control) {
            pieces.append("Control")
        }
        if contains(.option) {
            pieces.append("Option")
        }
        if contains(.shift) {
            pieces.append("Shift")
        }
        if contains(.command) {
            pieces.append("Command")
        }

        return pieces.isEmpty ? "No modifier" : pieces.joined(separator: " + ")
    }

    public var modifierCount: Int {
        rawValue.nonzeroBitCount
    }
}

public enum HotkeyKey: String, CaseIterable, Codable, Identifiable, Sendable {
    case zero
    case one
    case two
    case three
    case four
    case five
    case six
    case seven
    case eight
    case nine
    case a
    case b
    case c
    case d
    case e
    case f
    case g
    case h
    case i
    case j
    case k
    case l
    case m
    case n
    case o
    case p
    case q
    case r
    case s
    case t
    case u
    case v
    case w
    case x
    case y
    case z

    public var id: String { rawValue }

    public init?(keyCode: UInt16) {
        guard let key = Self.keyByKeyCode[keyCode] else {
            return nil
        }

        self = key
    }

    public var title: String {
        switch self {
        case .zero: "0"
        case .one: "1"
        case .two: "2"
        case .three: "3"
        case .four: "4"
        case .five: "5"
        case .six: "6"
        case .seven: "7"
        case .eight: "8"
        case .nine: "9"
        default: rawValue.uppercased()
        }
    }

    public var keyCode: UInt16 {
        guard let keyCode = Self.keyCodes[self] else {
            preconditionFailure("Missing key code mapping for \(self.rawValue)")
        }

        return keyCode
    }

    private static let keyCodes: [HotkeyKey: UInt16] = [
        .a: 0, .s: 1, .d: 2, .f: 3, .h: 4, .g: 5, .z: 6, .x: 7, .c: 8, .v: 9,
        .b: 11, .q: 12, .w: 13, .e: 14, .r: 15, .y: 16, .t: 17, .one: 18,
        .two: 19, .three: 20, .four: 21, .six: 22, .five: 23, .nine: 25,
        .seven: 26, .eight: 28, .zero: 29, .o: 31, .u: 32, .i: 34, .p: 35,
        .l: 37, .j: 38, .k: 40, .n: 45, .m: 46
    ]

    private static let keyByKeyCode = Dictionary(uniqueKeysWithValues: keyCodes.map { ($0.value, $0.key) })
}

public struct HotkeyShortcut: Codable, Equatable, Hashable, Sendable {
    public var key: HotkeyKey
    public var modifiers: HotkeyModifiers

    public init(key: HotkeyKey, modifiers: HotkeyModifiers) {
        self.key = key
        self.modifiers = modifiers
    }

    public var displayText: String {
        modifiers.displayText + key.title
    }

    public var isValid: Bool {
        modifiers.isEmpty == false
    }

    public static func recommended(for mode: CaptureMode) -> HotkeyShortcut {
        switch mode {
        case .rectangular:
            HotkeyShortcut(key: .four, modifiers: [.command, .shift])
        case .fullScreen:
            HotkeyShortcut(key: .six, modifiers: [.command, .shift])
        case .window:
            HotkeyShortcut(key: .seven, modifiers: [.command, .shift])
        }
    }
}

public struct HotkeyConflict: Equatable, Sendable {
    public var shortcut: HotkeyShortcut
    public var modes: [CaptureMode]

    public init(shortcut: HotkeyShortcut, modes: [CaptureMode]) {
        self.shortcut = shortcut
        self.modes = modes
    }

    public var message: String {
        let modeList = modes.map(\.title).joined(separator: ", ")
        return "\(shortcut.displayText) is assigned to multiple modes: \(modeList)."
    }
}

public struct CaptureModeHotkeyConfiguration: Codable, Equatable, Sendable {
    public var rectangular: HotkeyShortcut?
    public var fullScreen: HotkeyShortcut?
    public var window: HotkeyShortcut?

    public init(
        rectangular: HotkeyShortcut? = nil,
        fullScreen: HotkeyShortcut? = nil,
        window: HotkeyShortcut? = nil
    ) {
        self.rectangular = rectangular
        self.fullScreen = fullScreen
        self.window = window
    }

    public static let `default` = CaptureModeHotkeyConfiguration()

    public subscript(mode: CaptureMode) -> HotkeyShortcut? {
        get {
            switch mode {
            case .rectangular:
                rectangular
            case .fullScreen:
                fullScreen
            case .window:
                window
            }
        }
        set {
            switch mode {
            case .rectangular:
                rectangular = newValue
            case .fullScreen:
                fullScreen = newValue
            case .window:
                window = newValue
            }
        }
    }

    public var activeBindings: [(mode: CaptureMode, shortcut: HotkeyShortcut)] {
        CaptureMode.allCases.compactMap { mode in
            guard let shortcut = self[mode] else {
                return nil
            }

            return (mode, shortcut)
        }
    }

    public var conflicts: [HotkeyConflict] {
        let grouped = Dictionary(grouping: activeBindings, by: \.shortcut)

        return grouped
            .filter { $0.value.count > 1 }
            .map { shortcut, items in
                let modes = CaptureMode.allCases.filter { mode in
                    items.contains(where: { $0.mode == mode })
                }
                return HotkeyConflict(shortcut: shortcut, modes: modes)
            }
            .sorted { $0.shortcut.displayText < $1.shortcut.displayText }
    }

    public func validationError(for mode: CaptureMode, shortcut: HotkeyShortcut?) -> String? {
        guard let shortcut else {
            return nil
        }

        guard shortcut.isValid else {
            return "Shortcuts must include at least one modifier key."
        }

        var proposed = self
        proposed[mode] = shortcut

        return proposed.conflicts.first?.message
    }
}