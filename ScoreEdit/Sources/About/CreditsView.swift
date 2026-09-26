//
//  CreditsView.swift
//  ScoreEdit
//
//  Created by Stephen Beitzel on 9/25/26.
//

import SwiftUI
import Textual

struct CreditsView: View {
    private let licensesText: String = {
        guard
            let url = Bundle.module.url(forResource: "LICENSES", withExtension: "md"),
            let markdown = try? String(contentsOf: url, encoding: .utf8)
        else {
            return String(localized: .kerrLicensesUnavailable)
        }
        return markdown
    }()

    var body: some View {
        TabView {
            Tab(.ktabLicences, systemImage: "info.circle.text.page") {
                ScrollView {
                    StructuredText(markdown: licensesText)
                        .textual.structuredTextStyle(.gitHub)
                        .textual.textSelection(.disabled)
                        .textual.overflowMode(.scroll)
                }
                .padding()
            }
        }
    }
}

#Preview {
    CreditsView()
}
