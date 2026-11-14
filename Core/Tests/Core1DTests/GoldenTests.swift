// ---------------------------------------------------------------
// GoldenTests.swift —— 跨语言对拍固定文件 golden.json 全量断言
//
// 生成器：仓内 work/model/golden.mjs（kernel.mjs 连续积分参考内核）。
// Swift 端按 meta.methods 记载的同一算法实现（证明书 .tmp/swift-alg-proof.mjs
// 先在 node 侧对拍全绿后再移植），本套件是移植正确性的最终闸门：
//   - cp 域用 polyTol(1e-9)，其余域用 integrateTol(1e-6)；
//   - 相对容差定义 |a−b|/max(|b|,1)（= golden.meta.tolerances.note）；
//   - conv 提示文案：静态文案逐字相等；带数值文案按 %.3f 拼装后逐字相等；
//   - 情况 8 可达范围：App 用连续细扫、工作簿引擎用 381 点网格，范围数字有
//     已知微差（golden.meta.workbookReferenceNote），故只断言 code 与消息模式，
//     不断言范围数字（有意差异，非遗漏）。
// ---------------------------------------------------------------
import XCTest
import Foundation

@testable import Core1D

// MARK: - golden.json 的 Codable 结构（字段名与 JSON 原键一致）

private struct GoldenFile: Codable {
    struct Meta: Codable {
        struct Tolerances: Codable {
            let polyTol: Double
            let integrateTol: Double
        }
        let tolerances: Tolerances
    }
    struct Coeffs: Codable {
        let poly: [Double]
        let tMid: Double
        let tScale: Double
        let tRef: Double
        let r: Double
        let tMin: Double
        let tMax: Double
    }
    struct CpBlock: Codable {
        struct Point: Codable {
            let T: Double
            let cp: Double
        }
        let points: [Point]
    }
    struct Primitive: Codable {
        struct HTPoint: Codable {
            let T: Double
            let h: Double?
            let s: Double?
        }
        struct TsCase: Codable {
            let T0: Double
            let pi: Double
            let Ts: Double
        }
        let han: [HTPoint]
        let phi: [HTPoint]
        let ts: [TsCase]
    }
    struct Eval: Codable {
        struct Inputs: Codable {
            let mdot: Double?
            let T1: Double
            let T2: Double?
            let p1: Double
            let p2: Double
            let etaC: Double?
            let etaT: Double?
        }
        struct Outputs: Codable {
            let pi: Double?
            let epr: Double?
            let Ts: Double?
            let etaC: Double?
            let etaT: Double?
            let TsIsen: Double?
            let T2: Double?
            let W: Double?
        }
        struct EvalCase: Codable {
            let inputs: Inputs
            let outputs: Outputs
        }
        let compressorEfficiency: EvalCase
        let turbineEfficiency: EvalCase
        let compressorPower: EvalCase
        let turbinePower: EvalCase
    }
    struct Flow: Codable {
        struct Inputs: Codable {
            let mdot: Double
            let T0: Double
            let P0: Double
            let A: Double
            let etaBlk: Double
        }
        struct Outputs: Codable {
            let T: Double
            let P: Double
            let rho: Double
            let V: Double
            let a: Double
            let M: Double
        }
        struct FlowCase: Codable {
            let name: String
            let inputs: Inputs
            let fluxG: Double?
            let gCrit: Double?
            let outputs: Outputs
        }
        let cases: [FlowCase]
    }
    struct Conv: Codable {
        struct Slots: Codable {
            let T0: Double?
            let P0: Double?
            let T: Double?
            let P: Double?
            let M: Double?
        }
        struct Outputs: Codable {
            let T: Double?
            let P: Double?
            let T0: Double?
            let P0: Double?
            let M: Double?
            let p0OverP: Double?
        }
        struct ConvCase: Codable {
            let id: Int
            let known: String
            let inputs: Slots
            let outputs: Outputs
        }
        struct Warning: Codable {
            let id: Int
            let kind: String
            let inputs: Slots
            let refM: Double?
            let piTarget: Double?
            let message: String
        }
        struct ErrorInputs: Codable {
            let T0: Double?
            let P0: Double?
            let T0C: Double?
            let T0K: Double?
            let T: Double?
            let TC: Double?
            let TK: Double?
            let P: Double?
            let M: Double?
        }
        struct ErrorCase: Codable {
            let code: String
            let filled: Int
            let inputs: ErrorInputs
            let message: String
        }
        let cases: [ConvCase]
        let warnings: [Warning]
        let errors: [ErrorCase]
    }
    struct Cases: Codable {
        let cp: CpBlock
        let primitive: Primitive
        let eval: Eval
        let flow: Flow
        let conv: Conv
    }
    let meta: Meta
    let coeffs: Coeffs
    let cases: Cases
}

// MARK: - 对拍套件

final class GoldenTests: XCTestCase {

    private var golden: GoldenFile!
    private var model: AirModel!
    private var polyTol: Double = 0
    private var integrateTol: Double = 0

    override func setUpWithError() throws {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "golden", withExtension: "json", subdirectory: "Fixtures"),
            "Fixtures/golden.json 没有打进测试资源")
        golden = try JSONDecoder().decode(GoldenFile.self, from: Data(contentsOf: url))
        model = AirModel.standard()
        polyTol = golden.meta.tolerances.polyTol
        integrateTol = golden.meta.tolerances.integrateTol
    }

    // MARK: 工具

    private func relDev(_ a: Double, _ b: Double) -> Double {
        abs(a - b) / max(abs(b), 1)
    }

    private func assertClose(_ a: Double, _ b: Double, _ tol: Double, _ label: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThanOrEqual(
            relDev(a, b), tol,
            "\(label)：相对偏差 \(relDev(a, b)) 超容差 \(tol)（得 \(a)，期望 \(b)）",
            file: file, line: line)
    }

    private func assertEqualExact(_ a: Double, _ b: Double, _ label: String,
                                  file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a, b, accuracy: abs(b) * 1e-15 + 1e-300,
                       "\(label)：\(a) 与 \(b) 应逐位一致", file: file, line: line)
    }

    // MARK: 防呆

    // golden 系数必须与 standard() 硬编码一致：golden 重生成而 App 未同步时在此失败
    func testGoldenCoeffsMatchStandardModel() {
        let g = golden.coeffs
        XCTAssertEqual(model.poly.count, 5)
        for (i, b) in g.poly.enumerated() {
            assertEqualExact(model.poly[i], b, "poly[\(i)]")
        }
        assertEqualExact(model.tMid, g.tMid, "tMid")
        assertEqualExact(model.tScale, g.tScale, "tScale")
        assertEqualExact(model.tRef, g.tRef, "tRef")
        assertEqualExact(model.r, g.r, "r")
        assertEqualExact(model.tMin, g.tMin, "tMin")
        assertEqualExact(model.tMax, g.tMax, "tMax")
    }

    // 容差防呆：golden 若改紧容差而套件未感知，会静默假绿，这里显式钉住
    func testGoldenTolerancesAreExpected() {
        XCTAssertEqual(golden.meta.tolerances.polyTol, 1e-9)
        XCTAssertEqual(golden.meta.tolerances.integrateTol, 1e-6)
    }

    // MARK: cp / 焓 / 熵 / 等熵温度

    func testCpPoints() {
        for p in golden.cases.cp.points {
            assertClose(model.cp(p.T), p.cp, polyTol, "cp(T=\(p.T))")
        }
    }

    func testHanPoints() {
        for p in golden.cases.primitive.han {
            assertClose(model.h(p.T), p.h!, integrateTol, "h(T=\(p.T))")
        }
    }

    func testPhiPoints() {
        for p in golden.cases.primitive.phi {
            assertClose(model.s(p.T), p.s!, integrateTol, "s(T=\(p.T))")
        }
    }

    func testTsCases() {
        for c in golden.cases.primitive.ts {
            assertClose(model.ts(t0: c.T0, pi: c.pi), c.Ts, integrateTol,
                        "TS(T0=\(c.T0), pi=\(c.pi))")
        }
    }

    // MARK: 评估页四工况

    func testEvalCases() throws {
        let ev = golden.cases.eval
        // 压气机效率：T1=288, T2=350, p1=100, p2=200
        do {
            let ci = ev.compressorEfficiency.inputs
            let co = ev.compressorEfficiency.outputs
            let pi = ci.p2 / ci.p1
            let eff = EvalSolver(model: model).compressorEfficiency(pi: pi, t1: ci.T1, t2: ci.T2!)
            assertClose(pi, co.pi!, integrateTol, "压气机效率.pi")
            assertClose(eff.tsIsen, co.Ts!, integrateTol, "压气机效率.Ts")
            assertClose(eff.eta, co.etaC!, integrateTol, "压气机效率.etaC")
        }
        // 涡轮效率：T1=1200, T2=800, p1=500, p2=125
        do {
            let ti = ev.turbineEfficiency.inputs
            let to = ev.turbineEfficiency.outputs
            let eps = ti.p1 / ti.p2
            let eff = EvalSolver(model: model).turbineEfficiency(eps: eps, t1: ti.T1, t2: ti.T2!)
            assertClose(eps, to.epr!, integrateTol, "涡轮效率.epr")
            assertClose(eff.tsIsen, to.Ts!, integrateTol, "涡轮效率.Ts")
            assertClose(eff.eta, to.etaT!, integrateTol, "涡轮效率.etaT")
        }
        // 压气机耗功
        do {
            let ci = ev.compressorPower.inputs
            let co = ev.compressorPower.outputs
            let out = EvalSolver(model: model).compressor(
                pi: ci.p2 / ci.p1, t1: ci.T1, etaC: ci.etaC!, mdot: ci.mdot!)
            assertClose(out.tsIsen, co.TsIsen!, integrateTol, "压气机耗功.TsIsen")
            assertClose(out.t2, co.T2!, integrateTol, "压气机耗功.T2")
            assertClose(out.wKW, co.W!, integrateTol, "压气机耗功.W")
        }
        // 涡轮产功
        do {
            let ti = ev.turbinePower.inputs
            let to = ev.turbinePower.outputs
            let out = EvalSolver(model: model).turbine(
                eps: ti.p1 / ti.p2, t1: ti.T1, etaT: ti.etaT!, mdot: ti.mdot!)
            assertClose(out.tsIsen, to.TsIsen!, integrateTol, "涡轮产功.TsIsen")
            assertClose(out.t2, to.T2!, integrateTol, "涡轮产功.T2")
            assertClose(out.wKW, to.W!, integrateTol, "涡轮产功.W")
        }
    }

    // MARK: 管流四工况（含近堵塞）

    func testFlowCases() throws {
        let solver = FlowSolver(model: model)
        for c in golden.cases.flow.cases {
            let r = solver.solve(mdot: c.inputs.mdot, t0: c.inputs.T0, p0: c.inputs.P0,
                                 area: c.inputs.A, etaBlk: c.inputs.etaBlk)
            XCTAssertFalse(r.choked, "\(c.name) 不应判堵")
            assertClose(r.flux, c.inputs.mdot / (c.inputs.A * c.inputs.etaBlk), polyTol,
                        "\(c.name).flux")
            assertClose(r.T!, c.outputs.T, integrateTol, "\(c.name).T")
            assertClose(r.P!, c.outputs.P, integrateTol, "\(c.name).P")
            assertClose(r.rho!, c.outputs.rho, integrateTol, "\(c.name).rho")
            assertClose(r.V!, c.outputs.V, integrateTol, "\(c.name).V")
            assertClose(r.a!, c.outputs.a, integrateTol, "\(c.name).a")
            assertClose(r.M!, c.outputs.M, integrateTol, "\(c.name).M")
            if let gCrit = c.gCrit {
                assertClose(r.gCrit, gCrit, integrateTol, "\(c.name).gCrit（细扫 vs golden 三分）")
            }
            if let fluxG = c.fluxG {
                assertClose(r.flux, fluxG, polyTol, "\(c.name).fluxG")
            }
        }
        // near_choke 必须落在亚声速支（golden 生成端同款防呆）
        let choke = golden.cases.flow.cases[3]
        let rc = solver.solve(mdot: choke.inputs.mdot, t0: choke.inputs.T0,
                              p0: choke.inputs.P0, area: choke.inputs.A, etaBlk: choke.inputs.etaBlk)
        XCTAssertGreaterThan(rc.M!, 0.5)
        XCTAssertLessThan(rc.M!, 1.0)
    }

    // 堵塞判定：目标密流略超 g_crit → choked 且无数值输出
    func testChokedDetection() throws {
        let solver = FlowSolver(model: model)
        let c = try XCTUnwrap(golden.cases.flow.cases.first { $0.gCrit != nil })
        // 构造 1.02×g_crit 的目标密流：mdot = 1.02·g_crit·A·η_blk
        let r = solver.solve(mdot: 1.02 * c.gCrit! * c.inputs.A * c.inputs.etaBlk,
                             t0: c.inputs.T0, p0: c.inputs.P0, area: c.inputs.A, etaBlk: c.inputs.etaBlk)
        XCTAssertTrue(r.choked, "密流 1.02×g_crit 应判堵")
        XCTAssertNil(r.T)
        XCTAssertNil(r.M)
        assertClose(r.gCrit, c.gCrit!, integrateTol, "choked.gCrit")
    }

    // MARK: 总静换算 10 种情况

    func testConvCases() throws {
        let solver = ConvSolver(model: model)
        for c in golden.cases.conv.cases {
            let input = ConvInput(T0: c.inputs.T0, P0: c.inputs.P0, T: c.inputs.T,
                                  P: c.inputs.P, M: c.inputs.M)
            let r = solver.solve(input)
            XCTAssertEqual(r.caseId, c.id, "情况 \(c.id) 判况错误")
            XCTAssertEqual(r.filled, 3)
            XCTAssertTrue(r.valid, "情况 \(c.id) 应有数值输出")
            let mine: [String: Double] = [
                "T": r.T, "P": r.P, "T0": r.T0, "P0": r.P0, "M": r.M, "p0OverP": r.p0OverP,
            ]
            for (key, expected) in goldenOutputDict(c.outputs) {
                let got = try XCTUnwrap(mine[key], "情况 \(c.id) 缺输出 \(key)")
                assertClose(got, expected, integrateTol, "情况\(c.id).\(key)")
            }
        }
    }

    private func goldenOutputDict(_ o: GoldenFile.Conv.Outputs) -> [String: Double] {
        var d = [String: Double]()
        if let v = o.T { d["T"] = v }
        if let v = o.P { d["P"] = v }
        if let v = o.T0 { d["T0"] = v }
        if let v = o.P0 { d["P0"] = v }
        if let v = o.M { d["M"] = v }
        if let v = o.p0OverP { d["p0OverP"] = v }
        return d
    }

    // MARK: conv 警告（4b M 自洽 / 8c 可达范围）

    // 4b：M 与 MofV(T0,T) 差 > 0.005 → 结果照常输出 + 黄色提示，文案逐字相等
    func testConvWarningMConsistency() throws {
        let w = try XCTUnwrap(golden.cases.conv.warnings.first { $0.id == 4 })
        let solver = ConvSolver(model: model)
        let r = solver.solve(ConvInput(T0: w.inputs.T0, T: w.inputs.T, M: w.inputs.M))
        XCTAssertEqual(r.caseId, 4)
        XCTAssertTrue(r.valid, "4b 仍应有 p0OverP 输出")
        XCTAssertEqual(r.p0OverP!, model.piV(w.inputs.T0!, w.inputs.T!))
        // refM 复算对拍（4b 触发条件的计算侧）
        let refM = model.MofV(w.inputs.T0!, w.inputs.T!)
        assertClose(refM, w.refM!, integrateTol, "4b.refM")
        XCTAssertGreaterThan(abs(w.inputs.M! - refM), ConvSolver.mConsistencyTol, "4b 应触发")
        XCTAssertEqual(r.message, w.message, "4b 文案应与 golden 逐字相等")
        XCTAssertEqual(r.severity, .warning)
    }

    // 8c：P0/P 超出该 M 的可达范围 → 无解提示。范围数字不逐字对拍：
    // App 连续细扫与工作簿 381 点网格存在已知微差（golden.meta.workbookReferenceNote
    // 同源说明），故只断言 code 与消息模式（含『可达范围』）——有意差异，非遗漏。
    func testConvWarningReachableRange() throws {
        let w = try XCTUnwrap(golden.cases.conv.warnings.first { $0.id == 8 })
        let solver = ConvSolver(model: model)
        let r = solver.solve(ConvInput(P0: w.inputs.P0, P: w.inputs.P, M: w.inputs.M))
        XCTAssertEqual(r.caseId, 8)
        XCTAssertFalse(r.valid, "8c 无数值输出")
        XCTAssertEqual(r.code, "OUT_OF_REACHABLE_RANGE")
        XCTAssertEqual(r.severity, .warning)
        XCTAssertTrue(r.message.hasPrefix("⚠ 无解：P0/P 不在该 M 的可达范围 ["), "8c 消息模式（前缀）")
        XCTAssertTrue(r.message.contains("可达范围"), "8c 消息模式（含『可达范围』）")
        // 目标 π 确实落在自己算出的范围之外（自洽性）
        let piTarget = w.inputs.P0! / w.inputs.P!
        let range = solver.reachableRange(M: w.inputs.M!)
        XCTAssertLessThan(range.high, piTarget, "8c 触发条件应成立")
    }

    // MARK: conv 报错（超参数 / 温标冲突 / 参数不足）

    func testConvErrors() throws {
        let solver = ConvSolver(model: model)
        let errs = golden.cases.conv.errors

        // 已填 4 个
        let e0 = solver.solve(ConvInput(T0: 600, P0: 200000, T: 500, M: 0.5))
        XCTAssertEqual(e0.code, errs[0].code)
        XCTAssertEqual(e0.filled, errs[0].filled)
        XCTAssertEqual(e0.message, errs[0].message)
        XCTAssertFalse(e0.valid)
        XCTAssertEqual(e0.severity, .error)

        // 已填 5 个
        let e1 = solver.solve(ConvInput(T0: 600, P0: 200000, T: 500, P: 150000, M: 0.5))
        XCTAssertEqual(e1.code, errs[1].code)
        XCTAssertEqual(e1.filled, errs[1].filled)
        XCTAssertEqual(e1.message, errs[1].message)

        // 总温 ℃/K 双格冲突（App 单格不会触发；双格入口为对拍保留）
        XCTAssertTrue(ConvSolver.validateDual(celsius: errs[2].inputs.T0C, kelvin: errs[2].inputs.T0K))
        let e2 = solver.solve(input: ConvInput(P0: errs[2].inputs.P0, M: errs[2].inputs.M),
                              dual: ConvDualTemps(t0Celsius: errs[2].inputs.T0C,
                                                  t0Kelvin: errs[2].inputs.T0K))
        XCTAssertEqual(e2.code, errs[2].code)
        XCTAssertEqual(e2.filled, errs[2].filled)
        XCTAssertEqual(e2.message, errs[2].message)
        XCTAssertEqual(ConvSolver.dualConflictMessage, errs[2].message)

        // 静温 ℃/K 双格冲突
        XCTAssertTrue(ConvSolver.validateDual(celsius: errs[3].inputs.TC, kelvin: errs[3].inputs.TK))
        let e3 = solver.solve(input: ConvInput(P: errs[3].inputs.P),
                              dual: ConvDualTemps(t0Kelvin: errs[3].inputs.T0K,
                                                  tCelsius: errs[3].inputs.TC,
                                                  tKelvin: errs[3].inputs.TK))
        XCTAssertEqual(e3.code, errs[3].code)
        XCTAssertEqual(e3.filled, errs[3].filled)
        XCTAssertEqual(e3.message, errs[3].message)

        // 双格一致（差 273.15±0.05 内）不算冲突
        XCTAssertFalse(ConvSolver.validateDual(celsius: 26.85, kelvin: 300.0))
        XCTAssertFalse(ConvSolver.validateDual(celsius: 26.88, kelvin: 300.0))

        // 已填 2 个 → 继续补足的进行时提示（无 ⚠ 前缀）
        let e4 = solver.solve(ConvInput(T0: 600, P0: 200000))
        XCTAssertEqual(e4.code, errs[4].code)
        XCTAssertEqual(e4.filled, errs[4].filled)
        XCTAssertEqual(e4.message, errs[4].message)
        XCTAssertEqual(e4.severity, .hint)
    }
}
