import Foundation

/// よみ（読み仮名）の正規化ユーティリティ。
/// カタカナ→ひらがな、全角英数記号→半角、前後空白除去などを行う。
/// ユーザー辞書・学習の双方でキーを揃えるために共通利用する。
public enum ReadingNormalizer {

    /// よみを正規化して返す。
    /// - カタカナ（全角/半角）→ ひらがな
    /// - 全角英数字・記号 → 半角
    /// - 前後空白の除去
    /// - 小文字化（英字）
    public static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return s }

        // 半角カナ → 全角カナ、全角英数 → 半角 をまとめて行う。
        // .fullwidthToHalfwidth で全角英数記号と全角カナが半角化される。
        if let converted = s.applyingTransform(.fullwidthToHalfwidth, reverse: false) {
            s = converted
        }
        // 半角カナ→ひらがな化のため、いったん全角カナへ戻してから平仮名化する。
        if let toKatakana = s.applyingTransform(.hiraganaToKatakana, reverse: false) {
            // hiraganaToKatakana でひらがな部分をカタカナへ寄せ、次に一括で平仮名へ。
            s = toKatakana
        }
        // カタカナ → ひらがな。
        if let toHiragana = s.applyingTransform(.hiraganaToKatakana, reverse: true) {
            s = toHiragana
        }

        return s.lowercased()
    }
}
