// MozcFlickShared.h — フレームワークのアンブレラヘッダ。
// 公開する Objective-C(++) ヘッダをここへ集約し、
// 同一フレームワーク内の Swift から MozcEngineBridge を可視にする。
// （framework ターゲットは Swift bridging header を使えないため、この方式を採る）

#import <Foundation/Foundation.h>

FOUNDATION_EXPORT double MozcFlickSharedVersionNumber;
FOUNDATION_EXPORT const unsigned char MozcFlickSharedVersionString[];

#import <MozcFlickShared/MozcEngineBridge.h>
