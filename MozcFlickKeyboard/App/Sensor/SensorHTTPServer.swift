// SensorHTTPServer.swift
// MozcFlickKeyboard — 追加: 同一 LAN の MacBook から疑似センサーイベントを受け取る最小 HTTP サーバー。
//
// 目的: 実機の IoT センサーが無い段階でも、Python CLI（tools/sensor_inject.py）から
//       玄関開閉・トイレ・床材質・温度のイベントを注入して研究フローを動かせるようにする。
//
// 実装方針:
//  - 外部ライブラリを使わず Network.framework（NWListener + TCP）だけで組む。
//  - 受け付けるのは POST /sensor のみ。body の JSON を SensorEvent としてデコードし onEvent へ渡す。
//  - レスポンスは常に 200 {"ok":true}（CLI 側を単純に保つ）。不正 body でも 400 を返して切断するだけ。
//
// iOS の制約（重要）:
//  - アプリが前面にある間だけ受信できる。バックグラウンド・キーボード拡張では待ち受けできない。
//    そのため SceneDelegate の active/background に合わせて start/stop する。
//  - iOS 14+ は LAN アクセスに Info.plist の NSLocalNetworkUsageDescription とユーザー許可が必要。

import Foundation
import Network // 追加: NWListener による TCP 待ち受け
import MozcFlickShared // 追加: SensorEvent / SensorEventRouter / NarrativeJSON を利用

/// 追加: 疑似センサーイベントを LAN 経由で受信する軽量 HTTP サーバー。
final class SensorHTTPServer {

    /// 追加: アプリ全体で1つだけ使う共有インスタンス（SceneDelegate と各画面から参照する）。
    static let shared = SensorHTTPServer()

    /// 追加: 待ち受けリスナー。停止中は nil。
    private var listener: NWListener?

    /// 追加: 接続処理を回す専用キュー。
    private let queue = DispatchQueue(label: "MozcFlick.SensorHTTPServer")

    /// 追加: 受信イベントを振り分けるルーター（Shared 側の実装を使う）。
    private let router = SensorEventRouter()

    /// 追加: 現在待ち受け中か（設定画面・Dashboard の表示に使う）。
    private(set) var isRunning = false

    /// 追加: 実際に待ち受けているポート。停止中は nil。
    private(set) var activePort: UInt16?

    /// 追加: イベントを受信したときに UI 側へ知らせるコールバック（Dashboard の再描画用）。
    var onEventReceived: ((SensorEvent) -> Void)?

    private init() {}

    // MARK: - 開始 / 停止

    /// 追加: 指定ポートで待ち受けを開始する。既に稼働中なら何もしない。
    func start(port: Int) {
        guard listener == nil else { return } // 追加: 二重起動を防ぐ
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(truncatingIfNeeded: port)) else {
            NSLog("[MFK-Sensor] invalid port=\(port)") // 追加: ポート不正
            return
        }
        // 追加: TCP のみ（TLS なし）。LAN 内の疑似センサー注入専用なので平文で受ける。
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true // 追加: 再起動時に「アドレス使用中」で失敗しないようにする
        guard let l = try? NWListener(using: params, on: nwPort) else {
            NSLog("[MFK-Sensor] listener create failed port=\(port)") // 追加: 生成失敗
            return
        }
        l.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection) // 追加: 1接続 = 1リクエストとして処理
        }
        l.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.isRunning = true
                self?.activePort = nwPort.rawValue
                NSLog("[MFK-Sensor] listening on port=\(nwPort.rawValue)") // 追加: 待ち受け開始
            case .failed(let error):
                NSLog("[MFK-Sensor] listener failed: \(error)") // 追加: 失敗（権限拒否・ポート衝突など）
                self?.stop()
            case .cancelled:
                self?.isRunning = false
                self?.activePort = nil
                NSLog("[MFK-Sensor] listener cancelled") // 追加: 停止
            default:
                break
            }
        }
        listener = l
        l.start(queue: queue)
    }

    /// 追加: 待ち受けを停止する（アプリが背面へ回ったときなど）。
    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        activePort = nil
        NSLog("[MFK-Sensor] stop") // 追加: 停止デバッグ
    }

    // MARK: - 接続処理

    /// 追加: 1接続を受け取り、HTTP リクエストを1つ読んで応答して閉じる。
    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        // 追加: リクエスト全体を1回の受信で読む（CLI が送る JSON は小さいので十分）。
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, _ in
            guard let self else { return }
            guard let data, let request = String(data: data, encoding: .utf8) else {
                self.respond(connection: connection, status: "400 Bad Request", body: "{\"ok\":false}")
                return
            }
            self.process(request: request, connection: connection)
        }
    }

    /// 追加: 生の HTTP テキストを解釈し、POST /sensor なら body を SensorEvent として処理する。
    private func process(request: String, connection: NWConnection) {
        // 追加: リクエスト行（"POST /sensor HTTP/1.1"）を確認する。
        let isSensorPost = request.hasPrefix("POST /sensor")
        guard isSensorPost else {
            NSLog("[MFK-Sensor] ignored request (not POST /sensor)") // 追加: 想定外パス
            respond(connection: connection, status: "404 Not Found", body: "{\"ok\":false}")
            return
        }
        // 追加: ヘッダと body は空行（\r\n\r\n）で区切られる。body だけを取り出す。
        guard let separatorRange = request.range(of: "\r\n\r\n") else {
            respond(connection: connection, status: "400 Bad Request", body: "{\"ok\":false}")
            return
        }
        let body = String(request[separatorRange.upperBound...])
        guard let bodyData = body.data(using: .utf8),
              let event = try? NarrativeJSON.decoder.decode(SensorEvent.self, from: bodyData) else {
            NSLog("[MFK-Sensor] body decode failed body=\(body)") // 追加: JSON 不正
            respond(connection: connection, status: "400 Bad Request", body: "{\"ok\":false}")
            return
        }
        // 追加: 振り分け（キュー投入 + ContextEvent 保存）はメインスレッド外でも安全だが、
        //       UI 通知のためコールバックはメインへ回す。
        router.route(event)
        DispatchQueue.main.async { [weak self] in
            self?.onEventReceived?(event)
        }
        respond(connection: connection, status: "200 OK", body: "{\"ok\":true}")
    }

    /// 追加: 最小限の HTTP レスポンスを返して接続を閉じる。
    private func respond(connection: NWConnection, status: String, body: String) {
        let response = """
        HTTP/1.1 \(status)\r
        Content-Type: application/json\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel() // 追加: 1リクエストごとに閉じる
        })
    }

    // MARK: - LAN IP 取得（設定画面での表示用）

    /// 追加: 現在の Wi-Fi(en0) の IPv4 アドレスを返す。取得できなければ nil。
    /// Python CLI の --host にこの値を渡してもらう。
    static func currentWiFiIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        var pointer = first
        while true {
            let interface = pointer.pointee
            let family = interface.ifa_addr.pointee.sa_family
            // 追加: IPv4 かつ Wi-Fi インターフェース(en0) のものを採用する。
            if family == UInt8(AF_INET), String(cString: interface.ifa_name) == "en0" {
                var addr = interface.ifa_addr.pointee
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(&addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                               &hostname, socklen_t(hostname.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    address = String(cString: hostname)
                }
            }
            guard let next = interface.ifa_next else { break }
            pointer = next
        }
        freeifaddrs(ifaddr)
        return address
    }
}
