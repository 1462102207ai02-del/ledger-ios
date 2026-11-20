import SwiftUI

struct ContentView: View {
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
