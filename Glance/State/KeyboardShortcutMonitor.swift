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
    /// The window this view is in. Every window's monitor sees every key press, so each handles only its own.
    @State private var window = WindowReference()

    func body(content: Content) -> some View {
        content
            .background(WindowReader(reference: window))
            .onAppear {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [window] event in
                    guard event.window != nil, event.window === window.window else { return event }
                    return MainActor.assumeIsolated { model.handleKeyDown(event) } ? nil : event
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }
}

private final class WindowReference {
    weak var window: NSWindow?
}

private struct WindowReader: NSViewRepresentable {
    let reference: WindowReference

    func makeNSView(context: Context) -> NSView {
        let view = WindowTrackingView()
        view.reference = reference
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}

    private final class WindowTrackingView: NSView {
        var reference: WindowReference?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            reference?.window = window
        }
    }
}
