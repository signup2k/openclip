// AIActionSync.swift
// OpenClip
//
// Keeps AIServiceManager's AI presets registered in the ActionCoordinator as individual
// `AIAction`s, so every preset shows up as a searchable entry in the action-search palette and
// as its own row in the popup and Preferences → Actions. Also registers the AI Tools settings row.
// Reconciles the registered set whenever the preset list
// changes; the title snapshot on `AIAction` is refreshed by re-registering on any content change.
import Foundation
import Core

@MainActor
public final class AIActionSync {
    public static let shared = AIActionSync()

    private let coordinator = ActionCoordinator.shared
    private var registeredIDs: Set<String> = []
    private var lastFingerprint: [String] = []
    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: .aiActionPresetsDidChange,
            object: AIServiceManager.shared,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sync()
            }
        }
        sync()
        coordinator.register(action: AIToolsAction())
    }

    private func sync() {
        let presets = AIServiceManager.shared.presets
        let fingerprint = presets.map { "\($0.id)|\($0.title)|\($0.prompt)|\($0.isEnabled)" }
        guard fingerprint != lastFingerprint else { return }

        let currentIDs = Set(presets.map { AIAction(presetID: $0.id, title: $0.title).id })
        for id in registeredIDs.subtracting(currentIDs) {
            coordinator.unregister(actionID: id)
        }
        for preset in presets {
            coordinator.register(action: AIAction(presetID: preset.id, title: preset.title))
        }

        registeredIDs = currentIDs
        lastFingerprint = fingerprint
    }
}
