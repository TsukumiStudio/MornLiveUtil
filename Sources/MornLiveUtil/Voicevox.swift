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

/// 読み上げ用に整形する
func speechText(_ chat: Chat, readName: Bool) -> String {
    var t = chat.text
        .replacing(/https?:\/\/\S+/, with: "URL")
        .replacing(/[wｗ]{2,}/, with: "わら")
    if t.count > 60 { t = String(t.prefix(60)) + " 以下略" }
    guard readName else { return t }
    // "@name-abc" → "name"
    let name = chat.author.replacing(/^@/, with: "").replacing(/-[a-z0-9]{3}$/, with: "")
    return "\(name)、\(t)"
}

/// 1 本ずつ順番に再生する。溜まりすぎたら古いものから捨てる。
final class Reader {
    private let queue: AsyncStream<String>.Continuation
    private var player: AVAudioPlayer?

    init(onError: @escaping @MainActor (String) -> Void) {
        let (stream, queue) = AsyncStream.makeStream(of: String.self, bufferingPolicy: .bufferingNewest(10))
        self.queue = queue
        Task { [weak self] in
            for await text in stream {
                do {
                    guard let self else { return }
                    try await Task.sleep(for: .seconds(self.play(text)))
                } catch {
                    await onError("VOICEVOX: \(error.localizedDescription)")
                }
            }
        }
    }

    /// 再生を始めて長さ(秒)を返す
    @discardableResult
    func play(_ text: String) async throws -> TimeInterval {
        let d = UserDefaults.standard
        let wav = try await Voicevox.synthesize(text, speaker: d.integer(forKey: "speaker"), speed: d.double(forKey: "speed"))
        let p = try AVAudioPlayer(data: wav)
        player?.stop()
        player = p
        p.play()
        return p.duration
    }

    func say(_ text: String) { if !text.isEmpty { queue.yield(text) } }
    func stop() { player?.stop() }
}
