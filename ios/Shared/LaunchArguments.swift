import Foundation

enum LaunchArguments {
    /// 起動引数つき（-demo や画面写真用）で起動したか。このときは許可の確認を出さない。英語の確認が出て画面写真を隠すため
    static var isScripted: Bool { ProcessInfo.processInfo.arguments.count > 1 }
}
