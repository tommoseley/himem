import Foundation
import AuthenticationServices

@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published var isAuthenticated: Bool = false
    @Published var userName: String = ""

    private let keychain = KeychainService.shared
    private let userIDKey = "appleUserID"
    private let userNameKey = "userName"
    /// UserDefaults key for the "user finished the permission wizard
    /// on this install" flag. UserDefaults is wiped on app uninstall
    /// by iOS reliably (unlike Keychain, which we've observed
    /// persisting across uninstall on real devices despite the
    /// ThisDeviceOnly access class). That makes UserDefaults the
    /// right signal for "should the wizard show on next launch."
    private let wizardCompletedKey = "wizardCompletedOnThisInstall.v1"
    /// iCloud Key-Value Store key for the user's display name.
    /// Survives an app reinstall on the same Apple ID — Sign in with
    /// Apple only returns `fullName` on the FIRST sign-in ever for a
    /// given Apple ID + bundle ID combination, so without an iCloud-
    /// scoped sidecar the user has to retype their name after every
    /// uninstall+reinstall. NSUbiquitousKeyValueStore is the 4KB
    /// iCloud-backed dictionary designed exactly for this case — no
    /// CloudKit container needed, no schema, no first-launch sync
    /// delay. The Keychain (ThisDeviceOnly) stays the per-device
    /// authoritative store for the userID itself.
    private let kvUserNameKey = "userName.v1"
    private var kvStore: NSUbiquitousKeyValueStore { .default }

    init() {
        loadStoredCredentials()
    }

    // MARK: - Stored State

    /// True if the user is signed in with Apple on this device.
    /// Backed by the Keychain `appleUserID` entry. Used by the auth /
    /// credential-verification flow, NOT by the wizard gate — Apple
    /// Sign In is step 1 of 7 in the wizard, and we don't want
    /// the gate to flip true while the user is mid-flow. Use
    /// `hasCompletedOnboardingWizard` for the gate.
    var hasCompletedOnboarding: Bool {
        keychain.retrieve(key: userIDKey) != nil
    }

    /// True if the user finished the PermissionWizard end-to-end on
    /// the current install. Backed by UserDefaults (wiped on
    /// uninstall, persistent across force-quit). This is the
    /// canonical signal for "should the wizard show on next cold
    /// launch." Survives force-quit + relaunch within the same
    /// install; reset on uninstall so reinstall users see the
    /// wizard fresh and re-grant permissions (which iOS makes them
    /// re-grant anyway).
    var hasCompletedOnboardingWizard: Bool {
        UserDefaults.standard.bool(forKey: wizardCompletedKey)
    }

    /// Called once by `PermissionWizardView` from its `onComplete`
    /// callback. Idempotent — safe to call multiple times if for
    /// some reason the user replays the wizard via the DEBUG reset.
    func markOnboardingWizardComplete() {
        UserDefaults.standard.set(true, forKey: wizardCompletedKey)
    }

    /// Re-reads the Keychain into `isAuthenticated` / `userName`.
    /// Called by `MemoryStreamApp` on `scenePhase → .active` so an
    /// AuthService instance that was created during a locked-device
    /// background launch (where the Keychain was unreadable, leaving
    /// `isAuthenticated=false`) recovers as soon as the user
    /// foregrounds the app. Idempotent: a no-op when state is
    /// already correct.
    func refresh() {
        loadStoredCredentials()
    }

    private func loadStoredCredentials() {
        if let name = keychain.retrieve(key: userNameKey) {
            userName = name
            // In-place migration: re-saving rewrites the entry with
            // the current `KeychainService` access class
            // (`AfterFirstUnlockThisDeviceOnly`). Entries written
            // under the previous `WhenUnlockedThisDeviceOnly` class
            // get upgraded the first time we successfully read them.
            _ = keychain.save(key: userNameKey, value: name)
            // Keep the iCloud KV sidecar in sync — propagates the
            // Keychain value to other Apple-ID-paired installs and
            // future reinstalls of this app.
            kvStore.set(name, forKey: kvUserNameKey)
        } else if let kvName = kvStore.string(forKey: kvUserNameKey),
                  !kvName.isEmpty {
            // Reinstall path: Keychain wiped by iOS on uninstall, but
            // the iCloud KV sidecar from the previous install (or a
            // companion device) still holds the name. Restore it to
            // both the published state and this device's Keychain.
            userName = kvName
            _ = keychain.save(key: userNameKey, value: kvName)
        }
        if let userID = keychain.retrieve(key: userIDKey) {
            isAuthenticated = true
            _ = keychain.save(key: userIDKey, value: userID)
        }
    }

    /// Writes `userName` to the @Published property, Keychain, and
    /// iCloud KV in one call. Use this from any code that mutates the
    /// user's display name (Sign in with Apple result, wizard name
    /// edit, future profile-edit surface) so all three stores stay in
    /// sync. Empty input is rejected.
    func setUserName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        userName = trimmed
        _ = keychain.save(key: userNameKey, value: trimmed)
        kvStore.set(trimmed, forKey: kvUserNameKey)
        kvStore.synchronize() // best-effort immediate push; iOS still owns the schedule
    }

    // MARK: - Sign in with Apple

    func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else { return }

            let userID = credential.user
            let _ = keychain.save(key: userIDKey, value: userID)

            // Apple only provides the name on FIRST sign-in. Subsequent
            // sign-ins return fullName=nil even for the same user — by
            // design, privacy-protective. Apple's "first" determination
            // is per-Apple-ID + per-bundle-ID, not per-install: even
            // after Keychain wipe, Apple won't re-share the name unless
            // the user explicitly stops using Apple ID for HiMem in
            // iOS Settings. The iCloud KV sidecar (see `setUserName`)
            // covers most reinstall cases so the name still pre-fills.
            //
            // When neither Apple, Keychain, nor the KV sidecar has a
            // name, leave userName empty. The wizard's Page 1b shows
            // an empty editable field with placeholder copy; the user
            // types their preferred name and Continue commits it via
            // setUserName. NEVER store "there" as the userName — that
            // string is a display-time greeting fallback only, used by
            // LaunchScreenView.greeting when name.isEmpty.
            if let fullName = credential.fullName {
                let first = (fullName.givenName ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !first.isEmpty {
                    setUserName(first)
                }
            } else if userName.isEmpty {
                if let stored = keychain.retrieve(key: userNameKey),
                   !stored.isEmpty, stored != "there" {
                    userName = stored
                } else if let kvName = kvStore.string(forKey: kvUserNameKey),
                          !kvName.isEmpty {
                    setUserName(kvName)
                }
                // If we got here, no name source had anything. userName
                // stays empty; the wizard's name step handles that case.
            }

            isAuthenticated = true

        case .failure:
            // User cancelled or error — don't block, they can retry
            break
        }
    }

    // MARK: - DEBUG · onboarding reset

    #if DEBUG
    /// Clears Keychain (userID, userName) and the iCloud KV sidecar
    /// so the next cold launch enters the PermissionWizardView fresh.
    /// Resets in-memory state so the same Settings UI that triggered
    /// the reset doesn't keep showing the old user. Real iOS-system
    /// permission grants (mic, speech, photos, camera, location,
    /// notifications) are NOT reset — those live in iOS Settings and
    /// no app-level API can clear them. To test the actual prompts,
    /// use Settings → General → Transfer or Reset iPhone → Reset →
    /// Reset Location & Privacy.
    ///
    /// IMPORTANT: `@State private var onboardingComplete` in
    /// `MemoryStreamApp` is captured at App-struct creation, so this
    /// reset does NOT affect the current session — the user must
    /// force-quit and re-launch HiMem for the wizard to actually show.
    func debugResetOnboardingState() {
        _ = keychain.delete(key: userIDKey)
        _ = keychain.delete(key: userNameKey)
        kvStore.removeObject(forKey: kvUserNameKey)
        kvStore.synchronize()
        UserDefaults.standard.removeObject(forKey: wizardCompletedKey)
        isAuthenticated = false
        userName = ""
    }
    #endif

    // MARK: - Credential Check

    func verifyCredentialState() {
        guard let userID = keychain.retrieve(key: userIDKey) else { return }
        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { state, _ in
            Task { @MainActor in
                if state == .revoked {
                    self.isAuthenticated = false
                    let _ = self.keychain.delete(key: self.userIDKey)
                }
            }
        }
    }
}
