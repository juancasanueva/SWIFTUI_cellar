//
//  AboutView.swift
//  cellar
//

import SwiftUI

/// The app's user-facing name, read from the bundle so the About window, its
/// title and the menu item can never drift from the Info.plist display name.
enum AppIdentity {
    static var name: String {
        let info = Bundle.main.infoDictionary
        return info?["CFBundleDisplayName"] as? String
            ?? info?["CFBundleName"] as? String
            ?? "Cellar"
    }
}

/// The About window: identity, version, credits and links on the design's own
/// dark cards, replacing the system About panel via `AboutCommands`.
struct AboutView: View {
    @Environment(ThemeStore.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            hero
            infoCard
            SectionHeader("Credits")
                .padding(.leading, 4)
            creditsCard
            linksCard
            footer
        }
        .padding(EdgeInsets(top: 30, leading: 22, bottom: 18, trailing: 22))
        .frame(width: 340)
        .background(Theme.windowBackground)
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(AppIdentity.name)
                    .font(.system(size: 17, weight: .semibold))
                    .kerning(-0.3)
                    .foregroundStyle(Theme.textPrimary)
                Text("Keep your Homebrew tidy, healthy and up to date — in one calm place.")
                    .font(.system(size: 11.5))
                    .lineSpacing(2)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 3)
        }
        .padding(EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard(radius: 12)
    }

    private var infoCard: some View {
        card {
            row("Application", value: AppIdentity.name)
            HairlineDivider()
            row("Version", value: version, mono: true)
        }
    }

    private var creditsCard: some View {
        card {
            row("Developer", value: "Juan Casanueva")
            HairlineDivider()
            row("Tester", value: "Sebastián Casanueva")
            HairlineDivider()
            row("Tester", value: "Rodrigo Casanueva")
        }
    }

    private var linksCard: some View {
        card {
            linkRow("Web page", label: "juancasanueva.vercel.app",
                    url: URL(string: "https://juancasanueva.vercel.app")!)
            HairlineDivider()
            linkRow("Email", label: "juancasanueva@gmail.com",
                    url: URL(string: "mailto:juancasanueva@gmail.com")!)
        }
    }

    private var footer: some View {
        VStack(spacing: 3) {
            Text("© \(String(Calendar.current.component(.year, from: .now))) Juan Casanueva")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
            Text("Made with care using SwiftUI")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.base)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    private func card(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .themeCard(radius: 12)
    }

    private func row(_ label: String, value: String, mono: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 12)
            Text(value)
                .font(mono ? Theme.mono(11.5) : .system(size: 12))
                .foregroundStyle(mono ? Theme.textMono : Theme.textSecondary)
        }
        .padding(EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14))
    }

    private func linkRow(_ label: String, label value: String, url: URL) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 12)
            Link(destination: url) {
                HStack(spacing: 4) {
                    Text(value)
                        .font(.system(size: 12))
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 10))
                }
                .foregroundStyle(theme.base)
            }
        }
        .padding(EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 14))
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }
}

/// Replaces the system About panel with the design's own window.
struct AboutCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About \(AppIdentity.name)") { openWindow(id: "about") }
        }
    }
}

#Preview {
    AboutView().environment(ThemeStore())
}
