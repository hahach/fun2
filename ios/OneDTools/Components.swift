import SwiftUI
import Core1D

// 共享 UI 件：数值输入行、温标/压强单位输入、结果卡片、提示卡片、输出格式化。
// 本文件只做输入解析（容忍逗号小数点）与展示，不含任何气动数值公式——
// 计算一律走 Core1D。

/// 十进制解析：容忍半角/全角逗号作小数点，容忍首尾空白
func parseDecimal(_ raw: String) -> Double? {
    let cleaned = raw
        .replacingOccurrences(of: "，", with: ".")
        .replacingOccurrences(of: ",", with: ".")
        .trimmingCharacters(in: .whitespaces)
    guard !cleaned.isEmpty else { return nil }
    return Double(cleaned)
}

/// 温度输出：K 与 ℃ 同行双显（℃ 偏移走 Core1D.TempScale，本文件不自带常数）
func dualTemp(_ kelvin: Double) -> String {
    String(format: "%.2f", kelvin) + " K ｜ "
        + String(format: "%.2f", kelvin - TempScale.celsiusOffset) + " ℃"
}

/// 压强输出：按页面压强单位显示（bar 三位小数、Pa 整数），换算走 Core1D.PressureScale
func pressureText(_ pascal: Double, isBar: Bool) -> String {
    isBar ? String(format: "%.3f", PressureScale.fromPascal(pascal, isBar: true)) + " bar"
          : String(format: "%.0f", pascal) + " Pa"
}

/// 数值输入行：大号输入框（小数键盘）+ 单位后缀
struct NumberField: View {
    let label: String
    let unit: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.footnote)
                .foregroundColor(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TextField(unit, text: $text)
                    .keyboardType(.decimalPad)
                    .font(.title2.monospacedDigit())
                Text(unit)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

/// 温度输入行：大号输入框 + K/℃ 分段开关（内部统一开尔文，换算经 Core1D.TempScale）
struct TempField: View {
    let label: String
    @Binding var text: String
    @Binding var isCelsius: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.footnote)
                .foregroundColor(.secondary)
            HStack(spacing: 10) {
                TextField(isCelsius ? "℃" : "K", text: $text)
                    .keyboardType(.decimalPad)
                    .font(.title2.monospacedDigit())
                Picker("温标", selection: $isCelsius) {
                    Text("K").tag(false)
                    Text("℃").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 88)
            }
        }
    }
}

/// 压强输入行：大号输入框 + bar/Pa 分段开关（内部统一帕斯卡，换算经 Core1D.PressureScale）
struct PressureField: View {
    let label: String
    @Binding var text: String
    @Binding var isBar: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.footnote)
                .foregroundColor(.secondary)
            HStack(spacing: 10) {
                TextField(isBar ? "bar" : "Pa", text: $text)
                    .keyboardType(.decimalPad)
                    .font(.title2.monospacedDigit())
                Picker("压强单位", selection: $isBar) {
                    Text("bar").tag(true)
                    Text("Pa").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 108)
            }
        }
    }
}

/// 结果卡片：逐行大号展示；highlight 行用黄色高亮关键输出
struct ResultCard: View {
    struct Row: Identifiable {
        let id = UUID()
        let label: String
        let value: String
        let highlight: Bool

        init(_ label: String, _ value: String, highlight: Bool = false) {
            self.label = label
            self.value = value
            self.highlight = highlight
        }
    }

    let title: String
    let rows: [Row]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.label)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(row.value)
                        .font(.title3.monospacedDigit().weight(row.highlight ? .semibold : .regular))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(row.highlight ? Color.yellow.opacity(0.4) : Color.clear)
                        .cornerRadius(8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(14)
    }
}

/// 提示/报错卡片：黄 = 警告、红 = 报错、灰 = 进行时提示
struct MessageCard: View {
    enum Level {
        case warning, error, hint

        var color: Color {
            switch self {
            case .warning: return .yellow
            case .error: return .red
            case .hint: return .gray
            }
        }

        var icon: String {
            switch self {
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.octagon.fill"
            case .hint: return "info.circle"
            }
        }
    }

    let level: Level
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: level.icon)
                .foregroundColor(level.color == .gray ? .secondary : level.color)
            Text(text)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(level.color.opacity(0.22))
        .cornerRadius(14)
    }
}

/// 输入卡片容器：标题 + 字段纵排
struct InputCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(14)
    }
}

/// 键盘工具栏右侧「完成」按钮：数字键盘没有 return 键，点完成收起键盘
extension View {
    func keyboardDoneBar() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
    }
}
