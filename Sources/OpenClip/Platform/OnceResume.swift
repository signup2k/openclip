import Foundation

/// Guarantees a `CheckedContinuation` is resumed exactly once when two or more racing producers
/// (a worker and a deadline watchdog) may both try to settle it. Mirrors the TimeoutFlag/OnceGate
/// lock-guarded pattern used across the runtimes.
final class OnceResume<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    @discardableResult
    func resume(_ continuation: CheckedContinuation<T, Never>, with value: T) -> Bool {
        lock.lock()
        if resumed {
            lock.unlock()
            return false
        }
        resumed = true
        lock.unlock()
        continuation.resume(returning: value)
        return true
    }
}
