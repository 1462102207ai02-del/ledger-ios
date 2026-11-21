import SwiftUI

struct ContentView: View {
    @Binding var showOCR: Bool

    init(showOCR: Binding<Bool> = .constant(false)) {
        _showOCR = showOCR
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
        TabView {
            AddRecordView()
                .tabItem { Label("记一笔", systemImage: "plus.circle.fill") }
            RecordsView()
                .tabItem { Label("明细", systemImage: "list.bullet") }
            StatisticsView()
                .tabItem { Label("统计", systemImage: "chart.bar.fill") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
    }
}
