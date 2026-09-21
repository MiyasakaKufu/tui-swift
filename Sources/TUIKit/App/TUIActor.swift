/// 端末・画面・ビューツリーに触るコードを載せるグローバルアクタ。
@globalActor
public actor TUIActor {
    /// 共有のインスタンス。
    public static let shared = TUIActor()
}
