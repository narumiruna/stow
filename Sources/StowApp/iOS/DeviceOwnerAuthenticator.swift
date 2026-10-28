import LocalAuthentication

@MainActor
final class DeviceOwnerAuthenticator: AppAuthenticating {
    private var context: LAContext?
    private var requestID: UUID?

    var availability: AppAuthenticationAvailability {
        let context = LAContext()
        var error: NSError?
        let available = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        let method: String
        switch context.biometryType {
        case .faceID: method = "Face ID"
        case .touchID: method = "Touch ID"
        default: method = "Device Passcode"
        }
        return AppAuthenticationAvailability(
            method: method,
            unavailableReason: available ? nil : "Device authentication is unavailable. \(error?.localizedDescription ?? "Check your device passcode settings and try again.")"
        )
    }

    func authenticate(reason: String) async throws {
        let context = LAContext()
        context.touchIDAuthenticationAllowableReuseDuration = 0
        let requestID = UUID()
        self.context = context
        self.requestID = requestID
        defer {
            if self.context === context {
                self.context = nil
                self.requestID = nil
            }
        }
        let authenticated = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } onCancel: {
            Task { @MainActor [weak self] in self?.invalidate(requestID: requestID) }
        }
        guard authenticated else { throw LAError(.authenticationFailed) }
    }

    func invalidate() {
        context?.invalidate()
        context = nil
        requestID = nil
    }

    private func invalidate(requestID: UUID) {
        guard self.requestID == requestID else { return }
        invalidate()
    }
}
