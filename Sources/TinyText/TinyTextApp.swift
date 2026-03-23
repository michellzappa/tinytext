import SwiftUI
import AppKit
import TinyKit
import UniformTypeIdentifiers

// MARK: - FocusedValue key for per-window AppState

struct FocusedAppStateKey: FocusedValueKey {
    typealias Value = AppState
}

extension FocusedValues {
    var appState: AppState? {
        get { self[FocusedAppStateKey.self] }
        set { self[FocusedAppStateKey.self] = newValue }
    }
}

// MARK: - App

@main
struct TinyTextApp: App {
    @NSApplicationDelegateAdaptor(TinyAppDelegate.self) var appDelegate
    @FocusedValue(\.appState) private var activeState

    var body: some Scene {
        WindowGroup(id: "editor") {
            WindowContentView()
                .frame(minWidth: 600, minHeight: 400)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                NewWindowButton()
            }

            CommandGroup(replacing: .appInfo) {
                Button("About TinyText") {
                    NSApp.orderFrontStandardAboutPanel()
                }
                Button("Welcome to TinyText") {
                    NotificationCenter.default.post(name: .showWelcome, object: nil)
                }
                Divider()
                Button("Feedback\u{2026}") {
                    NSWorkspace.shared.open(URL(string: "https://tinysuite.app/support.html")!)
                }
                Button("TinySuite Website") {
                    NSWorkspace.shared.open(URL(string: "https://tinysuite.app")!)
                }
            }

            CommandGroup(replacing: .help) {
                Button("TinyText on GitHub") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/michellzappa/tinytext")!)
                }
            }

            CommandGroup(after: .newItem) {
                Button("New File") {
                    activeState?.newFile()
                }
                .keyboardShortcut("n", modifiers: .command)

                OpenFileButton()

                OpenFolderButton()

                RecentFilesMenu { url in
                    activeState?.selectFile(url)
                }

                Divider()

                Button("Save") {
                    activeState?.save()
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Save As\u{2026}") {
                    activeState?.saveAs()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Divider()

                ExportPDFButton()
                ExportHTMLButton()

                Divider()

                CopyRichTextButton()
            }

            CommandGroup(replacing: .sidebar) {
                Button("Toggle Sidebar") {
                    NotificationCenter.default.post(name: .toggleSidebar, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
            }
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let toggleSidebar = Notification.Name("toggleSidebar")
}

// MARK: - Window Content

struct WindowContentView: View {
    @State private var state = AppState()
    @State private var showWelcome = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        ContentView(state: state, columnVisibility: $columnVisibility)
            .defaultAppBanner(appName: "TinyText", associations: [
                FileTypeAssociation(utType: .plainText, label: ".txt files"),
            ])
            .navigationTitle(state.selectedFile?.lastPathComponent ?? "TinyText")
            .focusedSceneValue(\.appState, state)
            .onAppear {
                if !TinyAppDelegate.pendingFiles.isEmpty {
                    let files = TinyAppDelegate.pendingFiles
                    TinyAppDelegate.pendingFiles.removeAll()
                    openFiles(files)
                } else if WelcomeState.isFirstLaunch {
                    showWelcome = true
                } else {
                    state.restoreLastFolder()
                }

                TinyAppDelegate.onOpenFiles = { [weak state] urls in
                    guard let state else { return }
                    openFilesInState(urls, state: state)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
                withAnimation {
                    columnVisibility = columnVisibility == .detailOnly ? .automatic : .detailOnly
                }
            }
            .welcomeSheet(
                isPresented: $showWelcome,
                appName: "TinyText",
                subtitle: "A clean, native plain text editor for macOS.",
                features: [
                    (icon: "doc.plaintext", title: "Plain Text", description: "Open any text file \u{2014} .txt, .cfg, .conf, .ini, and more"),
                    (icon: "keyboard", title: "Keyboard-First", description: "Navigate and edit with powerful shortcuts"),
                    (icon: "magnifyingglass", title: "Find & Replace", description: "Search across your file with Cmd+F"),
                    (icon: "sparkles", title: "AI Built In", description: "Edit and ask with Cmd+K"),
                ],
                onOpenFolder: { state.openFolder() },
                onOpenFile: { state.openFile() },
                onDismiss: { state.restoreLastFolder() }
            )
            .background(WindowCloseGuard(state: state))
    }

    private func openFiles(_ urls: [URL]) {
        openFilesInState(urls, state: state)
    }

    private func openFilesInState(_ urls: [URL], state: AppState) {
        guard let url = urls.first else { return }
        let folder = url.deletingLastPathComponent()
        if state.folderURL != folder {
            state.setFolder(folder)
        }
        state.selectFile(url)
        columnVisibility = .detailOnly
    }
}

// MARK: - Menu Buttons

struct OpenFileButton: View {
    @FocusedValue(\.appState) private var state

    var body: some View {
        Button("Open File\u{2026}") {
            state?.openFile()
        }
        .keyboardShortcut("o", modifiers: .command)
    }
}

struct OpenFolderButton: View {
    @FocusedValue(\.appState) private var state

    var body: some View {
        Button("Open Folder\u{2026}") {
            state?.openFolder()
        }
        .keyboardShortcut("o", modifiers: [.command, .shift])
    }
}

struct NewWindowButton: View {
    @Environment(\.openWindow) var openWindow

    var body: some View {
        Button("New Window") {
            openWindow(id: "editor")
        }
        .keyboardShortcut("n", modifiers: [.command, .shift])
    }
}

// MARK: - Export Buttons

struct ExportPDFButton: View {
    @FocusedValue(\.appState) private var state

    var body: some View {
        Button("Export as PDF\u{2026}") {
            guard let state else { return }
            let name = state.selectedFile?.lastPathComponent ?? "output.txt"
            let html = ExportManager.wrapHTML(
                body: "<pre>\(ExportManager.escapeHTML(state.content))</pre>",
                title: name
            )
            ExportManager.exportPDF(html: html, suggestedName: name)
        }
        .keyboardShortcut("e", modifiers: [.command, .shift])
        .disabled(state == nil)
    }
}

struct ExportHTMLButton: View {
    @FocusedValue(\.appState) private var state

    var body: some View {
        Button("Export as HTML\u{2026}") {
            guard let state else { return }
            let name = state.selectedFile?.lastPathComponent ?? "output.txt"
            let html = ExportManager.wrapHTML(
                body: "<pre>\(ExportManager.escapeHTML(state.content))</pre>",
                title: name
            )
            ExportManager.exportHTML(html: html, suggestedName: name)
        }
        .disabled(state == nil)
    }
}

struct CopyRichTextButton: View {
    @FocusedValue(\.appState) private var state

    var body: some View {
        Button("Copy as Rich Text") {
            guard let state else { return }
            let html = "<pre>\(ExportManager.escapeHTML(state.content))</pre>"
            ExportManager.copyAsRichText(body: html)
        }
        .keyboardShortcut("c", modifiers: [.command, .option])
        .disabled(state == nil)
    }
}
