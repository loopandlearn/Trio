import Foundation

struct NightscoutStatus: JSON {
    let device: String
    let openaps: OpenAPSStatus
    let pump: NSPumpStatus
    let uploader: Uploader
}

struct OpenAPSStatus: JSON {
    let iob: IOBEntry?
    let suggested: Suggestion?
    let enacted: Suggestion?
    let version: String
}

struct NSPumpStatus: JSON {
    let clock: Date
    let battery: Battery?
    let reservoir: Decimal?
    let status: PumpStatus?
}

struct Uploader: JSON {
    let batteryVoltage: Decimal?
    let battery: Int
}

struct NightscoutTimevalue: JSON {
    let time: String
    let value: Decimal
    let timeAsSeconds: Int?
}

struct ScheduledNightscoutProfile: JSON {
    let dia: Decimal
    let carbs_hr: Int
    let delay: Decimal
    let timezone: String
    let target_low: [NightscoutTimevalue]
    let target_high: [NightscoutTimevalue]
    let sens: [NightscoutTimevalue]
    let basal: [NightscoutTimevalue]
    let carbratio: [NightscoutTimevalue]
    let units: String
}

struct NightscoutProfileStore: JSON {
    let defaultProfile: String
    let startDate: Date
    let mills: Int
    let units: String
    let enteredBy: String
    let store: [String: ScheduledNightscoutProfile]
    let bundleIdentifier: String
    let deviceToken: String
    let isAPNSProduction: Bool
    let overridePresets: [NightscoutOverridePreset]
}

struct NightscoutOverridePreset: Codable {
    var advancedSettings: Bool
    var cr: Bool
    var date: Date?
    var duration: Decimal?
    var end: Decimal?
    var id: String?
    var indefinite: Bool
    var isf: Bool
    var isfAndCr: Bool
    var name: String?
    var percentage: Double
    var smbIsOff: Bool
    var smbIsScheduledOff: Bool
    var smbMinutes: Decimal?
    var start: Decimal?
    var target: Decimal?
    var uamMinutes: Decimal?
}

extension OverridePresets {
    func toNightscoutOverridePreset() -> NightscoutOverridePreset {
        NightscoutOverridePreset(
            advancedSettings: advancedSettings,
            cr: cr,
            date: date,
            duration: duration?.decimalValue,
            end: end?.decimalValue,
            id: id,
            indefinite: indefinite,
            isf: isf,
            isfAndCr: isfAndCr,
            name: name,
            percentage: percentage,
            smbIsOff: smbIsOff,
            smbIsScheduledOff: smbIsScheduledOff,
            smbMinutes: smbMinutes?.decimalValue,
            start: start?.decimalValue,
            target: target?.decimalValue,
            uamMinutes: uamMinutes?.decimalValue
        )
    }
}
