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

    var hasCompletedOnboarding: Bool {
        keychain.retrieve(key: userIDKey) != nil
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
            // design, privacy-protective. The iCloud KV sidecar (see
            // `setUserName`) survives uninstall+reinstall on the same
            // Apple ID so reinstalls don't lose the name.
            if let fullName = credential.fullName {
                let first = fullName.givenName ?? ""
                let name = first.isEmpty ? "there" : first
                setUserName(name)
            } else if userName.isEmpty {
                // Returning user, no name in @Published yet — try
                // Keychain, then KV sidecar, then fall back.
                if let stored = keychain.retrieve(key: userNameKey),
                   !stored.isEmpty {
                    userName = stored
                } else if let kvName = kvStore.string(forKey: kvUserNameKey),
                          !kvName.isEmpty {
                    setUserName(kvName)
                } else {
                    userName = "there"
                }
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
