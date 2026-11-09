import Foundation

/// live.tsukumistudio.com の辞書と視聴者設定
struct SiteConfig {
    struct Viewer {
        let nickname: String
        let speaker: Int?
    }

    var dictionary: [String: String] = [:]
    var viewers: [String: Viewer] = [:]

    static let base = "https://live.tsukumistudio.com"

    /// 取得してローカルに保存する。読み上げ時は通信せず保存分を使う
    static func fetch() async throws -> SiteConfig {
        let (data, _) = try await URLSession.shared.data(from: URL(string: "\(base)/api/app/config")!)
        let config = parse(try JSONSerialization.jsonObject(with: data))
        config.save()
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "siteFetchedAt")
        return config
    }

    static func cached() -> SiteConfig {
        guard let data = UserDefaults.standard.data(forKey: "siteConfig"),
              let json = try? JSONSerialization.jsonObject(with: data) else { return SiteConfig() }
        return parse(json)
    }

    func save() {
        UserDefaults.standard.set(try? JSONSerialization.data(withJSONObject: json), forKey: "siteConfig")
    }

    var json: [String: Any] {
        ["dictionary": dictionary, "viewers": viewers.mapValues { v -> [String: Any] in
            var o: [String: Any] = ["nickname": v.nickname]
            if let s = v.speaker { o["speaker"] = s }
            return o
        }]
    }

    static func parse(_ json: Any) -> SiteConfig {
        let root = json as? [String: Any] ?? [:]
        var config = SiteConfig()
        config.dictionary = root["dictionary"] as? [String: String] ?? [:]
        for (id, v) in root["viewers"] as? [String: [String: Any]] ?? [:] {
            config.viewers[id] = Viewer(nickname: v["nickname"] as? String ?? "", speaker: v["speaker"] as? Int)
        }
        return config
    }

    /// 長い語から順に、大文字小文字を区別せず置き換える
    func applyDictionary(_ text: String) -> String {
        dictionary.keys.sorted { $0.count > $1.count }.reduce(text) { t, from in
            t.replacingOccurrences(of: from, with: dictionary[from]!, options: .caseInsensitive)
        }
    }

    /// 教育（a=b）/ 忘却（a）を書き換えて返す読み上げ文。コマンドでなければ nil
    mutating func command(_ text: String, token: String) -> String? {
        if let m = text.wholeMatch(of: /教育[（(]([^()（）=＝]+)[=＝]([^()（）=＝]+)[）)]/) {
            let (from, to) = (m.1.trimmingCharacters(in: .whitespaces), m.2.trimmingCharacters(in: .whitespaces))
            guard !from.isEmpty, !to.isEmpty else { return nil }
            let updated = dictionary[from] != nil
            dictionary[from] = to
            Self.post(["from": from, "to": to], token: token)
            return updated ? "\(from) は \(to) に上書きしました！" : "\(from) は \(to) を覚えました！"
        }
        if let m = text.wholeMatch(of: /忘却[（(]([^()（）=＝]+)[）)]/) {
            let key = m.1.trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { return nil }
            guard dictionary.removeValue(forKey: key) != nil else { return "\(key) は覚えていません！" }
            Self.post(["forget": key], token: token)
            return "\(key) を忘れました！"
        }
        return nil
    }

    private static func post(_ body: [String: String], token: String) {
        guard !token.isEmpty else { return }
        var req = URLRequest(url: URL(string: "\(base)/api/app/learn")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        // ponytail: 失敗しても再送しない。次の再取得でサイトの内容に戻る
        Task { _ = try? await URLSession.shared.data(for: req) }
    }
}
