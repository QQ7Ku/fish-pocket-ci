#if DEBUG
import SwiftUI

/// Xcode Previews for the screens people spend their time on. The engine is not
/// started here: these previews show each screen's empty/loading state, which is
/// enough to catch layout and type-checking regressions without a simulator.
/// The real rendered PNG evidence comes from `.github/workflows/ios-preview.yml`.
private let previewURL = URL(string: "http://127.0.0.1:1")!

private extension View {
    /// Every screen reads `AppModel`; most also expect the engine object.
    func previewEnvironment() -> some View {
        environment(AppModel(launchURL: previewURL))
            .environmentObject(NodeEngine.shared)
    }
}

#Preview("主界面") {
    MainView()
        .previewEnvironment()
}

#Preview("会话") {
    ConversationView(sessionId: "preview", selection: .constant(nil))
        .previewEnvironment()
}

#Preview("探索") {
    ExploreTabView(path: .constant([]))
        .previewEnvironment()
}

#Preview("Bot 对话") {
    BotChatView(botId: "preview")
        .previewEnvironment()
}

#Preview("Mini Apps") {
    MiniAppsPage(asTab: true)
        .previewEnvironment()
}

#Preview("插件") {
    PluginsView()
        .previewEnvironment()
}

#Preview("插件商店") {
    PluginStoreView()
        .previewEnvironment()
}

#Preview("定时任务") {
    SchedulesView()
        .previewEnvironment()
}

#Preview("账号与余额") {
    AccountPage()
        .previewEnvironment()
}

#Preview("模型提供商") {
    ModelProvidersPage()
        .previewEnvironment()
}

#Preview("文件") {
    DirectoryView(sessionId: "preview", path: "/", title: "文件", root: nil)
        .previewEnvironment()
}

#Preview("本机能力") {
    NativeCapabilitiesView()
        .previewEnvironment()
}

#Preview("操控手机") {
    PhoneControlView()
        .previewEnvironment()
}

#Preview("添加 API Key") {
    OnboardingKeySheet(ref: "preview", finish: {})
        .previewEnvironment()
}
#endif
