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
#include <limits>

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
    BOOL _converting;
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
        _converting = NO;
#ifdef MOZC_AVAILABLE
        _engineReady = NO;
        @try {
            std::string path = StdStringFromNSString(dataPath);
            _engine = std::make_unique<mozc::ios::IosEngine>(path);
            // モバイル用リクエスト(12キー フリック)を設定し、モバイル設定を反映してセッション作成。
            mozc::commands::Command command;
            _engine->SetMobileRequest("QWERTY_JA", &command); // Swift resolves kana/flicks before sending text.
            mozc::config::Config config;
            mozc::ios::IosEngine::FillMobileConfig(&config);
            config.set_suggestions_size(20);
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
    return [self engineUsable];
#else
    return NO;
#endif
}

- (void)reset {
    @try {
        _composition.clear();
        _converting = NO;
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

- (void)setAlphabetInput:(BOOL)alphabet {
#ifdef MOZC_AVAILABLE
    if ([self engineUsable]) {
        _engine->SwitchInputMode(alphabet ? mozc::ios::IosEngine::InputMode::ALPHABET
                                         : mozc::ios::IosEngine::InputMode::HIRAGANA);
    }
#endif
}

- (void)setLearningEnabled:(BOOL)enabled {
#ifdef MOZC_AVAILABLE
    if ([self engineUsable]) {
        mozc::config::Config config;
        mozc::ios::IosEngine::FillMobileConfig(&config);
        config.set_suggestions_size(20);
        config.set_incognito_mode(!enabled);
        config.set_history_learning_level(enabled ? mozc::config::Config::DEFAULT_HISTORY
                                                 : mozc::config::Config::NO_HISTORY);
        mozc::commands::Command command;
        _engine->SetConfig(config, &command);
    }
#endif
}

- (void)insertText:(NSString *)text {
    @try {
        if (_converting) { [self cancelConversion]; }
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
        if (_converting) { [self cancelConversion]; }
        NSString *reading = NSStringFromStdString(_composition);
        if (reading.length > 0) {
            NSRange last = [reading rangeOfComposedCharacterSequenceAtIndex:reading.length - 1];
            _composition = StdStringFromNSString([reading substringToIndex:last.location]);
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
            if (_composition.empty()) { return [self resultFromLastOutput]; }
            mozc::commands::Command command;
            _engine->SendSpecialKey(mozc::commands::KeyEvent::SPACE, &command);
            if (command.has_output()) {
                _lastOutput = command.output();
                _converting = _lastOutput.has_preedit();
            }
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
            // Reject synthetic, malformed and stale IDs ("compo" must never become 0).
            NSScanner *scanner = [NSScanner scannerWithString:candidateID];
            long long parsed = 0;
            scanner.charactersToBeSkipped = nil;
            if (![scanner scanLongLong:&parsed] || !scanner.isAtEnd ||
                parsed < std::numeric_limits<int>::min() || parsed > std::numeric_limits<int>::max()) {
                return [self resultFromLastOutput];
            }
            BOOL found = NO;
            for (NSDictionary *candidate in [self resultFromLastOutput][kMozcResultKeyCandidates]) {
                if ([candidate[kMozcCandidateKeyID] isEqualToString:candidateID]) { found = YES; break; }
            }
            if (!found) { return [self resultFromLastOutput]; }
            int index = (int)parsed;
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
        if ([self engineUsable] && _converting) {
            mozc::commands::Command command;
            for (NSInteger i = 0; i < labs(offset); ++i) {
                _engine->SendSpecialKey(offset < 0 ? mozc::commands::KeyEvent::LEFT
                                                  : mozc::commands::KeyEvent::RIGHT, &command);
                if (command.has_output()) { _lastOutput = command.output(); }
            }
            return [self resultFromLastOutput];
        }
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
        if ([self engineUsable]) { return [self resultFromLastOutput]; } // Boundary resizing is not exposed by this keyboard.
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
        _converting = NO;
#ifdef MOZC_AVAILABLE
        if ([self engineUsable]) {
            // A mobile prediction may commit only a prefix. Preserve that result
            // and submit any remaining preedit instead of dropping the suffix.
            NSString *prefix = _lastOutput.has_result() ? NSStringFromStdString(_lastOutput.result().value()) : @"";
            if (prefix.length > 0 && (!_lastOutput.has_preedit() || _lastOutput.preedit().segment_size() == 0)) {
                _lastOutput.Clear();
                return prefix;
            }
            // 確定コマンドを送り、result.value を確定文字列として取得する。
            mozc::commands::Command command;
            _engine->Submit(&command);
            if (command.has_output()) {
                _lastOutput = command.output();
                if (_lastOutput.has_result()) {
                    committed = [prefix stringByAppendingString:NSStringFromStdString(_lastOutput.result().value())];
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
            if (_converting) {
                _engine->SendSpecialKey(mozc::commands::KeyEvent::ESCAPE, &command);
                if (command.has_output()) { _lastOutput = command.output(); }
            }
            _converting = NO;
            return [self resultFromLastOutput];
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

    const auto &preedit = out.preedit();
    NSInteger focused = 0;
    for (int i = 0; i < preedit.segment_size(); ++i) {
        if (preedit.segment(i).annotation() == mozc::commands::Preedit::Segment::HIGHLIGHT) { focused = i; break; }
    }
    NSString *readingFallback = NSStringFromStdString(_composition);
    if (_converting && preedit.segment_size() > focused && preedit.segment((int)focused).has_key()) {
        readingFallback = NSStringFromStdString(preedit.segment((int)focused).key());
    }
    NSMutableArray<NSDictionary *> *candidates = [NSMutableArray array];
    NSMutableSet<NSString *> *ids = [NSMutableSet set];
    // Prefer the full list; the window can contain just the visible page.
    for (const auto &c : out.all_candidate_words().candidates()) {
        if (!c.has_id() || !c.has_value()) { continue; }
        NSString *candidateID = [NSString stringWithFormat:@"%d", c.id()];
        [ids addObject:candidateID];
        [candidates addObject:@{
            kMozcCandidateKeyID: candidateID,
            kMozcCandidateKeyValue: NSStringFromStdString(c.value()),
            kMozcCandidateKeyReading: c.has_key() ? NSStringFromStdString(c.key()) : readingFallback,
            kMozcCandidateKeyDescription: NSStringFromStdString(c.annotation().description()),
        }];
    }
    for (const auto &c : out.candidate_window().candidate()) {
        NSString *candidateID = [NSString stringWithFormat:@"%d", c.id()];
        if (!c.has_id() || [ids containsObject:candidateID]) { continue; }
        [ids addObject:candidateID];
        [candidates addObject:@{
            kMozcCandidateKeyID: candidateID,
            kMozcCandidateKeyValue: NSStringFromStdString(c.value()),
            kMozcCandidateKeyReading: readingFallback,
            kMozcCandidateKeyDescription: NSStringFromStdString(c.annotation().description()),
        }];
    }
    NSMutableArray *segments = [NSMutableArray array];
    if (_converting) {
        for (int i = 0; i < preedit.segment_size(); ++i) {
            const auto &segment = preedit.segment(i);
            NSString *value = NSStringFromStdString(segment.value());
            NSString *reading = segment.has_key() ? NSStringFromStdString(segment.key()) : value;
            NSDictionary *selected = nil;
            if (i == focused) {
                for (NSDictionary *candidate in candidates) {
                    if ([candidate[kMozcCandidateKeyValue] isEqualToString:value]) { selected = candidate; break; }
                }
            }
            selected = selected ?: @{kMozcCandidateKeyID: [NSString stringWithFormat:@"segment:%d", i],
                                     kMozcCandidateKeyValue: value, kMozcCandidateKeyReading: reading};
            [segments addObject:@{kMozcSegmentKeyReading: reading, kMozcSegmentKeySelected: selected,
                                 kMozcSegmentKeyCandidates: i == focused ? candidates : @[selected]}];
        }
    }
    return @{
        kMozcResultKeyComposition: NSStringFromStdString(_composition),
        kMozcResultKeyCandidates: candidates,
        kMozcResultKeySegments: segments,
        kMozcResultKeyFocusedSegment: @(focused),
        kMozcResultKeyIsConverting: @(_converting),
    };
}
#endif

@end
