import Foundation

struct PushMessage: Decodable {
    var user: String
    var commandType: String
    var bolusAmount: Decimal?
    var target: Int?
    var duration: Int?
    var carbs: Int?
    var protein: Int?
    var fat: Int?
    var sharedSecret: String
    var timestamp: TimeInterval

    enum CodingKeys: String, CodingKey {
        case user
        case commandType = "command_type"
        case bolusAmount = "bolus_amount"
        case target
        case duration
        case carbs
        case protein
        case fat
        case sharedSecret = "shared_secret"
        case timestamp
    }
}
