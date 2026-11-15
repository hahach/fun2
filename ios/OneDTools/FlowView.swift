import SwiftUI
import Core1D

// 管流页：ṁ、T0、P0、A（或 r 半径切换）、η_blk → T、P、ρ、V、a、M。
// 目标密流 > g_crit 时显示显著堵塞提示（无亚声速解）。
// 计算全部经 Core1D.FlowSolver，本页无数值公式。
struct FlowView: View {
    @StateObject private var form = FlowForm.load()
    @EnvironmentObject private var history: HistoryStore

    private let solver = FlowSolver(model: .standard())

    private var result: FlowResult? {
        guard let mdot = parseDecimal(form.mdot),
              let t0raw = parseDecimal(form.t0),
              let p0raw = parseDecimal(form.p0),
              let eta = parseDecimal(form.etaBlk),
              mdot > 0, p0raw > 0, eta > 0 else { return nil }
        let t0 = TempScale.toKelvin(t0raw, isCelsius: form.t0Celsius)
        let p0 = PressureScale.toPascal(p0raw, isBar: form.p0IsBar)
        guard t0 > solver.model.tMin else { return nil } // Core 侧 precondition 的 UI 层前置挡板
        let area: Double?
        if form.useRadius {
            area = parseDecimal(form.radius).map { FlowSolver.areaFromRadius($0) }
        } else {
            area = parseDecimal(form.area)
        }
        guard let a = area, a > 0 else { return nil }
        return solver.solve(mdot: mdot, t0: t0, p0: p0, area: a, etaBlk: eta)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    InputCard(title: "一维管流输入") {
                        NumberField(label: "质量流量 ṁ", unit: "kg/s", text: $form.mdot)
                        TempField(label: "总温 T0", text: $form.t0, isCelsius: $form.t0Celsius)
                        PressureField(label: "总压 P0", text: $form.p0, isBar: $form.p0IsBar)
                        geometryPicker
                        NumberField(label: form.useRadius ? "半径 r" : "截面积 A",
                                    unit: form.useRadius ? "m" : "m²",
                                    text: form.useRadius ? $form.radius : $form.area)
                        NumberField(label: "堵塞系数 η_blk", unit: "0..1", text: $form.etaBlk)
                        resultBlock
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("管流")
            .keyboardDoneBar()
        }
    }

    private var geometryPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("几何输入")
                .font(.footnote)
                .foregroundColor(.secondary)
            Picker("几何输入", selection: $form.useRadius) {
                Text("面积 A").tag(false)
                Text("半径 r").tag(true)
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var resultBlock: some View {
        if let r = result {
            if r.choked {
                MessageCard(level: .warning, text: "⚠ 已堵塞：目标密流 "
                    + String(format: "%.2f", r.flux)
                    + " kg/(m²·s) 超过临界密流 g_crit = "
                    + String(format: "%.2f", r.gCrit)
                    + " kg/(m²·s)（峰位 T ≈ " + String(format: "%.1f", r.tPeak)
                    + " K，M ≈ 1），无亚声速解——请减小 ṁ 或增大 A/η_blk")
            } else {
                ResultCard(title: "管流结果", rows: [
                    .init("静温 T", dualTemp(r.T!), highlight: true),
                    .init("静压 P", pressureText(r.P!, isBar: form.p0IsBar)),
                    .init("密度 ρ", String(format: "%.4f", r.rho!) + " kg/m³"),
                    .init("速度 V", String(format: "%.2f", r.V!) + " m/s"),
                    .init("声速 a", String(format: "%.2f", r.a!) + " m/s"),
                    .init("马赫数 M", String(format: "%.4f", r.M!), highlight: true),
                    .init("密流 g / g_crit",
                          String(format: "%.2f / %.2f", r.flux, r.gCrit) + " kg/(m²·s)"),
                ])
                Button("存历史") {
                    history.add(page: "管流", inputs: inputSnapshot, outputs: [
                        "T": dualTemp(r.T!),
                        "P": pressureText(r.P!, isBar: form.p0IsBar),
                        "M": String(format: "%.4f", r.M!),
                        "V": String(format: "%.2f m/s", r.V!),
                    ])
                }
                .buttonStyle(.bordered)
            }
        } else {
            MessageCard(level: .hint, text: "填完 ṁ、T0、P0、A（或 r）、η_blk（均为正数）后自动出结果；T0 需大于有效下限 "
                + String(format: "%.0f", solver.model.tMin) + " K")
        }
    }

    private var inputSnapshot: [String: String] {
        var d: [String: String] = [
            "ṁ": form.mdot + " kg/s",
            "T0": form.t0 + " " + (form.t0Celsius ? "℃" : "K"),
            "P0": form.p0 + " " + (form.p0IsBar ? "bar" : "Pa"),
            "η_blk": form.etaBlk,
        ]
        if form.useRadius {
            d["r"] = form.radius + " m"
        } else {
            d["A"] = form.area + " m²"
        }
        return d
    }
}
