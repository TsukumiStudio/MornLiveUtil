import AVFoundation
import Foundation

struct Speaker: Identifiable, Hashable {
    let id: Int
    let name: String
}

enum Voicevox {
    static let base = "http://127.0.0.1:50021"

    static func speakers() async throws -> [Speaker] {
        let (data, _) = try await URLSession.shared.data(from: URL(string: "\(base)/speakers")!)
        let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        return list.flatMap { s in
            (s["styles"] as? [[String: Any]] ?? []).compactMap { st in
                guard let id = st["id"] as? Int else { return nil }
                return Speaker(id: id, name: "\(s["name"] as? String ?? "")（\(st["name"] as? String ?? "")）")
            }
        }
    }

    static func synthesize(_ text: String, speaker: Int, speed: Double) async throws -> Data {
        var c = URLComponents(string: "\(base)/audio_query")!
        c.queryItems = [.init(name: "text", value: text), .init(name: "speaker", value: "\(speaker)")]
        var q = URLRequest(url: c.url!)
        q.httpMethod = "POST"
        var query = try JSONSerialization.jsonObject(with: try await URLSession.shared.data(for: q).0) as? [String: Any] ?? [:]
        query["speedScale"] = speed

        var s = URLRequest(url: URL(string: "\(base)/synthesis?speaker=\(speaker)")!)
        s.httpMethod = "POST"
        s.setValue("application/json", forHTTPHeaderField: "Content-Type")
        s.httpBody = try JSONSerialization.data(withJSONObject: query)
        return try await URLSession.shared.data(for: s).0
    }
}

/// 読み上げ用に整形する。声はサイトで視聴者が選んだもの (無ければ nil)
/// コメント本文が maxLength 文字を超えたら「以下略」で切る (0 以下なら切らない)。
/// 辞書で長くなった分は数えない
func speechText(_ chat: Chat, readName: Bool, maxLength: Int = 60, site: SiteConfig = SiteConfig()) -> (text: String, speaker: Int?) {
    let viewer = site.viewers[chat.channelId]
    var t = chat.text
    var omitted = ""
    if maxLength > 0, t.count > maxLength { t = String(t.prefix(maxLength)); omitted = " 以下略" }
    t = site.applyDictionary(t)
        .replacing(/https?:\/\/\S+/, with: "URL")
        .replacing(/[wｗ]{2,}/, with: "わら") + omitted
    guard readName else { return (t, viewer?.speaker) }
    // "@name-abc" → "name"
    var name = chat.author.replacing(/^@/, with: "").replacing(/-[a-z0-9]{3}$/, with: "")
    if let nick = viewer?.nickname, !nick.isEmpty { name = nick }
    return ("\(name)、\(t)", viewer?.speaker)
}

/// 1 本ずつ順番に再生する。溜まりすぎたら古いものから捨てる。
final class Reader {
    private let queue: AsyncStream<(String, Int?)>.Continuation
    private var player: AVAudioPlayer?

    init(onError: @escaping @MainActor (String) -> Void) {
        let (stream, queue) = AsyncStream.makeStream(of: (String, Int?).self, bufferingPolicy: .bufferingNewest(10))
        self.queue = queue
        Task { [weak self] in
            for await (text, speaker) in stream {
                do {
                    guard let self else { return }
                    try await Task.sleep(for: .seconds(self.play(text, speaker: speaker)))
                } catch {
                    await onError("VOICEVOX: \(error.localizedDescription)")
                }
            }
        }
    }

    /// 再生を始めて長さ(秒)を返す
    @discardableResult
    func play(_ text: String, speaker: Int? = nil) async throws -> TimeInterval {
        let d = UserDefaults.standard
        let wav = try await Voicevox.synthesize(text, speaker: speaker ?? d.integer(forKey: "speaker"), speed: d.double(forKey: "speed"))
        let p = try AVAudioPlayer(data: wav)
        p.volume = Float(d.double(forKey: "volume"))
        player?.stop()
        player = p
        p.play()
        return p.duration
    }

    func say(_ text: String, speaker: Int? = nil) { if !text.isEmpty { queue.yield((text, speaker)) } }
    func stop() { player?.stop() }
}
