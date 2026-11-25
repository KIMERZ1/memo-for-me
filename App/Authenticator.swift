import LocalAuthentication

protocol Authenticator {
    func authenticate(reason: String) async -> Bool
}

/// Touch ID, falling back to the Mac password. Fails closed: the only case that is allowed without
/// authentication is a Mac with no passcode set at all (nothing to authenticate against; the note is still
/// encrypted at rest with a device-only Keychain key). Every other error denies access.
struct LAAuthenticator: Authenticator {
    func authenticate(reason: String) async -> Bool {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            return err?.code == LAError.passcodeNotSet.rawValue
        }
        return (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}
