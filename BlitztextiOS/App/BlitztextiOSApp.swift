import SwiftUI

@main
struct BlitztextiOSApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = BlitztextDictationModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .onAppear {
                    model.handleKeyboardDictationRequestIfNeeded()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        model.handleKeyboardDictationRequestIfNeeded()
                    } else if phase == .background {
                        model.endSessionIfFinished()
                    }
                }
                .onOpenURL { url in
                    guard url.scheme == "blitztext" else { return }
                    if url.host == "record" || url.path == "/record" {
                        let isKeyboard = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                            .queryItems?
                            .contains(where: { $0.name == "source" && $0.value == "keyboard" }) == true
                        if isKeyboard {
                            model.startKeyboardDictationSession()
                        } else {
                            model.startRecording()
                        }
                    }
                }
        }
    }
}
