//
//  AboutView.swift
//  ScoreEdit
//
//  Created by Stephen Beitzel on 9/25/26.
//

import SwiftUI

struct AboutView: View {
    @Environment(\.openWindow) private var openWindow

    private let appIconImage: Image = {
        let images = ScoreEditImages(name: .kAppIconImage)
        return Image(decorative: images)
    }()

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "N/A"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "N/A"
    }

    private var copyrightYear: String {
        let buildYearString = Bundle.main.infoDictionary?["QBBuildYear"] as? String ?? "2026"
        let buildYear = Int(buildYearString) ?? 2026
        var yearString: String
        if buildYear > 2026 {
            yearString = "2026 - \(buildYear)"
        } else {
            yearString = "2026"
        }
        return yearString
    }

    private var developerWebsite: URL {
        URL(string: "https://www.coprosperitysphere.com/apps/ScoreEdit/")!
    }

    var body: some View {
        VStack(spacing: 14) {
            appIconImage
                .resizable().scaledToFit()
                .frame(width: 80)
            Text(.kappName)
                .font(.title)
            VStack(spacing: 6) {
                Text(.kversion(version: appVersion, build: appBuild))
                Text(.kcopyright(year: copyrightYear))
            }
            .font(.callout)
            Link(
                .kbuttonAppWebsite,
                destination: developerWebsite
            )
            Button(.kbuttonCredits) {
                openWindow(id: .kWID_credits)
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 260)
    }
}

#Preview {
    AboutView()
}
