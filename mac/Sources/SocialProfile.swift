import Foundation
enum SocialProfile {
 static let fields=[("left","seatmate"),("right","seatmateRight"),("viewRoom","viewRoom")]
 static func capture() -> [String:Any] {Dictionary(uniqueKeysWithValues:fields.map{($0.0,Settings.get($0.1) as Any)})}
 static func apply(_ profile: [String:Any]) throws {var changes: [(String,String)]=[];for (key,setting) in fields {if let value=profile[key] as? String,value.count<=128 {changes.append((setting,value))}};let left=DeviceSync.str(profile,"left");if !left.isEmpty && left == DeviceSync.str(profile,"right") {changes.append(("seatmateRight",""))};if !changes.isEmpty {for (key,value) in changes {try Settings.set(key,value)}}}
 static func missing(_ remote: [String:Any],_ local: [String:Any]) -> [String:Any] {local.filter { item in remote[item.key] == nil && (item.key == "invite" || fields.contains(where:{$0.0 == item.key})) }}
}
