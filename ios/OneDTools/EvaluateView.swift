import SwiftUI
import Core1D

// 评估页：压气机块（π、T1、ηc、ṁ → Ts、T2、W）+ 涡轮块（ε 膨胀比主位、
// T1、ηt、ṁ → Ts、T2、W），语义与工作簿页 1 两块一致。
// 计算全部经 Core1D.EvalSolver，本页无数值公式。
struct EvaluateView: View {
    @StateObject private var form = EvaluateForm.load()
    @EnvironmentObject private var history: HistoryStore

    private let solver = EvalSolver(model: .standard())

    private var compressor: EvalSolver.PowerOutput? {
        guard let pi = parseDecimal(form.compPi),
              let t1 = parseDecimal(form.compT1),
              let eta = parseDecimal(form.compEta),
              let mdot = parseDecimal(form.compMdot),
              pi > 0, eta > 0, mdot > 0 else { return nil }
        return solver.compressor(
            pi: pi,
            t1: TempScale.toKelvin(t1, isCelsius: form.compT1Celsius),
            etaC: eta, mdot: mdot)
    }

    private var turbine: EvalSolver.PowerOutput? {
        guard let eps = parseDecimal(form.turbEps),
              let t1 = parseDecimal(form.turbT1),
              let eta = parseDecimal(form.turbEta),
              let mdot = parseDecimal(form.turbMdot),
              eps > 0, eta > 0, mdot > 0 else { return nil }
        return solver.turbine(
            eps: eps,
            t1: TempScale.toKelvin(t1, isCelsius: form.turbT1Celsius),
            etaT: eta, mdot: mdot)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    compressorCard
                    turbineCard
                }
                .padding()
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("评估")
            .keyboardDoneBar()
        }
    }

    private var compressorCard: some View {
        InputCard(title: "压气机") {
            NumberField(label: "增压比 π", unit: "—", text: $form.compPi)
            TempField(label: "入口温度 T1", text: $form.compT1, isCelsius: $form.compT1Celsius)
            NumberField(label: "等熵效率 ηc", unit: "0..1", text: $form.compEta)
            NumberField(label: "质量流量 ṁ", unit: "kg/s", text: $form.compMdot)
            resultBlock("压气机结果", output: compressor,
                        inputs: snapshot(inputs: [
                            ("π", form.compPi, "—"),
                            ("T1", form.compT1, form.compT1Celsius ? "℃" : "K"),
                            ("ηc", form.compEta, "—"),
                            ("ṁ", form.compMdot, "kg/s"),
                        ]),
                        page: "评估·压气机")
        }
    }

    private var turbineCard: some View {
        InputCard(title: "涡轮") {
            NumberField(label: "膨胀比 ε（p1/p2）", unit: "—", text: $form.turbEps)
            TempField(label: "入口温度 T1", text: $form.turbT1, isCelsius: $form.turbT1Celsius)
            NumberField(label: "等熵效率 ηt", unit: "0..1", text: $form.turbEta)
            NumberField(label: "质量流量 ṁ", unit: "kg/s", text: $form.turbMdot)
            resultBlock("涡轮结果", output: turbine,
                        inputs: snapshot(inputs: [
                            ("ε", form.turbEps, "—"),
                            ("T1", form.turbT1, form.turbT1Celsius ? "℃" : "K"),
                            ("ηt", form.turbEta, "—"),
                            ("ṁ", form.turbMdot, "kg/s"),
                        ]),
                        page: "评估·涡轮")
        }
    }

    @ViewBuilder
    private func resultBlock(_ title: String, output: EvalSolver.PowerOutput?,
                             inputs: [String: String], page: String) -> some View {
        if let r = output {
            ResultCard(title: title, rows: [
                .init("等熵出口 Ts", dualTemp(r.tsIsen)),
                .init("实际出口 T2", dualTemp(r.t2)),
                .init(page.hasSuffix("压气机") ? "耗功 W" : "产功 W",
                      String(format: "%.2f", r.wKW) + " kW", highlight: true),
            ])
            Button("存历史") {
                history.add(page: page, inputs: inputs, outputs: [
                    "Ts": dualTemp(r.tsIsen),
                    "T2": dualTemp(r.t2),
                    "W": String(format: "%.2f kW", r.wKW),
                ])
            }
            .buttonStyle(.bordered)
        } else {
            MessageCard(level: .hint, text: "填完四个输入（均为正数）后自动出结果；温度可选 K 或 ℃")
        }
    }

    private func snapshot(inputs: [(String, String, String)]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: inputs.map { name, value, unit in
            (name, value.isEmpty ? "（空）" : value + " " + unit)
        })
    }
}
