# Authentication & Security — Design Plan

## Why

Hi Mem stores personal thoughts, observations, and memories. Users need to trust that:
1. Nobody who picks up their phone can read their journal
2. Their identity is tied to their Apple account (not a username/password)
3. Their data is theirs — authenticated for future sync

## Two Layers

### Layer 1: Sign in with Apple (Identity)
**When:** First launch only (onboarding)
**What it gives us:**
- User's first name (for greeting — no "What should we call you?" prompt needed)
- Stable user identifier (persists across app reinstalls)
- Private relay email (for account recovery if needed)
- JWT credential (for future API auth against `api.thecombine.ai`)

**Flow:**
1. App launches for the first time → onboarding screen
2. Brief "Hi Mem is your private memory stream" intro
3. "Continue with Apple" button (ASAuthorizationAppleIDButton)
4. Apple consent sheet appears → user approves
5. App receives: name, user ID, identity token
6. Store user ID + name in Keychain
7. Proceed to splash screen → feed

**What we store:**
- `userName` — first name, in Keychain
- `appleUserID` — stable identifier, in Keychain
- `isAuthenticated` — flag in UserDefaults (fast check at launch)
- Identity token NOT stored long-term (refreshed when needed for API)

**Returning users:**
- On subsequent launches, check `appleUserID` exists in Keychain
- Verify credential state: `ASAuthorizationAppleIDProvider().getCredentialState(forUserID:)`
- If revoked (user removed the app from their Apple ID), show sign-in again

### Layer 2: Biometric Lock (Local Security)
**When:** Every app launch (after first sign-in)
**What it does:** Prevents unauthorized access to the journal

**Flow:**
1. App launches → splash screen shows (wordmark visible)
2. Face ID / Touch ID prompt appears over the splash
3. Success → choreography continues → feed
4. Failure → "Try Again" or "Enter Passcode" fallback
5. No biometric enrolled → fall through to app (don't lock users out)

**Implementation:**
- `LAContext().evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)`
- Fallback: `.deviceOwnerAuthentication` (includes device passcode)
- Prompt: "Unlock your memories"
- Fires BEFORE CloudKit sync — user sees the wordmark while authenticating
- If biometric succeeds, the splash choreography begins

**Settings:**
- "Require Face ID" toggle in Settings (default: ON)
- Users can disable if they don't want the friction
- Stored in UserDefaults: `requireBiometric`

## Onboarding Sequence (First Launch)

```
1. iOS Launch Screen (storyboard — wordmark on warm background)
2. OnboardingView:
   a. Welcome screen — "Your memories, private and secure"
   b. Sign in with Apple button
   c. Apple consent sheet
   d. Name + ID received
3. Splash screen (now with personalized greeting)
4. Feed (empty — first time)
```

## Returning Launch Sequence

```
1. iOS Launch Screen (storyboard)
2. Splash screen appears
3. Face ID prompt overlays splash
4. Success → choreography + CloudKit sync
5. Feed
```

## Files to Create
- `Views/Onboarding/OnboardingView.swift` — welcome + Sign in with Apple
- `Services/AuthService.swift` — Sign in with Apple handling, Keychain storage, biometric check

## Files to Modify
- `App/MemoryStreamApp.swift` — check auth state, show onboarding or biometric gate
- `Views/Launch/LaunchScreenView.swift` — integrate biometric prompt timing
- `Views/Components/SettingsView.swift` — "Require Face ID" toggle
- `Services/Storage/KeychainService.swift` — store user ID + name (already exists)

## Frameworks
- `AuthenticationServices` — Sign in with Apple
- `LocalAuthentication` — Face ID / Touch ID
- `Security` — Keychain (already imported)

## Privacy Posture
- No passwords, no email collection
- Apple's private relay protects the user's real email
- Biometric data never leaves the device (Secure Enclave)
- Journal data protected at rest by iOS Data Protection
- CloudKit data encrypted in transit and at rest
- Future: end-to-end encryption option (encrypt before CloudKit upload)

## What We're NOT Building
- No custom account system (no username/password)
- No social login (Google, Facebook)
- No server-side session management (yet — deferred to API sync work)
- No multi-user support (single Apple ID = single user)
- No remote wipe (deferred)

## Acceptance Criteria
- First launch: user signs in with Apple, name appears in greeting
- Subsequent launches: Face ID prompt before journal access
- Face ID failure: passcode fallback works
- No biometric: app still accessible (toggle off by default for devices without Face ID)
- Settings: user can toggle biometric lock on/off
- Credential revocation: if user removes app from Apple ID, re-prompts sign-in
