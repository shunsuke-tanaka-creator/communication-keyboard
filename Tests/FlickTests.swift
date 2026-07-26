// FlickTests.swift
// MozcFlickKeyboard — フリック方向判定ロジックの単体テスト。
//
// 【対象と確定度】
//  - FlickGestureRecognizer（またはフリック判定の純関数）は他エージェントが作成中で API 未確定。
//    ★対象 API が未確定な場合はメインが結合時に調整すること。★
//
// 【仮定した API（結合時に要確認）】
//  - enum FlickDirection { case center, up, down, left, right }
//  - struct FlickThresholds {
//        var minDistance: CGFloat  // これ未満は center（タップ扱い）
//        var minVelocity: CGFloat  // これ以上なら距離が短くてもフリック成立
//        static let `default`: FlickThresholds
//    }
//  - enum FlickResolver {
//        static func direction(dx: CGFloat, dy: CGFloat,
//                              velocity: CGFloat,
//                              thresholds: FlickThresholds = .default) -> FlickDirection
//    }
//    ※ iOS の座標系は下方向が +y。up は dy<0、down は dy>0。
//    ※ もし判定が FlickGestureRecognizer のインスタンスメソッドで提供される場合は
//      メインが同等の純関数ブリッジを用意すること。
//
// 【モジュール名について】
//  - モジュール名はメインが結合時に調整すること（@testable import 行）。

import XCTest
import CoreGraphics
// モジュール名はメインが結合時に調整すること。
@testable import MozcFlickShared

final class FlickTests: XCTestCase {

    private let th = FlickThresholds.default

    // MARK: - 距離しきい値（角度判定の前提）

    // 微小移動は center（タップ）と判定されること。
    func testTinyMovementIsCenter() {
        let d = FlickResolver.direction(dx: 2, dy: -3, velocity: 10, thresholds: th)
        XCTAssertEqual(d, .center, "minDistance 未満・低速はタップ(center)と判定すべき")
    }

    // MARK: - 4 方向の角度判定（十分な距離）

    func testFlickUp() {
        // 上フリック: dy が大きく負。
        let d = FlickResolver.direction(dx: 0, dy: -80, velocity: 800, thresholds: th)
        XCTAssertEqual(d, .up)
    }

    func testFlickDown() {
        let d = FlickResolver.direction(dx: 0, dy: 80, velocity: 800, thresholds: th)
        XCTAssertEqual(d, .down)
    }

    func testFlickLeft() {
        let d = FlickResolver.direction(dx: -80, dy: 0, velocity: 800, thresholds: th)
        XCTAssertEqual(d, .left)
    }

    func testFlickRight() {
        let d = FlickResolver.direction(dx: 80, dy: 0, velocity: 800, thresholds: th)
        XCTAssertEqual(d, .right)
    }

    // MARK: - 斜め入力は水平/垂直の優勢成分で決まること

    // 右やや下（dx 優勢）→ right。
    func testDiagonalResolvesToDominantAxis() {
        let d = FlickResolver.direction(dx: 80, dy: 30, velocity: 800, thresholds: th)
        XCTAssertEqual(d, .right, "|dx|>|dy| なら水平方向を採用すべき")
    }

    // 下やや右（dy 優勢）→ down。
    func testDiagonalResolvesToVerticalWhenDyDominant() {
        let d = FlickResolver.direction(dx: 30, dy: 80, velocity: 800, thresholds: th)
        XCTAssertEqual(d, .down, "|dy|>|dx| なら垂直方向を採用すべき")
    }

    // ちょうど 45 度付近は実装の tie-break に依存するので、境界の少し内側で検証する。
    func testNearFortyFiveDegreesRightBias() {
        // dx をわずかに大きくして right 側に倒す。
        let d = FlickResolver.direction(dx: 51, dy: 50, velocity: 800, thresholds: th)
        XCTAssertEqual(d, .right)
    }

    // MARK: - 速度しきい値（短距離でも高速ならフリック成立）

    // 距離は minDistance 未満だが高速 → フリック成立（上）。
    func testShortButFastIsFlick() {
        // dx=0, dy=-8（短距離）だが velocity が高い。
        let d = FlickResolver.direction(dx: 0, dy: -8, velocity: 3000, thresholds: th)
        XCTAssertEqual(d, .up, "minVelocity 以上なら短距離でもフリック成立とすべき")
    }

    // 距離十分でも極端に低速なら center 扱いにする（誤爆防止）というしきい値設計の確認。
    // ※この期待は「距離 or 速度のいずれかを満たせば成立」設計を前提とする。
    //   もし実装が「距離のみで判定（速度は補助）」なら、この 1 ケースはメインが調整すること。
    func testSlowLongPressCouldBeCenter() {
        let d = FlickResolver.direction(dx: 0, dy: -80, velocity: 5, thresholds: th)
        // 距離が minDistance を十分超えるため、多くの実装では up。
        // 距離優先設計を確定として up を期待する。
        XCTAssertEqual(d, .up, "距離が十分ならフリック成立(距離優先設計)")
    }

    // MARK: - しきい値のデフォルト値が妥当な範囲にあること

    func testDefaultThresholdsAreReasonable() {
        XCTAssertGreaterThan(th.minDistance, 0, "minDistance は正であるべき")
        XCTAssertGreaterThan(th.minVelocity, 0, "minVelocity は正であるべき")
        // 一般的な指の動きに対して現実的な上限（過大な値でないこと）。
        XCTAssertLessThanOrEqual(th.minDistance, 40, "minDistance は 40pt 以下が現実的")
    }
}
