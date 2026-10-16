import Foundation

/// Pure string matching helper for converting proxy node tags/names into country/region flag Emojis.
enum CountryFlagHelper {
    private static let flagRules: [(keywords: [String], flag: String)] = [
        (["香港", "hk", "hongkong", "hong kong"], "🇭🇰"),
        (["台湾", "tw", "taiwan", "台北"], "🇹🇼"),
        (["日本", "jp", "japan", "东京", "大阪"], "🇯🇵"),
        (["新加坡", "sg", "singapore", "狮城"], "🇸🇬"),
        (["美国", "us", "united states", "america"], "🇺🇸"),
        (["英国", "uk", "gb", "britain", "london", "伦敦"], "🇬🇧"),
        (["土耳其", "tr", "turkey", "istanbul", "伊斯坦布尔"], "🇹🇷"),
        (["德国", "de", "germany", "frankfurt", "法兰克福"], "🇩🇪"),
        (["法国", "fr", "france", "paris", "巴黎"], "🇫🇷"),
        (["韩国", "kr", "korea", "seoul", "首尔"], "🇰🇷"),
        (["加拿大", "ca", "canada"], "🇨🇦"),
        (["澳大利亚", "au", "australia", "sydney", "悉尼", "墨尔本"], "🇦🇺"),
        (["俄罗斯", "ru", "russia", "moscow", "莫斯科"], "🇷🇺"),
        (["印度", "in", "india", "mumbai"], "🇮🇳"),
        (["荷兰", "nl", "netherlands", "amsterdam"], "🇳🇱"),
        (["阿根廷", "ar", "argentina"], "🇦🇷"),
        (["巴西", "br", "brazil"], "🇧🇷"),
        (["马来西亚", "my", "malaysia"], "🇲🇾"),
        (["泰国", "th", "thailand", "bangkok"], "🇹🇭"),
        (["越南", "vn", "vietnam"], "🇻🇳"),
        (["菲律宾", "ph", "philippines"], "🇵🇭"),
        (["瑞士", "ch", "switzerland"], "🇨🇭"),
        (["意大利", "it", "italy"], "🇮🇹"),
        (["西班牙", "es", "spain"], "🇪🇸"),
        (["中国", "cn", "china"], "🇨🇳")
    ]

    static func flag(for nodeName: String) -> String {
        let lower = nodeName.lowercased()
        for rule in flagRules {
            for keyword in rule.keywords {
                if lower.contains(keyword) {
                    return rule.flag
                }
            }
        }
        return "🌐"
    }
}
