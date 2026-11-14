import SwiftUI

// 简易热力 —— 气动一维热力计算 App（工作簿三个计算页的手持版 + 历史）。
// 四页签：评估 / 管流 / 总静换算 / 历史。
// 数值计算全部经 Core1D（单一数据源），UI 层只做输入解析与展示。
@main
struct OneDToolsApp: App {
    @StateObject private var history = HistoryStore()

    var body: some Scene {
        WindowGroup {
            TabView {
                EvaluateView()
                    .tabItem { Label("评估", systemImage: "gauge.with.needle") }
                FlowView()
                    .tabItem { Label("管流", systemImage: "wind") }
                ConvView()
                    .tabItem { Label("总静换算", systemImage: "arrow.up.arrow.down") }
                HistoryView()
                    .tabItem { Label("历史", systemImage: "clock.arrow.circlepath") }
            }
            .environmentObject(history)
        }
    }
}
