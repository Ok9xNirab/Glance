//
//  AboutView.swift
//  Glance
//

import AppKit
import SwiftUI

enum AppInfo {
    static let name = "Glance"
    static let author = "Istiaq Nirab"
    static let repository = URL(string: "https://github.com/Ok9xNirab/Glance")!
    static let issues = URL(string: "https://github.com/Ok9xNirab/Glance/issues")!
    static let license = URL(string: "https://github.com/Ok9xNirab/Glance/blob/main/LICENSE")!

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }
}

/// The About window (Glance › About Glance), replacing the standard panel.
struct AboutView: View {
    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .padding(.bottom, 10)
            Text(AppInfo.name).font(.system(size: 20, weight: .bold))
            Text(AppInfo.version)
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondaryText)
                .textSelection(.enabled)
                .padding(.top, 2)
            Text("A git client for reviewing what AI agents change across your worktrees.")
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            VStack(spacing: 4) {
                Text("Made by \(AppInfo.author)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.text)
                HStack(spacing: 3) {
                    Text("Free and open source under the")
                    Link("MIT License", destination: AppInfo.license)
                }
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.secondaryText)
            }
            .padding(.top, 14)

            HStack(spacing: 8) {
                Link(destination: AppInfo.repository) {
                    Label("View on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .buttonStyle(.borderedProminent)
                Link(destination: AppInfo.issues) {
                    Label("Report an Issue", systemImage: "exclamationmark.bubble")
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.regular)
            .padding(.top, 16)

            Divider().padding(.vertical, 16)

            VStack(spacing: 3) {
                Text("Built with SwiftUI and tree-sitter.")
                Text("© \(Calendar.current.component(.year, from: .now).formatted(.number.grouping(.never))) \(AppInfo.author)")
                    .padding(.top, 6)
            }
            .font(.system(size: 10.5))
            .foregroundStyle(Palette.secondaryText)
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .frame(width: 360)
        .background(Palette.window)
    }
}

/// "About Glance" in the app menu; opens the About window.
struct AboutCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("About \(AppInfo.name)") { openWindow(id: "about") }
    }
}

#Preview {
    AboutView()
}
