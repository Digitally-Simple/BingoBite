import Foundation
import SwiftData
import Security

enum TrialStatus {
    case notStarted
    case active(daysRemaining: Int)
    case expired
}

enum TrialService {
    static let trialDurationDays = 14

    private static let keychainService = "com.digitallysimple.BingoBite.trialStartDate"
    private static let keychainAccount = "trial"

    // MARK: - Public API

    static func startTrial(settings: AppSettings, in context: ModelContext) {
        let now = Date()
        settings.trialStartDate = now
        try? context.save()
        saveToKeychain(date: now)
    }

    static func trialStatus(settings: AppSettings, in context: ModelContext) -> TrialStatus {
        let startDate = resolvedTrialStartDate(settings: settings, in: context)

        guard let startDate else {
            return .notStarted
        }

        let calendar = Calendar.current
        let daysSinceStart = calendar.dateComponents([.day], from: calendar.startOfDay(for: startDate), to: calendar.startOfDay(for: Date())).day ?? 0
        let daysRemaining = trialDurationDays - daysSinceStart

        if daysRemaining > 0 {
            return .active(daysRemaining: daysRemaining)
        } else {
            return .expired
        }
    }

    // MARK: - Date Resolution

    /// Keychain is authoritative. Syncs SwiftData <-> Keychain if they diverge.
    private static func resolvedTrialStartDate(settings: AppSettings, in context: ModelContext) -> Date? {
        let keychainDate = readFromKeychain()
        let swiftDataDate = settings.trialStartDate

        switch (keychainDate, swiftDataDate) {
        case let (kc?, sd?) where kc == sd:
            return kc
        case let (kc?, _):
            // Keychain is authoritative — restore to SwiftData
            settings.trialStartDate = kc
            try? context.save()
            return kc
        case let (nil, sd?):
            // SwiftData has a date but Keychain doesn't — write to Keychain
            saveToKeychain(date: sd)
            return sd
        case (nil, nil):
            return nil
        }
    }

    // MARK: - Keychain

    private static func saveToKeychain(date: Date) {
        let dateString = ISO8601DateFormatter().string(from: date)
        guard let data = dateString.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]

        // Try to update first, add if not found
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    private static func readFromKeychain() -> Date? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let dateString = String(data: data, encoding: .utf8) else {
            return nil
        }

        return ISO8601DateFormatter().date(from: dateString)
    }
}
