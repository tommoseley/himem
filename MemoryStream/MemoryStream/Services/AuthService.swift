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

    private func loadStoredCredentials() {
        if let name = keychain.retrieve(key: userNameKey) {
            userName = name
        }
        if keychain.retrieve(key: userIDKey) != nil {
            isAuthenticated = true
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
