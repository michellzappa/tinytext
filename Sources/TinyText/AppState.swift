import Foundation
import AppKit
import TinyKit

@Observable
final class AppState: FileState {
    init() {
        super.init(
            bookmarkKey: "lastFolderBookmarkText",
            defaultExtension: "txt",
            supportedExtensions: ["txt", "text", "cfg", "conf", "ini", "config", "properties", "rc", "env"]
        )
    }

    // MARK: - Spotlight

    private static let spotlightDomain = "com.tinyapps.tinytext.files"

    override func didOpenFile(_ url: URL) {
        SpotlightIndexer.index(file: url, content: content, domainID: Self.spotlightDomain)
    }

    override func didSaveFile(_ url: URL) {
        didOpenFile(url)
    }
}
