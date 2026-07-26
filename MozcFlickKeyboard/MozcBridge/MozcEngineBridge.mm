// =============================================================================
// MozcEngineBridge.mm
// Objective-C++ 実装。Mozc の実 API 呼び出し（MOZC_AVAILABLE 定義時）と、
// 未定義時のローカルスタブ応答の両方を持つ。
//
// 安全性:
//  - C++ 例外は ObjC 境界（各メソッド内）で try/catch し、Swift へ漏らさない。
//  - Swift/C++ 境界の文字列は UTF-8(std::string) <-> UTF-16(NSString) を明示変換する。
//    NSString へは -[NSString stringWithUTF8String:] / -[NSString UTF8String] を用いる。
// =============================================================================

#import "MozcEngineBridge.h"

#include <string>
#include <vector>

#ifdef MOZC_AVAILABLE
// Mozc 実 API のヘッダ（ビルドフラグで MOZC_AVAILABLE が定義された場合のみ）。
// include パスは build_mozc_ios.sh の収集構成（out/mozc/include）に合わせる。
#include "ios/ios_engine.h"
#include "protocol/commands.pb.h"
#include "protocol/config.pb.h"
#endif

// --- 候補辞書のキー ---------------------------------------------------------
NSString *const kMozcCandidateKeyID = @"id";
NSString *const kMozcCandidateKeyValue = @"value";
NSString *const kMozcCandidateKeyReading = @"reading";
NSString *const kMozcCandidateKeyDescription = @"description";

// --- 変換結果辞書のキー -----------------------------------------------------
NSString *const kMozcResultKeyComposition = @"composition";
NSString *const kMozcResultKeyCandidates = @"candidates";
NSString *const kMozcResultKeySegments = @"segments";
NSString *const kMozcResultKeyFocusedSegment = @"focusedSegment";
NSString *const kMozcResultKeyIsConverting = @"isConverting";

// --- 文節辞書のキー ---------------------------------------------------------
NSString *const kMozcSegmentKeyReading = @"reading";
NSString *const kMozcSegmentKeySelected = @"selected";
NSString *const kMozcSegmentKeyCandidates = @"candidates";

// UTF-8(std::string) -> NSString(UTF-16) 変換ヘルパ。nil を返さないよう空文字でフォールバック。
static NSString *NSStringFromStdString(const std::string &s) {
    NSString *result = [[NSString alloc] initWithBytes:s.data()
                                                length:s.size()
                                              encoding:NSUTF8StringEncoding];
    return result != nil ? result : @"";
}

// NSString(UTF-16) -> std::string(UTF-8) 変換ヘルパ。
static std::string StdStringFromNSString(NSString *s) {
    if (s == nil) {
        return std::string();
    }
    const char *utf8 = [s UTF8String];
    return utf8 != nullptr ? std::string(utf8) : std::string();
}

@implementation MozcEngineBridge {
    // スタブ用の内部状態。未確定よみを UTF-8 の std::string で保持する。
    std::string _composition;
#ifdef MOZC_AVAILABLE
    // 実 API では Mozc の IosEngine と直近の変換出力(Output)を保持する。
    std::unique_ptr<mozc::ios::IosEngine> _engine;
    mozc::commands::Output _lastOutput;  // 直近コマンドの出力（候補/preedit/result の取り出し元）
    BOOL _engineReady;                    // CreateSession まで成功したか
#endif
}

- (instancetype)init {
    // 辞書パス未指定。IosEngine は埋め込みフォールバックで動く（ヘッダ記載）。
    return [self initWithDataPath:@""];
}

- (instancetype)initWithDataPath:(NSString *)dataPath {
    self = [super init];
    if (self) {
        _composition.clear();
#ifdef MOZC_AVAILABLE
        _engineReady = NO;
        @try {
            std::string path = StdStringFromNSString(dataPath);
            _engine = std::make_unique<mozc::ios::IosEngine>(path);
            // モバイル用リクエスト(12キー フリック)を設定し、モバイル設定を反映してセッション作成。
            mozc::commands::Command command;
            _engine->SetMobileRequest("12KEYS", &command);
            mozc::config::Config config;
            mozc::ios::IosEngine::FillMobileConfig(&config);
            _engine->SetConfig(config, &command);
            if (_engine->CreateSession(&command)) {
                _engineReady = YES;
            } else {
                NSLog(@"[MozcEngineBridge] CreateSession に失敗しました。");
            }
        } @catch (NSException *e) {
            NSLog(@"[MozcEngineBridge] init 中に例外: %@", e);
            _engine.reset();
            _engineReady = NO;
        }
#endif
    }
    return self;
}

- (BOOL)isMozcAvailable {
#ifdef MOZC_AVAILABLE
    return YES;
#else
    return NO;
#endif
}

- (void)reset {
    @try {
        _composition.clear();
#ifdef MOZC_AVAILABLE
        if ([self engineUsable]) {
            mozc::commands::Command command;
            _engine->ResetContext(&command);
            _lastOutput.Clear();
        }
#endif
    } @catch (NSException *e) {
        NSLog(@"[MozcEngineBridge] reset 例外: %@", e);
    }
}

- (void)insertText:(NSString *)text {
    @try {
        _composition += StdStringFromNSString(text);
#ifdef MOZC_AVAILABLE
        if ([self engineUsable]) {
            // かなは複数コードポイントを含みうる（例: 拗音）。1 文字ずつ SendKey する。
            NSUInteger len = text.length;
            [text enumerateSubstringsInRange:NSMakeRange(0, len)
                                     options:NSStringEnumerationByComposedCharacterSequences
                                  usingBlock:^(NSString *sub, NSRange r, NSRange er, BOOL *stop) {
                mozc::commands::Command command;
                self->_engine->SendKey(StdStringFromNSString(sub), &command);
                if (command.has_output()) {
                    self->_lastOutput = command.output();
                }
            }];
        }
#endif
    } @catch (NSException *e) {
        NSLog(@"[MozcEngineBridge] insertText 例外: %@", e);
    }
}

- (void)deleteBackward {
    @try {
        // UTF-8 末尾 1 コードポイントを削除する（継続バイト 10xxxxxx を読み飛ばす）。
        if (!_composition.empty()) {
            size_t i = _composition.size();
            do {
                --i;
            } while (i > 0 && (static_cast<unsigned char>(_composition[i]) & 0xC0) == 0x80);
            _composition.erase(i);
        }
#ifdef MOZC_AVAILABLE
        if ([self engineUsable]) {
            mozc::commands::Command command;
            _engine->SendSpecialKey(mozc::commands::KeyEvent::BACKSPACE, &command);
            if (command.has_output()) {
                _lastOutput = command.output();
            }
        }
#endif
    } @catch (NSException *e) {
        NSLog(@"[MozcEngineBridge] deleteBackward 例外: %@", e);
    }
}

- (NSDictionary<NSString *, id> *)requestConversion {
    @try {
#ifdef MOZC_AVAILABLE
        if ([self engineUsable]) {
            // モバイルは SendKey 応答に既にサジェストが載る。直近出力をそのまま返す。
            return [self resultFromLastOutput];
        }
#endif
        return [self stubResultConverting:YES];
    } @catch (NSException *e) {
        NSLog(@"[MozcEngineBridge] requestConversion 例外: %@", e);
        return [self emptyResult];
    }
}

- (NSDictionary<NSString *, id> *)requestPrediction {
    @try {
#ifdef MOZC_AVAILABLE
        if ([self engineUsable]) {
            return [self resultFromLastOutput];
        }
#endif
        return [self stubResultConverting:NO];
    } @catch (NSException *e) {
        NSLog(@"[MozcEngineBridge] requestPrediction 例外: %@", e);
        return [self emptyResult];
    }
}

- (NSDictionary<NSString *, id> *)selectCandidateWithID:(NSString *)candidateID {
    @try {
#ifdef MOZC_AVAILABLE
        if ([self engineUsable]) {
            // 候補 ID は Output 由来の int を文字列化したもの。int へ戻して選択する。
            int index = [candidateID intValue];
            mozc::commands::Command command;
            _engine->SubmitCandidate(index, &command);
            if (command.has_output()) {
                _lastOutput = command.output();
            }
            // 追加(デバッグ): SubmitCandidate 後の result / preedit を確認する。
            NSLog(@"[MozcEngineBridge] selectCandidate id=%d has_result=%d result='%@' has_preedit=%d",
                  index,
                  _lastOutput.has_result(),
                  _lastOutput.has_result() ? NSStringFromStdString(_lastOutput.result().value()) : @"(none)",
                  _lastOutput.has_preedit());
            return [self resultFromLastOutput];
        }
#endif
        return [self stubResultConverting:YES];
    } @catch (NSException *e) {
        NSLog(@"[MozcEngineBridge] selectCandidate 例外: %@", e);
        return [self emptyResult];
    }
}

- (NSDictionary<NSString *, id> *)moveFocusBy:(NSInteger)offset {
    @try {
#ifdef MOZC_AVAILABLE
        // TODO(main): フォーカス文節移動を Mozc へ通知する。
#endif
        return [self stubResultConverting:YES];
    } @catch (NSException *e) {
        NSLog(@"[MozcEngineBridge] moveFocusBy 例外: %@", e);
        return [self emptyResult];
    }
}

- (NSDictionary<NSString *, id> *)resizeFocusedSegmentBy:(NSInteger)offset {
    @try {
#ifdef MOZC_AVAILABLE
        // TODO(main): 文節伸縮を Mozc へ通知する。
#endif
        return [self stubResultConverting:YES];
    } @catch (NSException *e) {
        NSLog(@"[MozcEngineBridge] resizeFocusedSegmentBy 例外: %@", e);
        return [self emptyResult];
    }
}

- (NSString *)commit {
    @try {
        NSString *committed = NSStringFromStdString(_composition);
        _composition.clear();
#ifdef MOZC_AVAILABLE
        if ([self engineUsable]) {
            // 追加: 直前の候補選択(SubmitCandidate)で既に result が確定している場合は
            // それを確定文字列として使う。ここで再度 Submit すると空コンテキストへの
            // 確定になり result が取れず、よみ(_composition)が返ってしまう不具合を防ぐ。
            if (_lastOutput.has_result() && !_lastOutput.result().value().empty()) {
                committed = NSStringFromStdString(_lastOutput.result().value());
                NSLog(@"[MozcEngineBridge] commit use last result committed='%@'", committed); // 追加(デバッグ)
                _lastOutput.Clear();
                return committed;
            }
            // 確定コマンドを送り、result.value を確定文字列として取得する。
            mozc::commands::Command command;
            _engine->Submit(&command);
            if (command.has_output()) {
                _lastOutput = command.output();
                if (_lastOutput.has_result()) {
                    committed = NSStringFromStdString(_lastOutput.result().value());
                }
            }
            // 追加(デバッグ): commit の Submit 後 result を確認する。
            NSLog(@"[MozcEngineBridge] commit has_output=%d has_result=%d committed='%@'",
                  command.has_output(),
                  _lastOutput.has_result(),
                  committed);
            _lastOutput.Clear();
        }
#endif
        return committed;
    } @catch (NSException *e) {
        NSLog(@"[MozcEngineBridge] commit 例外: %@", e);
        return @"";
    }
}

- (NSDictionary<NSString *, id> *)cancelConversion {
    @try {
#ifdef MOZC_AVAILABLE
        if ([self engineUsable]) {
            mozc::commands::Command command;
            _engine->ResetContext(&command);
            _composition.clear();
            _lastOutput.Clear();
            return [self emptyResult];
        }
#endif
        // かな入力状態（変換前）へ戻す。
        return [self stubResultConverting:NO];
    } @catch (NSException *e) {
        NSLog(@"[MozcEngineBridge] cancelConversion 例外: %@", e);
        return [self emptyResult];
    }
}

#pragma mark - スタブ応答

// 空の変換結果辞書。
- (NSDictionary<NSString *, id> *)emptyResult {
    return @{
        kMozcResultKeyComposition: @"",
        kMozcResultKeyCandidates: @[],
        kMozcResultKeySegments: @[],
        kMozcResultKeyFocusedSegment: @(0),
        kMozcResultKeyIsConverting: @(NO),
    };
}

// 現在の未確定よみをそのまま 1 候補として返す最小スタブ。
// 実 API 未接続時でもブリッジ経路の疎通確認ができるようにする。
// 実用的なかな漢字変換は Swift 側の LocalStubEngine が担当する。
- (NSDictionary<NSString *, id> *)stubResultConverting:(BOOL)converting {
    NSString *composition = NSStringFromStdString(_composition);
    NSArray<NSDictionary *> *candidates = @[];
    if (composition.length > 0) {
        candidates = @[ @{
            kMozcCandidateKeyID: @"stub-0",
            kMozcCandidateKeyValue: composition,
            kMozcCandidateKeyReading: composition,
            kMozcCandidateKeyDescription: [NSNull null],
        } ];
    }
    return @{
        kMozcResultKeyComposition: composition,
        kMozcResultKeyCandidates: candidates,
        kMozcResultKeySegments: @[],
        kMozcResultKeyFocusedSegment: @(0),
        kMozcResultKeyIsConverting: @(converting),
    };
}

#ifdef MOZC_AVAILABLE
#pragma mark - 実 API ヘルパ

// エンジンが初期化済みで使えるか。
- (BOOL)engineUsable {
    return _engineReady && _engine != nullptr;
}

// 直近の Output(_lastOutput) を Swift 契約の辞書へ変換する。
// - composition: preedit の全 segment の value を連結（未確定表示文字列）。
// - candidates: all_candidate_words から id/value/key(=reading) を取り出す。
- (NSDictionary<NSString *, id> *)resultFromLastOutput {
    const mozc::commands::Output &out = _lastOutput;

    // preedit（未確定文字列）を組み立てる。
    std::string composition;
    if (out.has_preedit()) {
        const mozc::commands::Preedit &preedit = out.preedit();
        for (int i = 0; i < preedit.segment_size(); ++i) {
            composition += preedit.segment(i).value();
        }
    }

    // 候補列を組み立てる。
    // 表示用候補は candidate_window に入る（予測/変換で埋まる）。
    // all_candidate_words は全件だが特定状況でしか埋まらないためフォールバックに使う。
    NSMutableArray<NSDictionary *> *candidates = [NSMutableArray array];
    NSString *readingFallback = NSStringFromStdString(composition);
    if (out.has_candidate_window() && out.candidate_window().candidate_size() > 0) {
        const mozc::commands::CandidateWindow &win = out.candidate_window();
        for (int i = 0; i < win.candidate_size(); ++i) {
            const mozc::commands::CandidateWindow::Candidate &c = win.candidate(i);
            [candidates addObject:@{
                kMozcCandidateKeyID: [NSString stringWithFormat:@"%d", c.id()],
                kMozcCandidateKeyValue: NSStringFromStdString(c.value()),
                kMozcCandidateKeyReading: readingFallback,  // candidate_window は key(よみ)を持たない
                kMozcCandidateKeyDescription: [NSNull null],
            }];
        }
    } else if (out.has_all_candidate_words()) {
        const mozc::commands::CandidateList &list = out.all_candidate_words();
        for (int i = 0; i < list.candidates_size(); ++i) {
            const mozc::commands::CandidateWord &c = list.candidates(i);
            NSString *reading = c.has_key() ? NSStringFromStdString(c.key()) : readingFallback;
            [candidates addObject:@{
                kMozcCandidateKeyID: [NSString stringWithFormat:@"%d", c.id()],
                kMozcCandidateKeyValue: NSStringFromStdString(c.value()),
                kMozcCandidateKeyReading: reading,
                kMozcCandidateKeyDescription: [NSNull null],
            }];
        }
    }

    NSString *compositionStr = NSStringFromStdString(composition);
    NSLog(@"[MozcEngineBridge] resultFromLastOutput composition='%@' candidates=%lu (window=%d all=%d)",
          compositionStr, (unsigned long)candidates.count,
          out.has_candidate_window() ? out.candidate_window().candidate_size() : 0,
          out.has_all_candidate_words() ? out.all_candidate_words().candidates_size() : 0); // 追加: 候補件数のデバッグ

    return @{
        kMozcResultKeyComposition: compositionStr,
        kMozcResultKeyCandidates: candidates,
        kMozcResultKeySegments: @[],
        kMozcResultKeyFocusedSegment: @(0),
        kMozcResultKeyIsConverting: @(NO),
    };
}
#endif

@end
