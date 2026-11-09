import Foundation

struct Chat: Identifiable {
    let id: String
    let author: String
    var channelId = ""
    let text: String
}

struct ChatError: LocalizedError {
    let errorDescription: String?
    init(_ s: String) { errorDescription = s }
}

/// ブラウザのポップアウトチャットと同じ内部 API (youtubei) を叩く。API キー不要。
/// ponytail: YouTube 側の仕様変更で壊れる前提の非公式 API。壊れたら live_chat ページの JSON 構造を見直す。
struct LiveChat {
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"

    let apiKey: String
    let clientVersion: String
    var continuation: String

    /// watch?v= / youtu.be / live / shorts / 動画ID単体 から動画IDを取り出す
    static func videoID(_ input: String) -> String? {
        let s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.wholeMatch(of: /[\w-]{11}/) != nil { return s }
        guard let c = URLComponents(string: s) else { return nil }
        if let v = c.queryItems?.first(where: { $0.name == "v" })?.value { return v }
        let parts = c.path.split(separator: "/").map(String.init)
        if c.host?.hasSuffix("youtu.be") == true { return parts.first }
        if let i = parts.firstIndex(where: { ["live", "shorts", "embed"].contains($0) }), i + 1 < parts.count {
            return parts[i + 1]
        }
        return nil
    }

    static func connect(videoID: String) async throws -> LiveChat {
        var req = URLRequest(url: URL(string: "https://www.youtube.com/live_chat?is_popout=1&v=\(videoID)")!)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("ja", forHTTPHeaderField: "Accept-Language")
        let html = String(decoding: try await URLSession.shared.data(for: req).0, as: UTF8.self)

        func first(_ key: String) -> String? {
            html.firstMatch(of: try! Regex("\"\(key)\":\"([^\"]+)\""))?.output[1].substring.map(String.init)
        }
        // reloadContinuationData は [上位チャット, チャット] の順。全件見たいので最後を使う
        let reloads = html.matches(of: /"reloadContinuationData":\{"continuation":"([^"]+)"/).map { String($0.output.1) }
        guard let key = first("INNERTUBE_API_KEY"),
              let ver = first("INNERTUBE_CLIENT_VERSION"),
              let cont = reloads.last ?? first("continuation")
        else { throw ChatError("チャットが見つかりません (配信中でない / チャット無効)") }
        return LiveChat(apiKey: key, clientVersion: ver, continuation: cont)
    }

    /// 新着コメントと次回ポーリングまでの待ち時間を返す
    mutating func poll() async throws -> (chats: [Chat], waitMs: Int) {
        var req = URLRequest(url: URL(string: "https://www.youtube.com/youtubei/v1/live_chat/get_live_chat?key=\(apiKey)")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "context": ["client": ["clientName": "WEB", "clientVersion": clientVersion, "hl": "ja"]],
            "continuation": continuation,
        ])
        let json = try JSONSerialization.jsonObject(with: try await URLSession.shared.data(for: req).0)
        let (chats, next, wait) = Self.parse(json)
        guard let next else { throw ChatError("配信が終了しました") }
        continuation = next
        return (chats, wait)
    }

    static func parse(_ json: Any) -> (chats: [Chat], continuation: String?, waitMs: Int) {
        let root = (json as? [String: Any])?["continuationContents"] as? [String: Any]
        let live = root?["liveChatContinuation"] as? [String: Any] ?? [:]

        let next = (live["continuations"] as? [[String: Any]])?.first?.values
            .compactMap { $0 as? [String: Any] }.first { $0["continuation"] != nil }
        let token = next?["continuation"] as? String
        // invalidation 系は timeoutMs が 10 秒と長いので、体感優先で上限を切る
        let wait = min(next?["timeoutMs"] as? Int ?? 2000, 2000)

        let chats: [Chat] = (live["actions"] as? [[String: Any]] ?? []).compactMap { action in
            guard let item = (action["addChatItemAction"] as? [String: Any])?["item"] as? [String: Any] else { return nil }
            let paid = item["liveChatPaidMessageRenderer"] as? [String: Any]
            guard let r = item["liveChatTextMessageRenderer"] as? [String: Any] ?? paid,
                  let id = r["id"] as? String else { return nil }
            let author = (r["authorName"] as? [String: Any])?["simpleText"] as? String ?? ""
            // 絵文字 run はテキストを持たないので読まない
            let runs = (r["message"] as? [String: Any])?["runs"] as? [[String: Any]] ?? []
            var text = runs.compactMap { $0["text"] as? String }.joined()
            if let amount = (paid?["purchaseAmountText"] as? [String: Any])?["simpleText"] as? String {
                text = "\(amount) \(text)"
            }
            return Chat(id: id, author: author, channelId: r["authorExternalChannelId"] as? String ?? "", text: text)
        }
        return (chats, token, wait)
    }
}
