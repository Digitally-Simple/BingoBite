# Free Trial System Design

## Overview

Add a 14-day free trial to BingoBite. Users explicitly opt in by clicking "Start Free Trial" on the gate screen. After 14 days, the app is hard-gated until a license key is entered. Trial state is stored in both SwiftData and the macOS Keychain to prevent casual resets via app data deletion.

## Decisions

- **Trial trigger:** Explicit opt-in (user clicks "Start Free Trial")
- **Duration:** 14 days
- **Tamper resistance:** Keychain + SwiftData dual storage; Keychain is authoritative
- **Expiration behavior:** Hard gate — app is completely unusable without a license key
- **In-trial indicator:** Subtle "Trial: X days remaining" text at the bottom of the sidebar, tappable to open Settings
- **Expired gate screen:** License key input only (purchase link placeholder for later)

## Components

### 1. TrialService (`BingoBite/Services/TrialService.swift`)

New `enum TrialService` (matches `LicenseService` style) that owns all trial logic.

**TrialStatus enum:**
```swift
enum TrialStatus {
    case notStarted
    case active(daysRemaining: Int)
    case expired
}
```

**Constants:**
- `trialDurationDays = 14`
- Keychain service key: bundle ID + `".trialStartDate"`

**Methods:**
- `startTrial(settings:context:)` — Writes current date to `AppSettings.trialStartDate` (SwiftData) and macOS Keychain (Security framework). Called when user clicks "Start Free Trial".
- `trialStatus(settings:)` — Returns `TrialStatus`. Uses Keychain as source of truth, falls back to SwiftData.
  - If SwiftData has no date but Keychain does → restores from Keychain to SwiftData
  - If Keychain has no date but SwiftData does → writes SwiftData value to Keychain
  - Computes days remaining from the stored start date

**Keychain implementation:**
- Uses `SecItemAdd` / `SecItemCopyMatching` / `SecItemUpdate` from the Security framework
- Service: `"com.digitallysimple.BingoBite.trialStartDate"`
- Account: `"trial"`
- Stores the date as ISO 8601 string encoded to Data

### 2. AppSettings Changes (`BingoBite/Models/AppSettings.swift`)

Add one optional field:
```swift
var trialStartDate: Date? = nil
```

Lightweight SwiftData migration happens automatically (optional with default value).

### 3. LicenseGateView Changes (`BingoBite/Views/LicenseGateView.swift`)

The existing view gains trial awareness via two new parameters:
```swift
var trialExpired: Bool        // true if trial has ended
var onTrialStarted: () -> Void // callback when user starts trial
```

**Three visual states:**

1. **New user (`!trialExpired`, no stored key):**
   - "Welcome to BingoBite"
   - "Start your 14-day free trial, or enter a license key."
   - "Start Free Trial" button (borderedProminent, primary)
   - License key input + "Activate" button (secondary)

2. **Expired trial (`trialExpired`):**
   - "Welcome to BingoBite"
   - "Your free trial has ended. Enter a license key to continue."
   - License key input + "Activate" button only (no trial button)

3. **Returning licensed user (existing behavior):**
   - Pre-fills stored key, shows Activate — unchanged

### 4. BingoBiteApp Changes (`BingoBite/BingoBiteApp.swift`)

**New state properties:**
```swift
@State private var isTrialing = false
@State private var trialDaysRemaining = 0
@State private var trialExpired = false
```

**Updated `checkLicense()` flow:**
1. Check license key validity (existing flow, unchanged)
2. If valid license → `isLicensed = true`, done
3. If no valid license → call `TrialService.trialStatus(settings:)`
   - `.active(let days)` → `isTrialing = true`, `trialDaysRemaining = days`
   - `.expired` → `trialExpired = true`
   - `.notStarted` → default state (gate shows trial button)

**Updated body:**
```swift
if !hasCheckedLicense {
    ProgressView("Checking license...")
} else if isLicensed || isTrialing {
    ContentView()  // pass trialDaysRemaining if trialing
} else {
    LicenseGateView(
        trialExpired: trialExpired,
        onActivated: { isLicensed = true },
        onTrialStarted: {
            isTrialing = true
            trialDaysRemaining = 14
        }
    )
}
```

Existing `licenseDeactivated` notification listener unchanged.

### 5. SettingsSheet Changes (`BingoBite/Views/SettingsSheet.swift`)

**When trialing** (license key is empty but user has access):
- GroupBox shows "Trial: X days remaining" in secondary text
- License key input + "Activate" button for mid-trial upgrade
- No deactivate button

**When licensed** (existing behavior): Unchanged.

`trialDaysRemaining` passed as a parameter from ContentView.

### 6. Sidebar Trial Indicator

In `ContentView`, at the bottom of the sidebar:
- Small `.caption` text: `"Trial: 12 days remaining"`
- `.secondary` foreground color
- Tappable — opens Settings sheet
- Only visible when `isTrialing` (not shown for licensed users)

## Files Changed

| File | Change |
|------|--------|
| `BingoBite/Services/TrialService.swift` | **New** — trial logic + Keychain persistence |
| `BingoBite/Models/AppSettings.swift` | Add `trialStartDate: Date?` |
| `BingoBite/BingoBiteApp.swift` | Add trial state, update `checkLicense()`, update body |
| `BingoBite/Views/LicenseGateView.swift` | Add trial states (new user, expired), `onTrialStarted` callback |
| `BingoBite/Views/SettingsSheet.swift` | Show trial info when trialing, license key input for upgrade |
| `BingoBite/Views/ContentView.swift` | Pass trial state, add sidebar trial indicator |

## Out of Scope

- Purchase link (to be added later when store is set up)
- Server-side trial tracking
- Feature-limited / read-only modes
- Escalating reminders near expiration
