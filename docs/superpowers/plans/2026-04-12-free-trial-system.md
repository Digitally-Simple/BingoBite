# Free Trial System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a 14-day free trial with Keychain-backed persistence and hard gate on expiration.

**Architecture:** TrialService owns trial logic and Keychain persistence. LicenseGateView gains trial states. BingoBiteApp coordinates trial + license checks. SidebarView shows a subtle days-remaining indicator.

**Tech Stack:** Swift, SwiftUI, SwiftData, Security framework (Keychain)

**Spec:** `docs/superpowers/specs/2026-04-12-free-trial-system-design.md`

---

### Task 1: Add `trialStartDate` to AppSettings

**Files:**
- Modify: `BingoBite/Models/AppSettings.swift`

- [ ] **Step 1: Add the property**

In `BingoBite/Models/AppSettings.swift`, add `trialStartDate` to the model class and init:

```swift
@Model
final class AppSettings {
    var licenseKey: String = ""
    var licenseKeyInstanceId: String = ""
    var lastLicenseValidationDate: Date? = nil
    var trialStartDate: Date? = nil

    init(licenseKey: String = "", licenseKeyInstanceId: String = "", lastLicenseValidationDate: Date? = nil, trialStartDate: Date? = nil) {
        self.licenseKey = licenseKey
        self.licenseKeyInstanceId = licenseKeyInstanceId
        self.lastLicenseValidationDate = lastLicenseValidationDate
        self.trialStartDate = trialStartDate
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -scheme BingoBite -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED (lightweight migration handles the new optional field automatically)

- [ ] **Step 3: Commit**

```bash
git add BingoBite/Models/AppSettings.swift
git commit -m "feat: add trialStartDate to AppSettings model"
```

---

### Task 2: Create TrialService

**Files:**
- Create: `BingoBite/Services/TrialService.swift`

- [ ] **Step 1: Create the TrialService file**

Create `BingoBite/Services/TrialService.swift` with the full implementation:

```swift
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
```

- [ ] **Step 2: Add the file to the Xcode project**

The file needs to be added to the Xcode project's BingoBite target. Open `BingoBite.xcodeproj/project.pbxproj` and add `TrialService.swift` to the Sources build phase, or add it via Xcode. Alternatively, if the project uses a folder reference (auto-discovers files), just building should pick it up.

Run: `xcodebuild -scheme BingoBite -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add BingoBite/Services/TrialService.swift BingoBite.xcodeproj/project.pbxproj
git commit -m "feat: add TrialService with Keychain-backed trial persistence"
```

---

### Task 3: Update BingoBiteApp to check trial status

**Files:**
- Modify: `BingoBite/BingoBiteApp.swift`

- [ ] **Step 1: Add trial state properties**

Add these `@State` properties alongside the existing ones in `BingoBiteApp`:

```swift
@State private var isLicensed = false
@State private var isTrialing = false
@State private var trialDaysRemaining = 0
@State private var trialExpired = false
@State private var hasCheckedLicense = false
```

(Replace the existing `isLicensed` and `hasCheckedLicense` declarations — just adding `isTrialing`, `trialDaysRemaining`, and `trialExpired`.)

- [ ] **Step 2: Update the body to handle trial state**

Replace the `Group` inside `WindowGroup` with:

```swift
Group {
    if !hasCheckedLicense {
        ProgressView("Checking license...")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if isLicensed || isTrialing {
        ContentView(trialDaysRemaining: isTrialing ? trialDaysRemaining : nil)
    } else {
        LicenseGateView(
            trialExpired: trialExpired,
            onActivated: { isLicensed = true },
            onTrialStarted: {
                isTrialing = true
                trialDaysRemaining = TrialService.trialDurationDays
            }
        )
    }
}
```

- [ ] **Step 3: Update `checkLicense()` to check trial after license**

Replace the `checkLicense()` method with:

```swift
@MainActor
private func checkLicense() async {
    let context = container.mainContext
    let descriptor = FetchDescriptor<AppSettings>()
    guard let settings = try? context.fetch(descriptor).first else {
        hasCheckedLicense = true
        return
    }

    let key = settings.licenseKey
    let instanceId = settings.licenseKeyInstanceId

    // 1. Check license key if present
    if !key.isEmpty, !instanceId.isEmpty {
        do {
            let valid = try await LicenseService.validate(licenseKey: key, instanceId: instanceId)
            if valid {
                settings.lastLicenseValidationDate = Date()
                try? context.save()
                isLicensed = true
                hasCheckedLicense = true
                return
            } else {
                LicenseService.clearLicense(settings: settings, in: context)
            }
        } catch {
            if LicenseService.isWithinOfflineGracePeriod(lastValidation: settings.lastLicenseValidationDate) {
                isLicensed = true
                hasCheckedLicense = true
                return
            }
        }
    }

    // 2. No valid license — check trial status
    let status = TrialService.trialStatus(settings: settings, in: context)
    switch status {
    case .notStarted:
        break // gate will show trial button
    case .active(let days):
        isTrialing = true
        trialDaysRemaining = days
    case .expired:
        trialExpired = true
    }

    hasCheckedLicense = true
}
```

- [ ] **Step 4: Build to verify** (will fail until Task 4 and 5 update ContentView and LicenseGateView signatures)

Note: This step will have compile errors because `ContentView` and `LicenseGateView` don't accept the new parameters yet. That's expected — Tasks 4 and 5 will fix this.

- [ ] **Step 5: Commit**

```bash
git add BingoBite/BingoBiteApp.swift
git commit -m "feat: add trial status check to app launch flow"
```

---

### Task 4: Update LicenseGateView with trial states

**Files:**
- Modify: `BingoBite/Views/LicenseGateView.swift`

- [ ] **Step 1: Add trial parameters**

Add the new parameters to `LicenseGateView` after the existing `@State` properties:

```swift
struct LicenseGateView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsItems: [AppSettings]

    @State private var licenseKeyInput = ""
    @State private var isActivating = false
    @State private var errorMessage: String?

    var trialExpired: Bool
    var onActivated: () -> Void
    var onTrialStarted: () -> Void
```

- [ ] **Step 2: Replace the body with trial-aware UI**

Replace the entire `body` computed property:

```swift
var body: some View {
    VStack(spacing: 24) {
        Spacer()

        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: 96, height: 96)

        Text("Welcome to BingoBite")
            .font(.largeTitle)
            .fontWeight(.bold)

        if trialExpired {
            Text("Your free trial has ended. Enter a license key to continue.")
                .foregroundStyle(.secondary)
        } else if settings.licenseKey.isEmpty {
            Text("Start your 14-day free trial, or enter a license key.")
                .foregroundStyle(.secondary)
        } else {
            Text("Enter your license key to get started.")
                .foregroundStyle(.secondary)
        }

        VStack(spacing: 12) {
            // Show "Start Free Trial" button only for new users (not expired, no stored key)
            if !trialExpired && settings.licenseKey.isEmpty {
                Button(action: startTrial) {
                    Text("Start Free Trial")
                        .frame(width: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Divider()
                    .frame(width: 360)
                    .padding(.vertical, 4)
            }

            TextField("License Key", text: $licenseKeyInput)
                .textFieldStyle(.roundedBorder)
                .frame(width: 360)
                .onSubmit { activateLicense() }

            Button(action: activateLicense) {
                if isActivating {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 100)
                } else {
                    Text("Activate")
                        .frame(width: 100)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(licenseKeyInput.trimmingCharacters(in: .whitespaces).isEmpty || isActivating)
            .keyboardShortcut(.defaultAction)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .frame(maxWidth: 360)
            }
        }

        Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear {
        let stored = settings.licenseKey
        if !stored.isEmpty {
            licenseKeyInput = stored
        }
    }
}
```

- [ ] **Step 3: Add the `startTrial` method**

Add this method alongside the existing `activateLicense()`:

```swift
private func startTrial() {
    TrialService.startTrial(settings: settings, in: modelContext)
    onTrialStarted()
}
```

- [ ] **Step 4: Build to verify** (may still fail until Task 5 updates ContentView)

- [ ] **Step 5: Commit**

```bash
git add BingoBite/Views/LicenseGateView.swift
git commit -m "feat: add trial states to LicenseGateView"
```

---

### Task 5: Update ContentView and SidebarView for trial indicator

**Files:**
- Modify: `BingoBite/ContentView.swift`
- Modify: `BingoBite/Views/SidebarView.swift`

- [ ] **Step 1: Add `trialDaysRemaining` parameter to ContentView**

Add the parameter and pass it through to SidebarView and SettingsSheet:

```swift
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Playlist.name) private var playlists: [Playlist]
    @Query(sort: \BingoGame.creationDate, order: .reverse) private var bingoGames: [BingoGame]

    var trialDaysRemaining: Int?

    @State private var sidebarSelection: SidebarSelection? = .allPlaylists
    @State private var showSettings = false
    @State private var showInspector = true
    @State private var selectedSong: Song?

    @StateObject private var audioPlayer = AudioPlayerService()
```

- [ ] **Step 2: Pass `trialDaysRemaining` to SidebarView**

In the `body`, update the `NavigationSplitView` sidebar:

```swift
NavigationSplitView {
    SidebarView(selection: $sidebarSelection, trialDaysRemaining: trialDaysRemaining, onShowSettings: { showSettings = true })
} detail: {
```

- [ ] **Step 3: Pass `trialDaysRemaining` to SettingsSheet**

Update the `.sheet` modifier:

```swift
.sheet(isPresented: $showSettings) {
    SettingsSheet(
        trialDaysRemaining: trialDaysRemaining,
        onLicenseDeactivated: {
            NotificationCenter.default.post(name: .licenseDeactivated, object: nil)
        }
    )
}
```

- [ ] **Step 4: Add trial indicator to SidebarView**

Update `SidebarView` to accept and display the trial info:

```swift
struct SidebarView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var selection: SidebarSelection?
    var trialDaysRemaining: Int?
    var onShowSettings: (() -> Void)?

    @Query(sort: \Playlist.name) private var playlists: [Playlist]
    @Query(sort: \BingoGame.creationDate, order: .reverse) private var bingoGames: [BingoGame]

    var body: some View {
        List(selection: $selection) {
            // ... existing sections unchanged ...
        }
        .listStyle(.sidebar)
        .navigationTitle("BingoBite")
        .safeAreaInset(edge: .bottom) {
            if let days = trialDaysRemaining {
                Button {
                    onShowSettings?()
                } label: {
                    Label("Trial: \(days) \(days == 1 ? "day" : "days") remaining", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
```

- [ ] **Step 5: Build to verify** (may still fail until Task 6 updates SettingsSheet)

- [ ] **Step 6: Commit**

```bash
git add BingoBite/ContentView.swift BingoBite/Views/SidebarView.swift
git commit -m "feat: add trial days remaining indicator to sidebar"
```

---

### Task 6: Update SettingsSheet for trial info

**Files:**
- Modify: `BingoBite/Views/SettingsSheet.swift`

- [ ] **Step 1: Add `trialDaysRemaining` parameter**

Add the parameter after the existing properties:

```swift
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsItems: [AppSettings]
    var trialDaysRemaining: Int?
    var onFolderChanged: () -> Void = { }
    var onLicenseDeactivated: (() -> Void)? = nil
```

- [ ] **Step 2: Update the License GroupBox to handle trial vs licensed**

Replace the `GroupBox("License")` section:

```swift
GroupBox("License") {
    VStack(alignment: .leading, spacing: 8) {
        if let days = trialDaysRemaining {
            // Trial mode
            HStack {
                Text("Status:")
                    .foregroundStyle(.secondary)
                Text("Trial - \(days) \(days == 1 ? "day" : "days") remaining")
            }

            Text("Enter a license key to activate the full version.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("License Key", text: $licenseKeyInput)
                .textFieldStyle(.roundedBorder)

            if let activationError {
                Text(activationError)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Button(action: activateLicenseFromSettings) {
                if isActivatingFromSettings {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Activate License")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(licenseKeyInput.trimmingCharacters(in: .whitespaces).isEmpty || isActivatingFromSettings)
        } else {
            // Licensed mode (existing UI)
            HStack {
                Text("Key:")
                    .foregroundStyle(.secondary)
                Text(maskedLicenseKey)
                    .monospaced()
            }

            if let lastValidation = settings.lastLicenseValidationDate {
                HStack {
                    Text("Last validated:")
                        .foregroundStyle(.secondary)
                    Text(lastValidation, style: .date)
                }
            }

            if let deactivationError {
                Text(deactivationError)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Button(role: .destructive) {
                deactivateLicense()
            } label: {
                if isDeactivating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Deactivate License")
                }
            }
            .disabled(isDeactivating)
        }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(8)
}
```

- [ ] **Step 3: Add state and method for trial-mode license activation**

Add these new `@State` properties alongside the existing ones:

```swift
@State private var licenseKeyInput = ""
@State private var isActivatingFromSettings = false
@State private var activationError: String?
```

Add this method alongside the existing `deactivateLicense()`:

```swift
private func activateLicenseFromSettings() {
    let key = licenseKeyInput.trimmingCharacters(in: .whitespaces)
    guard !key.isEmpty else { return }

    isActivatingFromSettings = true
    activationError = nil

    Task {
        do {
            let response = try await LicenseService.activate(licenseKey: key)
            LicenseService.persistActivation(
                settings: settings,
                licenseKey: key,
                instanceId: response.id,
                in: modelContext
            )
            dismiss()
            // Notify app to refresh license state — reuse existing deactivation notification
            // which triggers a re-check, or post a new activation notification
            NotificationCenter.default.post(name: .licenseDeactivated, object: nil)
        } catch let error as LicenseError {
            activationError = error.errorDescription
        } catch {
            activationError = "An unexpected error occurred. Please try again."
        }
        isActivatingFromSettings = false
    }
}
```

Note: Reusing `.licenseDeactivated` to trigger a re-check is a shortcut. The app will re-run `checkLicense()`, find the new valid license, and set `isLicensed = true`. If you prefer, rename the notification to `.licenseStateChanged` — but functionally it works the same.

- [ ] **Step 4: Build the full project**

Run: `xcodebuild -scheme BingoBite -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add BingoBite/Views/SettingsSheet.swift
git commit -m "feat: add trial info and license activation to SettingsSheet"
```

---

### Task 7: Integration verification

**Files:** None (manual testing)

- [ ] **Step 1: Clean build**

Run: `xcodebuild -scheme BingoBite -destination 'platform=macOS' clean build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 2: Manual smoke test**

Launch the app and verify:
1. First launch shows "Welcome to BingoBite" with "Start Free Trial" button and license key input
2. Click "Start Free Trial" — app opens to ContentView, sidebar shows "Trial: 14 days remaining"
3. Open Settings — shows trial status and license key input
4. Quit and relaunch — app auto-enters trial mode (days remaining persists)
5. Trial indicator in sidebar is tappable and opens Settings

- [ ] **Step 3: Verify Keychain persistence**

Open Keychain Access and search for `com.digitallysimple.BingoBite.trialStartDate` — should show the trial start date stored as ISO 8601 string.

- [ ] **Step 4: Final commit (if any fixes needed)**

```bash
git add -A
git commit -m "fix: integration fixes for free trial system"
```
