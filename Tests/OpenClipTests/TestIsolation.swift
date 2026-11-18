import Core

/// Clears the shared app state used by tests that exercise singleton entry points.
@MainActor
enum TestIsolation {
    static func reset() {
        ActionRegistry.shared.reset()
        ActionCustomizationManager.shared.reset()
        RuleEngine.shared.reset()
        ExtensionManager.shared.reset()
    }
}
