# MornLiveUtil

- 確認: `swift build && .build/debug/MornLiveUtil --selftest`
- リリース: 変更をコミットしたら確認なしで `git push` し、`vX.Y.Z` タグを push する（ユーザーの常時許可あり）。workflow がビルド・MornNotary 署名・GitHub Release・Homebrew tap 更新まで行う。
- 版の上げ方: 機能追加は minor、修正のみは patch。
