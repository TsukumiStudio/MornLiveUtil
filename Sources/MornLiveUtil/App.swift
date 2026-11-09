import AppKit
import SwiftUI

@main
struct MornLiveUtilApp: App {
    init() {
        // @AppStorage の初期値と読み上げ側の読み出しを揃える
        UserDefaults.standard.register(defaults: ["speaker": 3, "speed": 1.2, "volume": 1.0, "readName": true])
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
    @ObservationIgnored private var site = SiteConfig()
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
                var siteFetched = Date.distantPast
                status = "接続しました"
                var first = true
                while !Task.isCancelled {
                    // サイトの辞書・視聴者設定は 1 分ごとに取り直す
                    if Date().timeIntervalSince(siteFetched) > 60 {
                        siteFetched = Date()
                        do { site = try await SiteConfig.fetch() } catch { status = "サイトの設定を読めません: \(error.localizedDescription)" }
                    }
                    let (new, wait) = try await chat.poll()
                    chats.append(contentsOf: new)
                    if chats.count > 500 { chats.removeFirst(chats.count - 500) }
                    // 接続直後に届く過去ログは読まない
                    if !first {
                        let d = UserDefaults.standard
                        for c in new {
                            if let reply = site.command(c.text, token: d.string(forKey: "siteToken") ?? "") {
                                reader.say(reply)
                            } else {
                                let s = speechText(c, readName: d.bool(forKey: "readName"), site: site)
                                reader.say(s.text, speaker: s.speaker)
                            }
                        }
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

    func preview() {
        Task {
            do { try await reader.play("これはテストです") } catch { status = "VOICEVOX: \(error.localizedDescription)" }
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
    @StateObject private var updater = Updater()
    @AppStorage("url") private var url = ""
    @AppStorage("speaker") private var speaker = 3
    @AppStorage("speed") private var speed = 1.2
    @AppStorage("volume") private var volume = 1.0
    @AppStorage("readName") private var readName = true
    @AppStorage("siteToken") private var siteToken = ""

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
                Slider(value: $volume, in: 0...1) { Text("音量") }
                Button("試聴") { model.preview() }.disabled(speakers.isEmpty)
                Toggle("名前も読む", isOn: $readName)
                SecureField("サイト連携トークン（教育・忘却をサイトに保存）", text: $siteToken)
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

            HStack {
                Text(model.status).font(.caption).foregroundStyle(.secondary)
                Spacer()
                updateControls
                Text("v\(Updater.version)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(minWidth: 420, minHeight: 480)
        .task { await loadSpeakers() }
        .task { await updater.check() }
    }

    @ViewBuilder private var updateControls: some View {
        switch updater.state {
        case .idle:
            Button("最新を確認") { Task { await updater.check() } }
        case .checking:
            Text("確認中…").font(.caption)
        case .available(let tag):
            Button("最新に更新 (\(tag))") { Task { await updater.update() } }
        case .upToDate:
            Button("最新版です ↻") { Task { await updater.check() } }.help("最新を確認")
        case .updating:
            Text("更新中…").font(.caption)
        case .updated:
            Button("再起動して適用") { updater.restart() }
        case .failed(let message):
            Button("更新エラー") {
                let alert = NSAlert()
                alert.messageText = "更新できませんでした"
                alert.informativeText = message
                alert.alertStyle = .warning
                alert.runModal()
            }
            .foregroundStyle(.red)
            Button("再確認") { Task { await updater.check() } }
        }
    }

    private func loadSpeakers() async {
        do {
            speakers = try await Voicevox.speakers()
        } catch {
            model.status = "VOICEVOX に接続できません。起動してからウィンドウを開き直してください"
        }
    }
}

@MainActor private func selfTest() {
    precondition(LiveChat.videoID("https://www.youtube.com/watch?v=8GtbuaL0y_8&t=1") == "8GtbuaL0y_8")
    precondition(LiveChat.videoID("https://youtu.be/8GtbuaL0y_8") == "8GtbuaL0y_8")
    precondition(LiveChat.videoID("https://www.youtube.com/live/8GtbuaL0y_8?si=x") == "8GtbuaL0y_8")
    precondition(LiveChat.videoID("8GtbuaL0y_8") == "8GtbuaL0y_8")
    precondition(LiveChat.videoID("hello") == nil)
    let registered = UserDefaults.standard.volatileDomain(forName: UserDefaults.registrationDomain)
    precondition(registered["speaker"] as? Int == 3 && registered["readName"] as? Bool == true && registered["volume"] as? Double == 1)
    precondition(Updater.isNewer(latestTag: "v0.10.0", current: "0.9.1"))
    precondition(!Updater.isNewer(latestTag: "v0.1.0", current: "0.1.0"))

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
    precondition(speechText(chats[0], readName: true).text == "taro、見て URL わら")
    precondition(speechText(chats[1], readName: false).text == "¥500 ")

    var site = SiteConfig.parse([
        "dictionary": ["ab": "エービー", "abc": "エービーシー"],
        "viewers": ["UCx": ["nickname": "たろう", "speaker": 8]],
    ])
    precondition(site.applyDictionary("ABC と ab") == "エービーシー と エービー")
    let viewer = speechText(Chat(id: "1", author: "@taro", channelId: "UCx", text: "ab"), readName: true, site: site)
    precondition(viewer.text == "たろう、エービー" && viewer.speaker == 8)
    precondition(site.command("教育（xy=えっくす）", token: "") == "xy は えっくす を覚えました！" && site.dictionary["xy"] == "えっくす")
    precondition(site.command("忘却(xy)", token: "") == "xy を忘れました！" && site.dictionary["xy"] == nil)
    precondition(site.command("忘却（xy）", token: "") == "xy は覚えていません！")
    precondition(site.command("前に教育（a=b）", token: "") == nil)
    precondition(LiveChat.parse([:]).continuation == nil)
    print("selftest ok")
}
