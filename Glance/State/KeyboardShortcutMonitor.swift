//
//  KeyboardShortcutMonitor.swift
//  Glance
//

import AppKit
import SwiftUI

/// Routes plain key presses (J, K, V, arrows) to the model while no text field is being edited.
/// These can't be menu shortcuts, which would also fire while typing.
struct KeyboardShortcutMonitor: ViewModifier {
    let model: AppModel
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    MainActor.assumeIsolated { model.handleKeyDown(event) } ? nil : event
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }
}
