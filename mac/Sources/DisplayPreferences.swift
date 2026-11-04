import Foundation

enum DisplayPreferences {
    static func percent(_ key: String) -> Int {
        if let value = Int(Settings.get(key)) { return max(75,min(200,value)) }
        return Settings.get("largeText") == "1" ? 125 : 100
    }
}
