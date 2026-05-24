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
        }
        if let userID = keychain.retrieve(key: userIDKey) {
            isAuthenticated = true
            _ = keychain.save(key: userIDKey, value: userID)
        }
    }

    // MARK: - Sign in with Apple

    func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else { return }

            let userID = credential.user
            let _ = keychain.save(key: userIDKey, value: userID)

            // Apple only provides the name on FIRST sign-in
            if let fullName = credential.fullName {
                let first = fullName.givenName ?? ""
                let name = first.isEmpty ? "there" : first
                userName = name
                let _ = keychain.save(key: userNameKey, value: name)
            } else if userName.isEmpty {
                // Returning user — name was stored previously
                userName = keychain.retrieve(key: userNameKey) ?? "there"
            }

            isAuthenticated = true

        case .failure:
            // User cancelled or error — don't block, they can retry
            break
        }
    }

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
