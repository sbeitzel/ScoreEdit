import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let abcNotation = UTType(exportedAs: "com.qbcps.abc-notation")
}

struct ABCDocument: FileDocument {
    var text: String

    init(text: String = "") {
        self.text = text
    }

    static var readableContentTypes: [UTType] {
        var types: [UTType] = [.abcNotation, .plainText]
        // The .abc extension is also claimed by Alembic Scene (3D graphics format).
        // Accept whatever the system maps ".abc" to so files aren't grayed out in the picker.
        if let abcByExtension = UTType(filenameExtension: "abc"), !types.contains(abcByExtension) {
            types.append(abcByExtension)
        }
        return types
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(text.utf8)
        return FileWrapper(regularFileWithContents: data)
    }
}
