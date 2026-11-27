import SwiftUI

enum AppTab: Int {
    case add = 0
    case records = 1
    case statistics = 2
    case settings = 3
}

struct ContentView: View {
    @State private var selection: AppTab = .add
    /// 小组件点进来时递增，让「记一笔」自动聚焦金额输入框。
    @State private var addFocusToken = 0

    init() {
        // iOS 15+ 滚动内容经过底栏时，系统会把 TabBar 切成透明的
        // scrollEdgeAppearance，导致列表文字从底栏背后透出。
        // 这里强制指定不透明外观，覆盖该行为（systemBackground 自动适配深浅色）。
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor.systemBackground
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView(selection: $selection) {
            AddRecordView(focusToken: addFocusToken)
                .tabItem { Label("记一笔", systemImage: "plus.circle.fill") }
                .tag(AppTab.add)
            RecordsView()
                .tabItem { Label("明细", systemImage: "list.bullet") }
                .tag(AppTab.records)
            StatisticsView()
                .tabItem { Label("统计", systemImage: "chart.bar.fill") }
                .tag(AppTab.statistics)
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .onOpenURL { url in
            guard url.scheme?.lowercased() == "ledger" else { return }
            if url.host == "add" {
                selection = .add
                addFocusToken += 1
            }
        }
    }
}
