import SwiftUI

public struct ContentView: View {
    @Binding var document: ABCDocument

    public var body: some View {
        Text(document.text.isEmpty ? "Empty document" : document.text)
            .padding()
    }
}

#Preview {
    ContentView(document: .constant(ABCDocument()))
}
