import SwiftUI
import Core1D

// 总静换算页：五槽（T0/P0/T/P/M）任填 3，实时自动判况与输出；
// 警告/报错按 ConvSolver 结果用黄/红卡片展示。
// 计算全部经 Core1D.ConvSolver，本页无数值公式。
struct ConvView: View {
    @StateObject private var form = ConvForm.load()
    @EnvironmentObject private var history: HistoryStore

    private let solver = ConvSolver(model: .standard())

    /// 情况编号 → 已知/求解描述（与工作簿 G 列描述一致，纯文案）
    private static let legend: [Int: (known: String, solve: String)] = [
        1: ("T0,P0,M", "T,P"),
        2: ("T0,P0,T", "M,P"),
        3: ("T0,P0,P", "T,M"),
        4: ("T0,T,M", "P0/P"),
        5: ("T0,T,P", "M,P0"),
        6: ("T0,P,M", "T,P0"),
        7: ("P0,T,M", "T0,P"),
        8: ("P0,P,M", "T,T0"),
        9: ("P0,P,T", "T0,M"),
        10: ("T,P,M", "T0,P0"),
    ]

    private var result: ConvResult {
        solver.solve(ConvInput(
            T0: parseDecimal(form.t0).map { TempScale.toKelvin($0, isCelsius: form.t0Celsius) },
            P0: parseDecimal(form.p0).map { PressureScale.toPascal($0, isBar: form.pressureIsBar) },
            T: parseDecimal(form.t).map { TempScale.toKelvin($0, isCelsius: form.tCelsius) },
            P: parseDecimal(form.p).map { PressureScale.toPascal($0, isBar: form.pressureIsBar) },
            M: parseDecimal(form.m)))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    InputCard(title: "五槽输入（任填 3 个）") {
                        TempField(label: "总温 T0", text: $form.t0, isCelsius: $form.t0Celsius)
                        PressureField(label: "总压 P0", text: $form.p0, isBar: $form.pressureIsBar)
                        TempField(label: "静温 T", text: $form.t, isCelsius: $form.tCelsius)
                        PressureField(label: "静压 P", text: $form.p, isBar: $form.pressureIsBar)
                        NumberField(label: "马赫数 M", unit: "—", text: $form.m)
                    }
                    resultArea
                }
                .padding()
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("总静换算")
            .keyboardDoneBar()
        }
    }

    @ViewBuilder
    private var resultArea: some View {
        let r = result
        if r.valid {
            if let id = r.caseId, let legend = Self.legend[id] {
                Text("情况 \(id)：已知 \(legend.known) → 求解 \(legend.solve)")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ResultCard(title: "换算结果", rows: outputRows(r))
            if !r.message.isEmpty {
                MessageCard(level: .warning, text: r.message)
            }
            Button("存历史") {
                history.add(page: "总静换算·情况\(r.caseId.map(String.init) ?? "?")",
                            inputs: inputSnapshot, outputs: outputSnapshot(r))
            }
            .buttonStyle(.bordered)
        } else {
            switch r.severity {
            case .error:
                MessageCard(level: .error, text: r.message)
            case .warning:
                MessageCard(level: .warning, text: r.message)
            case .hint:
                MessageCard(level: .hint, text: r.message)
            case .plain:
                MessageCard(level: .hint, text: "继续填入参数，满 3 个自动判况")
            }
        }
    }

    private func outputRows(_ r: ConvResult) -> [ResultCard.Row] {
        var rows = [ResultCard.Row]()
        if let v = r.T { rows.append(.init("静温 T", dualTemp(v), highlight: true)) }
        if let v = r.T0 { rows.append(.init("总温 T0", dualTemp(v), highlight: true)) }
        if let v = r.P { rows.append(.init("静压 P", pressureText(v, isBar: form.pressureIsBar))) }
        if let v = r.P0 { rows.append(.init("总压 P0", pressureText(v, isBar: form.pressureIsBar))) }
        if let v = r.M { rows.append(.init("马赫数 M", String(format: "%.4f", v))) }
        if let v = r.p0OverP {
            rows.append(.init("总静压比 P0/P", String(format: "%.4f", v), highlight: true))
        }
        return rows
    }

    private func outputSnapshot(_ r: ConvResult) -> [String: String] {
        var d = [String: String]()
        if let v = r.T { d["T"] = dualTemp(v) }
        if let v = r.T0 { d["T0"] = dualTemp(v) }
        if let v = r.P { d["P"] = pressureText(v, isBar: form.pressureIsBar) }
        if let v = r.P0 { d["P0"] = pressureText(v, isBar: form.pressureIsBar) }
        if let v = r.M { d["M"] = String(format: "%.4f", v) }
        if let v = r.p0OverP { d["P0/P"] = String(format: "%.4f", v) }
        return d
    }

    private var inputSnapshot: [String: String] {
        var d = [String: String]()
        if !form.t0.isEmpty { d["T0"] = form.t0 + " " + (form.t0Celsius ? "℃" : "K") }
        if !form.p0.isEmpty { d["P0"] = form.p0 + " " + (form.pressureIsBar ? "bar" : "Pa") }
        if !form.t.isEmpty { d["T"] = form.t + " " + (form.tCelsius ? "℃" : "K") }
        if !form.p.isEmpty { d["P"] = form.p + " " + (form.pressureIsBar ? "bar" : "Pa") }
        if !form.m.isEmpty { d["M"] = form.m }
        return d
    }
}
