#!/usr/bin/env python3
# 疑似 IoT センサーイベントを同一 LAN の iPhone 親アプリへ HTTP POST で注入する CLI。
# 標準ライブラリのみを使用（third-party 依存なし）。
import argparse
import json
import sys
import urllib.error
import urllib.request
from datetime import datetime

DEFAULT_PORT = 8770
DEFAULT_TIMEOUT = 5

# サブコマンド名 -> 実際に送信する type 名
TYPE_MAP = {
    "door_open": "door_open",
    "door_close": "door_close",
    "toilet": "toilet",
    "temp": "temperature",
    "presence": "living_presence",  # 変更: 在室検知センサー（present / absent）
}

# 対話モードのメニュー: 番号 -> (表示ラベル, サブコマンド名, value)
MENU = {
    "1": ("玄関を開けた(外出)", "door_open", None),
    "2": ("玄関を閉めた(帰宅)", "door_close", None),
    "3": ("トイレ", "toilet", None),
    "4": ("温度 high", "temp", "high"),
    "5": ("温度 mid", "temp", "mid"),
    "6": ("温度 low", "temp", "low"),
    "7": ("在室（present）", "presence", "present"),  # 変更: 在室検知（1タップで送信）
    "8": ("不在（absent）", "presence", "absent"),  # 追加: 不在も1タップで送信
}


def now_iso8601():
    # 例: 2026-09-15T01:50:00.000+0900（ミリ秒 + タイムゾーンオフセット）
    now = datetime.now().astimezone()
    return now.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + now.strftime("%z")


def send_event(host, port, timeout, wire_type, value):
    # /sensor へ JSON を POST し、成功/失敗を標準出力に表示する
    payload = {"type": wire_type, "value": value, "at": now_iso8601()}
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    url = "http://{}:{}/sensor".format(host, port)
    req = urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as res:
            print("[OK] {} sent type={} value={}".format(res.status, wire_type, value))
            print("     payload={}".format(json.dumps(payload, ensure_ascii=False)))
            return True
    except urllib.error.HTTPError as e:
        print("[NG] HTTP {} {}".format(e.code, e.reason))
    except urllib.error.URLError as e:
        print("[NG] 接続できません: {}".format(e.reason))
    except TimeoutError:
        print("[NG] タイムアウト（{}秒）".format(timeout))
    except OSError as e:
        print("[NG] 通信エラー: {}".format(e))
    print("     ヒント: 親アプリを前面で開いていますか / IP({}) とポート({}) が合っていますか / "
          "初回のローカルネットワーク許可を許可しましたか / iPhone と Mac が同じ Wi-Fi ですか"
          .format(host, port))
    return False


def run_interactive(host, port, timeout):
    # 引数でサブコマンドを指定しなかった場合の対話ループ
    print("対話モード: 送信したいイベントの番号を入力してください（q で終了）")
    while True:
        for key in sorted(MENU):
            print("  {}: {}".format(key, MENU[key][0]))
        print("  q: 終了")
        choice = input("> ").strip()
        if choice in ("q", "quit", "exit"):
            print("終了します。")
            return 0
        if choice not in MENU:
            print("[NG] 不正な入力です: {}".format(choice))
            continue
        _label, name, value = MENU[choice]
        send_event(host, port, timeout, TYPE_MAP[name], value)


def build_parser():
    parser = argparse.ArgumentParser(
        description="疑似 IoT センサーイベントを iPhone 親アプリへ注入する（同一 LAN）"
    )
    parser.add_argument("--host", help="iPhone の LAN IP（親アプリの 設定 画面に表示されます）")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="受信ポート（既定: 8770）")
    parser.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT, help="タイムアウト秒（既定: 5）")
    sub = parser.add_subparsers(dest="command")
    sub.add_parser("door_open", help="玄関を開けた（外出）")
    sub.add_parser("door_close", help="玄関を閉めた（帰宅）")
    sub.add_parser("toilet", help="トイレ（記録のみ）")
    p_temp = sub.add_parser("temp", help="温度（high/low で疲労チェック、mid は記録のみ）")
    p_temp.add_argument("--value", required=True, choices=["high", "mid", "low"])
    p_presence = sub.add_parser("presence", help="リビング在室検知（記録のみ）")  # 変更: 在室検知サブコマンド
    p_presence.add_argument("--value", required=True, choices=["present", "absent"],
                            help="在室状況（present=在室 / absent=不在）")  # 変更: present / absent の選択のみ許可
    return parser


def main(argv):
    args = build_parser().parse_args(argv)
    if not args.host:
        print("[NG] --host を指定してください（iPhone の LAN IP）。")
        print("     IP は親アプリの 設定 画面に表示されます。")
        print("     例: python3 tools/sensor_inject.py --host 192.168.1.23 door_open")
        return 2
    if args.command is None:
        return run_interactive(args.host, args.port, args.timeout)
    value = getattr(args, "value", None)
    ok = send_event(args.host, args.port, args.timeout, TYPE_MAP[args.command], value)
    return 0 if ok else 1


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        print("\n中断しました。")
        sys.exit(130)
    except EOFError:
        print("\n入力が終了しました。")
        sys.exit(0)
