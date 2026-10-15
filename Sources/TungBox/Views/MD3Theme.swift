import AppKit
import Foundation

// MARK: - Color Mix & Hex Helper

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        let r = CGFloat((hex & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((hex & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(hex & 0x0000FF) / 255.0
        self.init(calibratedRed: r, green: g, blue: b, alpha: alpha)
    }

    func mixed(with color: NSColor, ratio: CGFloat) -> NSColor {
        guard let selfRGB = self.usingColorSpace(.deviceRGB),
              let targetRGB = color.usingColorSpace(.deviceRGB) else {
            return self
        }

        let r = selfRGB.redComponent * (1.0 - ratio) + targetRGB.redComponent * ratio
        let g = selfRGB.greenComponent * (1.0 - ratio) + targetRGB.greenComponent * ratio
        let b = selfRGB.blueComponent * (1.0 - ratio) + targetRGB.blueComponent * ratio
        let a = selfRGB.alphaComponent * (1.0 - ratio) + targetRGB.alphaComponent * ratio

        return NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
    }
}

// MARK: - MD3 Design System Colors

struct MD3ColorScheme: Sendable {
    let name: String
    let lightPrimary: NSColor
    let lightAccent: NSColor
    let lightBackground: NSColor
    let darkPrimary: NSColor
    let darkAccent: NSColor
    let darkBackground: NSColor
}

@MainActor
enum MD3 {
    static var isDark: Bool {
        get { _isDark }
        set { _isDark = newValue }
    }
    private static var _isDark = UserDefaults.standard.bool(forKey: "appearanceIsDark")

    static let colorSchemes: [MD3ColorScheme] = [
        MD3ColorScheme(
            name: "经典蓝 (Classic Blue)",
            lightPrimary: NSColor(hex: 0x1A73E8),
            lightAccent: NSColor(hex: 0xE8F0FE),
            lightBackground: NSColor(hex: 0xFAFAFF),
            darkPrimary: NSColor(hex: 0x8AB4F8),
            darkAccent: NSColor(hex: 0x174EA6),
            darkBackground: NSColor(hex: 0x0E1015)
        ),
        MD3ColorScheme(
            name: "翡翠绿 (Emerald Green)",
            lightPrimary: NSColor(hex: 0x0F9D58),
            lightAccent: NSColor(hex: 0xE6F4EA),
            lightBackground: NSColor(hex: 0xFAFBFB),
            darkPrimary: NSColor(hex: 0x81C995),
            darkAccent: NSColor(hex: 0x0D522C),
            darkBackground: NSColor(hex: 0x0E1310)
        ),
        MD3ColorScheme(
            name: "夕阳橙 (Sunset Orange)",
            lightPrimary: NSColor(hex: 0xE65100),
            lightAccent: NSColor(hex: 0xFDF0E6),
            lightBackground: NSColor(hex: 0xFCFAF9),
            darkPrimary: NSColor(hex: 0xFFB74D),
            darkAccent: NSColor(hex: 0x8D3C00),
            darkBackground: NSColor(hex: 0x13110E)
        ),
        MD3ColorScheme(
            name: "樱花粉 (Sakura Pink)",
            lightPrimary: NSColor(hex: 0xD81B60),
            lightAccent: NSColor(hex: 0xFCE4EC),
            lightBackground: NSColor(hex: 0xFFF9FA),
            darkPrimary: NSColor(hex: 0xF48FB1),
            darkAccent: NSColor(hex: 0x880E4F),
            darkBackground: NSColor(hex: 0x140E10)
        ),
        MD3ColorScheme(
            name: "紫罗兰 (Purple Velvet)",
            lightPrimary: NSColor(hex: 0x7B1FA2),
            lightAccent: NSColor(hex: 0xF3E5F5),
            lightBackground: NSColor(hex: 0xFAF9FB),
            darkPrimary: NSColor(hex: 0xCE93D8),
            darkAccent: NSColor(hex: 0x4A148C),
            darkBackground: NSColor(hex: 0x110E14)
        ),
        MD3ColorScheme(
            name: "深海绿 (Teal Breeze)",
            lightPrimary: NSColor(hex: 0x00796B),
            lightAccent: NSColor(hex: 0xE0F2F1),
            lightBackground: NSColor(hex: 0xF9FBFB),
            darkPrimary: NSColor(hex: 0x80CBC4),
            darkAccent: NSColor(hex: 0x004D40),
            darkBackground: NSColor(hex: 0x0E1313)
        ),
        MD3ColorScheme(
            name: "琥珀金 (Sandy Gold)",
            lightPrimary: NSColor(hex: 0xE6A100),
            lightAccent: NSColor(hex: 0xFFFDE7),
            lightBackground: NSColor(hex: 0xFCFCFA),
            darkPrimary: NSColor(hex: 0xFFD54F),
            darkAccent: NSColor(hex: 0x5F4B00),
            darkBackground: NSColor(hex: 0x13120E)
        ),
        MD3ColorScheme(
            name: "绯红红 (Crimson Red)",
            lightPrimary: NSColor(hex: 0xC62828),
            lightAccent: NSColor(hex: 0xFFEBEE),
            lightBackground: NSColor(hex: 0xFFFDFD),
            darkPrimary: NSColor(hex: 0xEF9A9A),
            darkAccent: NSColor(hex: 0x7F0000),
            darkBackground: NSColor(hex: 0x140E0E)
        ),
        MD3ColorScheme(
            name: "极客灰 (Charcoal Gray)",
            lightPrimary: NSColor(hex: 0x37474F),
            lightAccent: NSColor(hex: 0xECEFF1),
            lightBackground: NSColor(hex: 0xF8F9FA),
            darkPrimary: NSColor(hex: 0x90A4AE),
            darkAccent: NSColor(hex: 0x263238),
            darkBackground: NSColor(hex: 0x101213)
        ),
        MD3ColorScheme(
            name: "靛蓝夜 (Indigo Night)",
            lightPrimary: NSColor(hex: 0x3F51B5),
            lightAccent: NSColor(hex: 0xE8EAF6),
            lightBackground: NSColor(hex: 0xFAF9FD),
            darkPrimary: NSColor(hex: 0x9FA8DA),
            darkAccent: NSColor(hex: 0x1A237E),
            darkBackground: NSColor(hex: 0x0E0F14)
        )
    ]

    static var currentSchemeIndex: Int {
        get {
            let val = UserDefaults.standard.integer(forKey: "MD3ColorSchemeIndex")
            if val >= 0 && val < colorSchemes.count {
                return val
            }
            return 0
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "MD3ColorSchemeIndex")
        }
    }

    static var currentScheme: MD3ColorScheme {
        colorSchemes[currentSchemeIndex]
    }

    static var primary: NSColor {
        isDark ? currentScheme.darkPrimary : currentScheme.lightPrimary
    }
    static var onPrimary: NSColor {
        isDark ? currentScheme.darkBackground : NSColor.white
    }
    static var primaryContainer: NSColor {
        isDark ? currentScheme.darkAccent : currentScheme.lightAccent
    }
    static var onPrimaryContainer: NSColor {
        isDark ? currentScheme.darkPrimary : currentScheme.lightPrimary
    }

    static var secondaryContainer: NSColor {
        isDark ? currentScheme.darkAccent.mixed(with: .white, ratio: 0.1) : currentScheme.lightAccent.mixed(with: .black, ratio: 0.05)
    }
    static var onSecondaryContainer: NSColor {
        isDark ? currentScheme.darkPrimary : currentScheme.lightPrimary
    }

    static var surface: NSColor {
        isDark ? currentScheme.darkBackground.mixed(with: .white, ratio: 0.06) : NSColor.white
    }
    static var onSurface: NSColor {
        isDark ? NSColor(calibratedRed: 0.89, green: 0.89, blue: 0.92, alpha: 1) : NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.14, alpha: 1)
    }
    static var surfaceContainer: NSColor {
        isDark ? currentScheme.darkBackground.mixed(with: .white, ratio: 0.12) : currentScheme.lightBackground.mixed(with: currentScheme.lightPrimary, ratio: 0.04)
    }
    static var surfaceContainerLow: NSColor {
        isDark ? currentScheme.darkBackground.mixed(with: .white, ratio: 0.08) : currentScheme.lightBackground.mixed(with: currentScheme.lightPrimary, ratio: 0.02)
    }
    static var onSurfaceVariant: NSColor {
        isDark ? NSColor(calibratedRed: 0.75, green: 0.76, blue: 0.80, alpha: 1) : NSColor(calibratedRed: 0.27, green: 0.28, blue: 0.33, alpha: 1)
    }
    static var outline: NSColor {
        isDark ? NSColor(calibratedRed: 0.54, green: 0.55, blue: 0.59, alpha: 1) : NSColor(calibratedRed: 0.45, green: 0.46, blue: 0.51, alpha: 1)
    }
    static var outlineVariant: NSColor {
        isDark ? currentScheme.darkBackground.mixed(with: currentScheme.darkPrimary, ratio: 0.12) : currentScheme.lightBackground.mixed(with: currentScheme.lightPrimary, ratio: 0.08)
    }
    static var background: NSColor {
        // 浅色模式：固定 #ECECEC（用户指定）。深色模式保持原 darkBackground。
        isDark
            ? currentScheme.darkBackground
            : NSColor(calibratedRed: 0xEC/255.0, green: 0xEC/255.0, blue: 0xEC/255.0, alpha: 1)
    }

    // Status colors
    static var success: NSColor {
        isDark ? NSColor(calibratedRed: 0.44, green: 0.81, blue: 0.55, alpha: 1) : NSColor(calibratedRed: 0.10, green: 0.55, blue: 0.23, alpha: 1)
    }
    static var successContainer: NSColor {
        isDark ? NSColor(calibratedRed: 0.05, green: 0.28, blue: 0.12, alpha: 1) : NSColor(calibratedRed: 0.85, green: 0.95, blue: 0.88, alpha: 1)
    }
    static var onSuccessContainer: NSColor {
        isDark ? NSColor(calibratedRed: 0.70, green: 0.94, blue: 0.76, alpha: 1) : NSColor(calibratedRed: 0.03, green: 0.22, blue: 0.07, alpha: 1)
    }

    static var error: NSColor {
        isDark ? NSColor(calibratedRed: 1.00, green: 0.45, blue: 0.45, alpha: 1) : NSColor(calibratedRed: 0.75, green: 0.10, blue: 0.10, alpha: 1)
    }

    static var warning: NSColor {
        isDark ? NSColor(calibratedRed: 1.00, green: 0.70, blue: 0.30, alpha: 1) : NSColor(calibratedRed: 0.85, green: 0.50, blue: 0.05, alpha: 1)
    }

    /// Text color for a latency string: < 400ms green, < 800ms orange, ≥ 800ms red.
    /// Non-numeric (未测试 / — / 失败) → neutral.
    static func latencyTextColor(_ delay: String) -> NSColor {
        let cleaned = delay.replacingOccurrences(of: " ms", with: "").trimmingCharacters(in: .whitespaces)
        guard let ms = Int(cleaned) else { return onSurfaceVariant }
        if ms < 400 { return success }
        if ms < 800 { return warning }
        return error
    }
}

// MARK: - View Theme Refresh Helper

@MainActor
protocol MD3Themeable: AnyObject {
    func themeChanged()
}

extension NSView {
    func refreshSubviews() {
        self.needsDisplay = true
        if let themeable = self as? MD3Themeable {
            themeable.themeChanged()
        }
        for subview in subviews {
            subview.refreshSubviews()
        }
    }
}
