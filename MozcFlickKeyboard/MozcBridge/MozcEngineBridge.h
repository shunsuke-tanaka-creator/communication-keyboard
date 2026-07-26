// =============================================================================
// MozcEngineBridge.h
// Objective-C ヘッダ。Swift から利用する Mozc 変換エンジンの薄いブリッジ。
//
// 設計方針:
//  - 公開するのは純粋な Objective-C / Foundation 型のみ（NSString/NSArray/NSDictionary）。
//    C++ / Mozc の内部型はヘッダに一切漏らさない（実装は .mm 側に隠蔽）。
//  - 候補は NSArray<NSDictionary *> * で返す。各辞書のキーは下記 定数を使用:
//      kMozcCandidateKeyID / kMozcCandidateKeyValue /
//      kMozcCandidateKeyReading / kMozcCandidateKeyDescription
//  - 変換状態は 1 個の NSDictionary（"result")で返し、Swift 側で ConversionResult へ変換する。
// =============================================================================

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// --- 候補辞書のキー ---------------------------------------------------------
FOUNDATION_EXPORT NSString *const kMozcCandidateKeyID;          // NSString  候補ID
FOUNDATION_EXPORT NSString *const kMozcCandidateKeyValue;       // NSString  確定文字列
FOUNDATION_EXPORT NSString *const kMozcCandidateKeyReading;     // NSString  よみ（ひらがな）
FOUNDATION_EXPORT NSString *const kMozcCandidateKeyDescription; // NSString? 注釈（任意）

// --- 変換結果辞書のキー -----------------------------------------------------
FOUNDATION_EXPORT NSString *const kMozcResultKeyComposition;    // NSString                未確定よみ
FOUNDATION_EXPORT NSString *const kMozcResultKeyCandidates;     // NSArray<NSDictionary*>  候補列
FOUNDATION_EXPORT NSString *const kMozcResultKeySegments;       // NSArray<NSDictionary*>  文節列
FOUNDATION_EXPORT NSString *const kMozcResultKeyFocusedSegment; // NSNumber(int)           フォーカス文節
FOUNDATION_EXPORT NSString *const kMozcResultKeyIsConverting;   // NSNumber(BOOL)          変換中か

// --- 文節辞書のキー ---------------------------------------------------------
FOUNDATION_EXPORT NSString *const kMozcSegmentKeyReading;       // NSString                文節よみ
FOUNDATION_EXPORT NSString *const kMozcSegmentKeySelected;      // NSDictionary            選択候補
FOUNDATION_EXPORT NSString *const kMozcSegmentKeyCandidates;    // NSArray<NSDictionary*>  文節候補

/// Mozc 変換エンジンへの Objective-C ブリッジ。
/// C++ 例外は境界で握りつぶし、Swift へは伝播させない。
@interface MozcEngineBridge : NSObject

/// Mozc 実 API が組み込まれているか（MOZC_AVAILABLE 定義の有無）。
/// NO の場合はスタブ応答を返す。
@property (nonatomic, readonly, getter=isMozcAvailable) BOOL mozcAvailable;

- (instancetype)init;

/// 辞書データファイル(mozc.data)の絶対パスを指定して初期化する。
/// パスが空/不正な場合、IosEngine は埋め込みの低品質エンジンにフォールバックする。
- (instancetype)initWithDataPath:(NSString *)dataPath NS_DESIGNATED_INITIALIZER;

/// 内部状態を初期化する。
- (void)reset;

/// 未確定文字列末尾へかなを追加する。
- (void)insertText:(NSString *)text;

/// 未確定文字列末尾を 1 文字削除する。
- (void)deleteBackward;

/// 変換を要求し、変換結果辞書（kMozcResultKey* を含む）を返す。
- (NSDictionary<NSString *, id> *)requestConversion;

/// 予測候補を要求し、変換結果辞書を返す。
- (NSDictionary<NSString *, id> *)requestPrediction;

/// 指定 ID の候補を選択し（学習にも反映）、変換結果辞書を返す。
- (NSDictionary<NSString *, id> *)selectCandidateWithID:(NSString *)candidateID;

/// フォーカス文節を offset だけ移動し、変換結果辞書を返す。
- (NSDictionary<NSString *, id> *)moveFocusBy:(NSInteger)offset;

/// フォーカス文節を offset 文字ぶん伸縮し、変換結果辞書を返す。
- (NSDictionary<NSString *, id> *)resizeFocusedSegmentBy:(NSInteger)offset;

/// 現在の選択状態を確定し、確定文字列を返す。副作用で内部状態はリセットされる。
- (NSString *)commit;

/// 変換を取り消してかな入力状態へ戻し、変換結果辞書を返す。
- (NSDictionary<NSString *, id> *)cancelConversion;

@end

NS_ASSUME_NONNULL_END
