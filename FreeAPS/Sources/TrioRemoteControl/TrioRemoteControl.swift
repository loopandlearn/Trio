import Foundation
import Swinject

class TrioRemoteControl: Injectable {
    static let shared = TrioRemoteControl()

    @Injected() private var tempTargetsStorage: TempTargetsStorage!
    @Injected() private var carbsStorage: CarbsStorage!

    private let timeWindow: TimeInterval = 3 // Defines how old messages that are accepted

    private init() {
        injectServices(FreeAPSApp.resolver)
    }

    func handleRemoteNotification(userInfo: [AnyHashable: Any]) {
        let enabled = UserDefaults.standard.bool(forKey: "TRCenabled")
        guard enabled else {
            debug(.remoteControl, "Remote command received, but remote control is disabled in settings. Ignoring command.")
            return
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: userInfo)

            let pushMessage = try JSONDecoder().decode(PushMessage.self, from: jsonData)

            let currentTime = Date().timeIntervalSince1970
            let timeDifference = currentTime - pushMessage.timestamp

            guard abs(timeDifference) <= timeWindow else {
                debug(
                    .remoteControl,
                    "Push message rejected: time difference of \(timeDifference) seconds exceeds the allowed window."
                )
                return
            }
            debug(.remoteControl, "Push message with acceptable timestamp difference: \(timeDifference) seconds.")

            let storedSecret = UserDefaults.standard.string(forKey: "TRCsharedSecret") ?? ""
            guard !storedSecret.isEmpty else {
                debug(
                    .remoteControl,
                    "Shared secret is missing in settings. Validation of the push message cannot proceed without it."
                )
                return
            }

            guard pushMessage.sharedSecret == storedSecret else {
                debug(.remoteControl, "Shared secret mismatch.")
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
                debug(.remoteControl, "Unsupported command type received: \(pushMessage.commandType)")
            }

        } catch {
            debug(.remoteControl, "Failed to decode PushMessage: \(error.localizedDescription)")
        }
    }

    private func handleMealCommand(_ pushMessage: PushMessage) {
        guard
            let carbs = pushMessage.carbs,
            let fat = pushMessage.fat,
            let protein = pushMessage.protein
        else {
            debug(.remoteControl, "Meal command received with missing or invalid data.")
            return
        }

        let settings = FreeAPSApp.resolver.resolve(SettingsManager.self)?.settings
        let maxCarbs = settings?.maxCarbs ?? Decimal(0)
        let maxFat = settings?.maxFat ?? Decimal(0)
        let maxProtein = settings?.maxProtein ?? Decimal(0)

        guard Decimal(carbs) <= maxCarbs else {
            debug(.remoteControl, "Meal command rejected: received carbs \(carbs) exceeds the max allowed carbs \(maxCarbs).")
            return
        }

        guard Decimal(fat) <= maxFat else {
            debug(.remoteControl, "Meal command rejected: received fat \(fat) exceeds the max allowed fat \(maxFat).")
            return
        }

        guard Decimal(protein) <= maxProtein else {
            debug(
                .remoteControl,
                "Meal command rejected: received protein \(protein) exceeds the max allowed protein \(maxProtein)."
            )
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
            debug(.remoteControl, "Bolus command received without a valid bolus amount.")
            return
        }

        let maxBolus = FreeAPSApp.resolver.resolve(SettingsManager.self)?.pumpSettings.maxBolus ?? Decimal(0)

        guard bolusAmount <= maxBolus else {
            debug(
                .remoteControl,
                "Bolus command rejected: requested amount \(bolusAmount) exceeds max bolus limit of \(maxBolus)."
            )
            return
        }

        debug(.remoteControl, "Enacting bolus command with amount: \(bolusAmount)")

        guard let apsManager = FreeAPSApp.resolver.resolve(APSManager.self) else {
            debug(.remoteControl, "APSManager is not available.")
            return
        }

        apsManager.enactBolus(amount: Double(bolusAmount), isSMB: false)
    }

    private func handleTempTargetCommand(_ pushMessage: PushMessage) {
        guard let targetValue = pushMessage.target,
              let durationValue = pushMessage.duration
        else {
            debug(.remoteControl, "Temp target command received with missing or invalid data.")
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
            debug(.remoteControl, "No active temp target to cancel.")
            return
        }

        let cancelEntry = TempTarget.cancel(at: Date())
        tempTargetsStorage.storeTempTargets([cancelEntry])

        debug(.remoteControl, "Temp Target cancelled successfully.")
    }

    func determineAPNSEnvironment() {
        let isAPNSProduction = isRunningInAPNSProductionEnvironment()

        debug(.remoteControl, "APNS Environment determined: \(isAPNSProduction ? "Production" : "Sandbox")")
    }

    private func isRunningInAPNSProductionEnvironment() -> Bool {
        if let appStoreReceiptURL = Bundle.main.appStoreReceiptURL {
            return appStoreReceiptURL.lastPathComponent != "sandboxReceipt"
        }
        return false
    }
}
