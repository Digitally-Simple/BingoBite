import Foundation
import SwiftData

enum LicenseError: LocalizedError {
    case invalidKey
    case activationLimitReached
    case keyInactive
    case keyNotFound
    case networkError(Error)
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidKey:
            return "This license key is invalid."
        case .activationLimitReached:
            return "This license key has reached its activation limit. Please deactivate another device first."
        case .keyInactive:
            return "This license key is no longer active."
        case .keyNotFound:
            return "License key not found. Please check and try again."
        case .networkError:
            return "Unable to connect. Please check your internet connection and try again."
        case .httpError(let code):
            return "Server error (\(code)). Please try again later."
        }
    }
}

enum LicenseService {
    private static let baseURL = "https://test.dodopayments.com/licenses"
    private static let gracePeriodDays = 7

    struct ActivateResponse: Decodable {
        let id: String
    }

    // MARK: - API Calls

    static func activate(licenseKey: String) async throws -> ActivateResponse {
        let url = URL(string: "\(baseURL)/activate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "license_key": licenseKey,
            "name": deviceName()
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw LicenseError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LicenseError.httpError(0)
        }

        switch httpResponse.statusCode {
        case 200, 201:
            return try JSONDecoder().decode(ActivateResponse.self, from: data)
        case 404:
            throw LicenseError.keyNotFound
        case 422:
            throw LicenseError.activationLimitReached
        case 400:
            throw LicenseError.invalidKey
        default:
            throw LicenseError.httpError(httpResponse.statusCode)
        }
    }

    static func validate(licenseKey: String, instanceId: String) async throws -> Bool {
        let url = URL(string: "\(baseURL)/validate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "license_key": licenseKey,
            "license_key_instance_id": instanceId
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw LicenseError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LicenseError.httpError(0)
        }

        guard httpResponse.statusCode == 200 else {
            throw LicenseError.httpError(httpResponse.statusCode)
        }

        struct ValidateResponse: Decodable {
            let valid: Bool
        }

        let result = try JSONDecoder().decode(ValidateResponse.self, from: data)
        return result.valid
    }

    static func deactivate(licenseKey: String, instanceId: String) async throws {
        let url = URL(string: "\(baseURL)/deactivate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "license_key": licenseKey,
            "license_key_instance_id": instanceId
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_,  response): (Data, URLResponse)
        do {
            (_, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw LicenseError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LicenseError.httpError(0)
        }

        guard httpResponse.statusCode == 200 else {
            throw LicenseError.httpError(httpResponse.statusCode)
        }
    }

    // MARK: - Helpers

    static func deviceName() -> String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    static func isWithinOfflineGracePeriod(lastValidation: Date?) -> Bool {
        guard let lastValidation else { return false }
        let deadline = Calendar.current.date(byAdding: .day, value: gracePeriodDays, to: lastValidation)!
        return Date() < deadline
    }

    static func persistActivation(settings: AppSettings, licenseKey: String, instanceId: String, in context: ModelContext) {
        settings.licenseKey = licenseKey
        settings.licenseKeyInstanceId = instanceId
        settings.lastLicenseValidationDate = Date()
        try? context.save()
    }

    static func clearLicense(settings: AppSettings, in context: ModelContext) {
        settings.licenseKey = ""
        settings.licenseKeyInstanceId = ""
        settings.lastLicenseValidationDate = nil
        try? context.save()
    }
}

extension Notification.Name {
    static let licenseStateChanged = Notification.Name("licenseStateChanged")
}
