import AppKit
import SwiftUI

@main
struct MornLiveUtilApp: App {
    init() {
        if CommandLine.arguments.contains("--selftest") { selfTest(); exit(0) }
        // swift run で起動してもウィンドウが前面に出るように
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
    }

    var body: some Scene {
        WindowGroup("MornLiveUtil") { ContentView() }
            .defaultSize(width: 520, height: 640)
    }
}

@MainActor @Observable
final class Model {
    var chats: [Chat] = []
    var status = ""
    var running = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored lazy var reader = Reader { [weak self] in self?.status = $0 }

    func start(url: String) {
        guard let id = LiveChat.videoID(url) else { status = "URL から動画IDを取れません"; return }
        stop()
        running = true
        chats = []
        status = "接続中…"
        task = Task {
            defer { running = false }
            do {
                var chat = try await LiveChat.connect(videoID: id)
                status = "接続しました"
                var first = true
                while !Task.isCancelled {
                    let (new, wait) = try await chat.poll()
                    chats.append(contentsOf: new)
                    if chats.count > 500 { chats.removeFirst(chats.count - 500) }
                    // 接続直後に届く過去ログは読まない
                    if !first {
                        let readName = UserDefaults.standard.bool(forKey: "readName")
                        new.forEach { reader.say(speechText($0, readName: readName)) }
                    }
                    first = false
                    try await Task.sleep(for: .milliseconds(wait))
                }
            } catch is CancellationError {
                status = "停止しました"
            } catch {
                status = error.localizedDescription
            }
        }
    }

    func stop() {
        task?.cancel()
        reader.stop()
    }
}

struct ContentView: View {
    @State private var model = Model()
    @State private var speakers: [Speaker] = []
    @AppStorage("url") private var url = ""
    @AppStorage("speaker") private var speaker = 3
    @AppStorage("speed") private var speed = 1.2
    @AppStorage("readName") private var readName = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("配信URL", text: $url)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.start(url: url) }
                if model.running {
                    Button("停止") { model.stop() }
                } else {
                    Button("開始") { model.start(url: url) }.keyboardShortcut(.defaultAction)
                }
            }

            Form {
                Picker("話者", selection: $speaker) {
                    ForEach(speakers) { Text($0.name).tag($0.id) }
                }
                .disabled(speakers.isEmpty)
                Slider(value: $speed, in: 0.5...2.0) { Text("速さ \(speed, specifier: "%.1f")") }
                Toggle("名前も読む", isOn: $readName)
            }

            ScrollViewReader { proxy in
                List(model.chats) { c in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.author).font(.caption).foregroundStyle(.secondary)
                        Text(c.text).textSelection(.enabled)
                    }
                    .id(c.id)
                }
                .onChange(of: model.chats.last?.id) { _, id in
                    if let id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }

            Text(model.status).font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .frame(minWidth: 420, minHeight: 480)
        .task { await loadSpeakers() }
    }

    private func loadSpeakers() async {
        do {
            speakers = try await Voicevox.speakers()
        } catch {
            model.status = "VOICEVOX に接続できません。起動してからウィンドウを開き直してください"
        }
    }
}

private func selfTest() {
    precondition(LiveChat.videoID("https://www.youtube.com/watch?v=8GtbuaL0y_8&t=1") == "8GtbuaL0y_8")
    precondition(LiveChat.videoID("https://youtu.be/8GtbuaL0y_8") == "8GtbuaL0y_8")
    precondition(LiveChat.videoID("https://www.youtube.com/live/8GtbuaL0y_8?si=x") == "8GtbuaL0y_8")
    precondition(LiveChat.videoID("8GtbuaL0y_8") == "8GtbuaL0y_8")
    precondition(LiveChat.videoID("hello") == nil)

    let json: [String: Any] = ["continuationContents": ["liveChatContinuation": [
        "continuations": [["invalidationContinuationData": ["continuation": "NEXT", "timeoutMs": 10000]]],
        "actions": [
            ["addChatItemAction": ["item": ["liveChatTextMessageRenderer": [
                "id": "a", "authorName": ["simpleText": "@taro-x1z"],
                "message": ["runs": [["text": "見て https://x.com/a "], ["emoji": [:]], ["text": "www"]]]]]]],
            ["addChatItemAction": ["item": ["liveChatPaidMessageRenderer": [
                "id": "b", "authorName": ["simpleText": "@hanako"], "purchaseAmountText": ["simpleText": "¥500"]]]]],
            ["addChatItemAction": ["item": ["liveChatMembershipItemRenderer": ["id": "c"]]]],
        ],
    ]]]
    let (chats, next, wait) = LiveChat.parse(json)
    precondition(next == "NEXT" && wait == 2000)
    precondition(chats.map(\.id) == ["a", "b"])
    precondition(speechText(chats[0], readName: true) == "taro、見て URL わら")
    precondition(speechText(chats[1], readName: false) == "¥500 ")
    precondition(LiveChat.parse([:]).continuation == nil)
    print("selftest ok")
}
