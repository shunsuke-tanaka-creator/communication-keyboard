// FlickGestureRecognizer.swift
// MozcFlickKeyboard — フリック方向判定ロジック（距離/速度/角度のしきい値をパラメータ化）。
//
// 純粋なジオメトリ計算として分離し、FlickKeyButton から利用する。
// 誤フリック抑制（短すぎる移動をタップ扱い）や、対角線の角度判定をここで一元管理する。

import CoreGraphics

/// フリック判定のパラメータ。端末サイズや設定に応じて調整可能。
public struct FlickThresholds: Sendable {
    /// これ未満の移動距離(pt)はタップ（中央）とみなす。誤フリック抑制。
    public var minDistance: CGFloat
    /// フリックと確定するための最小速度(pt/s)。距離が十分なら速度は不問にできる。
    public var minVelocity: CGFloat
    /// 距離がこれ以上なら速度に関わらずフリック確定。
    public var confirmDistance: CGFloat

    public init(minDistance: CGFloat = 10,
                minVelocity: CGFloat = 120,
                confirmDistance: CGFloat = 18) {
        self.minDistance = minDistance
        self.minVelocity = minVelocity
        self.confirmDistance = confirmDistance
    }

    public static let standard = FlickThresholds()
    /// 別名（既定値）。テスト・呼び出し側の可読性のため。
    public static let `default` = FlickThresholds()
}

/// フリック方向判定の純関数群。
public enum FlickGesture {

    /// 移動ベクトルと速度から FlickDirection を判定する。
    /// - Parameters:
    ///   - translation: 開始点からの移動量。
    ///   - velocity: 指の移動速度(pt/s)。速度不明なら .zero を渡す。
    ///   - thresholds: 判定しきい値。
    /// - Returns: 中央(タップ)なら .center、方向確定ならその方向。
    public static func direction(translation: CGPoint,
                                 velocity: CGPoint = .zero,
                                 thresholds: FlickThresholds = .standard,
                                 previousDirection: FlickDirection = .center) -> FlickDirection {
        let distance = hypot(translation.x, translation.y)
        let speed = hypot(velocity.x, velocity.y)

        // A short deliberate stroke works even when a slow touch has no velocity.
        // Ignore high velocity for tiny (< 6pt) jitter. Once selected, keep the
        // direction until the finger returns near the origin or crosses a clear axis.
        if previousDirection != .center && distance >= thresholds.minDistance * 0.5 {
            switch previousDirection {
            case .left where translation.x < 0, .right where translation.x > 0:
                if abs(translation.y) < abs(translation.x) * 1.25 { return previousDirection }
            case .up where translation.y < 0, .down where translation.y > 0:
                if abs(translation.x) < abs(translation.y) * 1.25 { return previousDirection }
            default: break
            }
        }
        let isFlick = distance >= thresholds.minDistance || distance >= thresholds.confirmDistance
            || (distance >= 6 && speed >= thresholds.minVelocity)
        guard isFlick else { return .center }

        // 角度で 4 方向へ量子化（上下左右）。画面座標は y が下方向に増加する点に注意。
        let angle = atan2(translation.y, translation.x) // -π...π, 右=0, 下=+π/2
        let deg = angle * 180 / .pi

        // 右: -45..45, 下: 45..135, 左: 135..180 / -180..-135, 上: -135..-45
        switch deg {
        case -45..<45:
            return .right
        case 45..<135:
            return .down
        case -135..<(-45):
            return .up
        default:
            return .left
        }
    }
}

/// テスト・呼び出し側向けのスカラー引数フリック判定。
/// dx/dy と速度スカラーから FlickGesture.direction へ委譲する薄いラッパ。
public enum FlickResolver {
    /// - Parameters:
    ///   - dx: X 方向移動量(pt)。右が正。
    ///   - dy: Y 方向移動量(pt)。iOS 座標系で下が正（上フリックは dy<0）。
    ///   - velocity: 速度スカラー(pt/s)。
    ///   - thresholds: 判定しきい値。
    public static func direction(dx: CGFloat,
                                 dy: CGFloat,
                                 velocity: CGFloat,
                                 thresholds: FlickThresholds = .default) -> FlickDirection {
        // 速度スカラーを移動方向へ射影したベクトルとして渡す（方向は translation で決まる）。
        let distance = hypot(dx, dy)
        let vx: CGFloat = distance > 0 ? dx / distance * velocity : 0
        let vy: CGFloat = distance > 0 ? dy / distance * velocity : 0
        return FlickGesture.direction(translation: CGPoint(x: dx, y: dy),
                                      velocity: CGPoint(x: vx, y: vy),
                                      thresholds: thresholds)
    }
}

/// Accumulates small drag movements without losing the remainder or jumping on reversal.
public struct CursorDragState {
    private var remainder: CGFloat = 0
    public var pointsPerCharacter: CGFloat = 10
    public init() {}
    public mutating func move(by delta: CGFloat) -> Int {
        remainder += delta
        let steps = Int(remainder / max(pointsPerCharacter, 1))
        remainder -= CGFloat(steps) * max(pointsPerCharacter, 1)
        return steps
    }
}
