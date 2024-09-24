import Foundation
import Swinject

class TrioRemoteControl: Injectable {
    static let shared = TrioRemoteControl()

    @Injected() private var tempTargetsStorage: TempTargetsStorage!
    @Injected() private var carbsStorage: CarbsStorage!
    @Injected() private var nightscoutManager: NightscoutManager!

    private let timeWindow: TimeInterval = 300 // Defines how old messages that are accepted

    private init() {
        injectServices(FreeAPSApp.resolver)
    }

    func handleRemoteNotification(userInfo: [AnyHashable: Any]) {
        let enabled = UserDefaults.standard.bool(forKey: "TRCenabled")
        guard enabled else {
            let note = "Remote command received, but remote control is disabled in settings. Ignoring command."
            debug(.remoteControl, note)
            nightscoutManager.uploadNoteTreatment(note: note)
            return
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: userInfo)

            let pushMessage = try JSONDecoder().decode(PushMessage.self, from: jsonData)

            let currentTime = Date().timeIntervalSince1970
            let timeDifference = currentTime - pushMessage.timestamp

            guard abs(timeDifference) <= timeWindow else {
                let note = "Push message rejected: time difference of \(timeDifference) seconds exceeds the allowed window."
                debug(.remoteControl, note)
                nightscoutManager.uploadNoteTreatment(note: note)
                return
            }
            debug(.remoteControl, "Push message with acceptable timestamp difference: \(timeDifference) seconds.")

            let storedSecret = UserDefaults.standard.string(forKey: "TRCsharedSecret") ?? ""
            guard !storedSecret.isEmpty else {
                let note = "Shared secret is missing in settings. Validation of the push message cannot proceed without it."
                debug(.remoteControl, note)
                nightscoutManager.uploadNoteTreatment(note: note)
                return
            }

            guard pushMessage.sharedSecret == storedSecret else {
                let note = "Shared secret mismatch."
                debug(.remoteControl, note)
                nightscoutManager.uploadNoteTreatment(note: note)
                return
            }

            switch pushMessage.commandType {
            case "bolus":
                handleBolusCommand(pushMessage)
            case "temp_target":
                handleTempTargetCommand(pushMessage)
            case "cancel_temp_target":
                cancelTempTarget()
            case "meal":
                handleMealCommand(pushMessage)
            default:
                let note = "Unsupported command type received: \(pushMessage.commandType)"
                debug(.remoteControl, note)
                nightscoutManager.uploadNoteTreatment(note: note)
            }

        } catch {
            let note = "Failed to decode PushMessage: \(error.localizedDescription)"
            debug(.remoteControl, note)
            nightscoutManager.uploadNoteTreatment(note: note)
        }
    }

    private func handleMealCommand(_ pushMessage: PushMessage) {
        guard
            let carbs = pushMessage.carbs,
            let fat = pushMessage.fat,
            let protein = pushMessage.protein
        else {
            let note = "Meal command received with missing or invalid data."
            debug(.remoteControl, note)
            nightscoutManager.uploadNoteTreatment(note: note)
            return
        }

        let settings = FreeAPSApp.resolver.resolve(SettingsManager.self)?.settings
        let maxCarbs = settings?.maxCarbs ?? Decimal(0)
        let maxFat = settings?.maxFat ?? Decimal(0)
        let maxProtein = settings?.maxProtein ?? Decimal(0)

        guard Decimal(carbs) <= maxCarbs else {
            let note = "Meal command rejected: received carbs \(carbs) exceeds the max allowed carbs \(maxCarbs)."
            debug(.remoteControl, note)
            nightscoutManager.uploadNoteTreatment(note: note)
            return
        }

        guard Decimal(fat) <= maxFat else {
            let note = "Meal command rejected: received fat \(fat) exceeds the max allowed fat \(maxFat)."
            debug(.remoteControl, note)
            nightscoutManager.uploadNoteTreatment(note: note)
            return
        }

        guard Decimal(protein) <= maxProtein else {
            let note = "Meal command rejected: received protein \(protein) exceeds the max allowed protein \(maxProtein)."
            debug(.remoteControl, note)
            nightscoutManager.uploadNoteTreatment(note: note)
            return
        }

        let mealEntry = CarbsEntry(
            id: UUID().uuidString,
            createdAt: Date(),
            carbs: Decimal(carbs),
            fat: Decimal(fat),
            protein: Decimal(protein),
            note: "Remote meal command",
            enteredBy: CarbsEntry.manual,
            isFPU: false,
            fpuID: nil
        )

        carbsStorage.storeCarbs([mealEntry])
        debug(.remoteControl, "Meal command processed successfully with carbs: \(carbs), fat: \(fat), protein: \(protein)")
    }

    private func handleBolusCommand(_ pushMessage: PushMessage) {
        guard let bolusAmount = pushMessage.bolusAmount else {
            let note = "Bolus command received without a valid bolus amount."
            debug(.remoteControl, note)
            nightscoutManager.uploadNoteTreatment(note: note)
            return
        }

        let maxBolus = FreeAPSApp.resolver.resolve(SettingsManager.self)?.pumpSettings.maxBolus ?? Decimal(0)

        guard bolusAmount <= maxBolus else {
            let note = "Bolus command rejected: requested amount \(bolusAmount) exceeds max bolus limit of \(maxBolus)."
            debug(.remoteControl, note)
            nightscoutManager.uploadNoteTreatment(note: note)
            return
        }

        debug(.remoteControl, "Enacting bolus command with amount: \(bolusAmount)")

        guard let apsManager = FreeAPSApp.resolver.resolve(APSManager.self) else {
            let note = "APSManager is not available."
            debug(.remoteControl, note)
            nightscoutManager.uploadNoteTreatment(note: note)
            return
        }

        apsManager.enactBolus(amount: Double(bolusAmount), isSMB: false)
    }

    private func handleTempTargetCommand(_ pushMessage: PushMessage) {
        guard let targetValue = pushMessage.target,
              let durationValue = pushMessage.duration
        else {
            let note = "Temp target command received with missing or invalid data."
            debug(.remoteControl, note)
            nightscoutManager.uploadNoteTreatment(note: note)
            return
        }

        let durationInMinutes = Int(durationValue)

        let tempTarget = TempTarget(
            name: "Remote Control",
            createdAt: Date(),
            targetTop: Decimal(targetValue),
            targetBottom: Decimal(targetValue),
            duration: Decimal(durationInMinutes),
            enteredBy: pushMessage.user,
            reason: "Remote temp target command"
        )

        tempTargetsStorage.storeTempTargets([tempTarget])

        debug(.remoteControl, "Temp target set with target: \(targetValue), duration: \(durationInMinutes) minutes.")
    }

    func cancelTempTarget() {
        debug(.remoteControl, "Cancelling Temp Target")

        guard tempTargetsStorage.current() != nil else {
            let note = "No active temp target to cancel."
            debug(.remoteControl, note)
            nightscoutManager.uploadNoteTreatment(note: note)
            return
        }

        let cancelEntry = TempTarget.cancel(at: Date())
        tempTargetsStorage.storeTempTargets([cancelEntry])

        debug(.remoteControl, "Temp Target cancelled successfully.")
    }

    func handleAPNSChanges(deviceToken: String?) {
        let previousDeviceToken = UserDefaults.standard.string(forKey: "deviceToken")
        let previousIsAPNSProduction = UserDefaults.standard.bool(forKey: "isAPNSProduction")

        let isAPNSProduction = isRunningInAPNSProductionEnvironment()

        var shouldUploadProfiles = false

        if let token = deviceToken, token != previousDeviceToken {
            UserDefaults.standard.set(token, forKey: "deviceToken")
            debug(.remoteControl, "Device Token updated: \(token)")
            shouldUploadProfiles = true
        }

        if previousIsAPNSProduction != isAPNSProduction {
            UserDefaults.standard.set(isAPNSProduction, forKey: "isAPNSProduction")
            debug(.remoteControl, "APNS Environment changed to: \(isAPNSProduction ? "Production" : "Sandbox")")
            shouldUploadProfiles = true
        }

        if shouldUploadProfiles {
            nightscoutManager.uploadProfileAndSettings(true)
        } else {
            debug(.remoteControl, "No changes detected in deviceToken or APNS environment.")
        }
    }

    private func isRunningInAPNSProductionEnvironment() -> Bool {
        if let appStoreReceiptURL = Bundle.main.appStoreReceiptURL {
            return appStoreReceiptURL.lastPathComponent != "sandboxReceipt"
        }
        return false
    }
}
