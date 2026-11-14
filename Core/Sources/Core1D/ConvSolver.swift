// ---------------------------------------------------------------
// ConvSolver.swift —— 总静态参数换算（工作簿页 3 语义）
//
// 五槽可选输入 T0/P0/T/P/M：恰 3 个非空 → 按 10 种情况判况求解 2 个输出；
// >3 个 → TOO_MANY_PARAMS；<3 个 → TOO_FEW_PARAMS（继续补足的进行时提示）。
// 另暴露工作簿 ℃/K 双格冲突检测 validateDual（|C+273.15−K| > 0.05 判冲突），
// 以及双格入口 solve(input:dual:)（每格各计 1 个参数，冲突检查先于数量检查，
// 与工作簿 B4 编号格行为一致）。App 单格+温标开关结构上不会触发冲突，双格入口
// 仅为对拍 golden errors 保留。
//
// 提示/报错文案（TOO_MANY_PARAMS / TOO_FEW_PARAMS / 两处温标冲突 / 情况 4 的
// M 自洽提示 / 情况 8 的可达范围无解提示）与 golden.json 逐字同源；其中带数值
// 的文案按 %.3f 拼装。情况 8 的可达范围用连续细扫（工作簿引擎为 381 点网格，
// 范围数字有已知微差，见 golden.meta.workbookReferenceNote）。
// ---------------------------------------------------------------
import Foundation

/// 五槽输入（nil = 未填），与工作簿 E6:E10 对应
public struct ConvInput {
    public var T0: Double?
    public var P0: Double?
    public var T: Double?
    public var P: Double?
    public var M: Double?

    public init(T0: Double? = nil, P0: Double? = nil, T: Double? = nil,
                P: Double? = nil, M: Double? = nil) {
        self.T0 = T0
        self.P0 = P0
        self.T = T
        self.P = P
        self.M = M
    }
}

/// 工作簿 ℃/K 双格输入（对拍 golden errors 用；App 不使用）
public struct ConvDualTemps {
    public var t0Celsius: Double?
    public var t0Kelvin: Double?
    public var tCelsius: Double?
    public var tKelvin: Double?

    public init(t0Celsius: Double? = nil, t0Kelvin: Double? = nil,
                tCelsius: Double? = nil, tKelvin: Double? = nil) {
        self.t0Celsius = t0Celsius
        self.t0Kelvin = t0Kelvin
        self.tCelsius = tCelsius
        self.tKelvin = tKelvin
    }
}

/// 换算结果：valid = 是否有可展示的数值输出；message 非空时按 severity 展示卡片
public struct ConvResult {
    public enum Severity {
        case plain      // 无文案
        case hint       // 进行时提示（灰，如参数不足）
        case warning    // 警告（黄：M 不自洽 / 可达范围无解）
        case error      // 报错（红：超参数 / 温标冲突）
    }

    /// 状态码（与 golden errors 的 code 同款原文；SOLVED = 正常求解）
    public let code: String
    /// 非空参数个数（双格时每格各计 1）
    public let filled: Int
    /// 情况编号 1...10（未到判况时为 nil）
    public let caseId: Int?
    /// 是否有数值输出
    public let valid: Bool
    /// 文案级别
    public let severity: Severity
    /// 展示文案（空 = 无）
    public let message: String

    /// 求解输出（仅本情况求解的两个非 nil）
    public let T: Double?
    public let P: Double?
    public let T0: Double?
    public let P0: Double?
    public let M: Double?
    public let p0OverP: Double?
}

public struct ConvSolver {
    public let model: AirModel

    /// 情况 8 可达范围的细扫点数（工作簿引擎为 381 点网格，此处连续细扫）
    public static let rangeScanPoints = 3801
    /// 情况 4 的 M 自洽提示触发阈值（golden 注记同款）
    public static let mConsistencyTol = 0.005
    /// ℃/K 双格冲突容差 [K]
    public static let unitConflictTolK = 0.05

    public init(model: AirModel) {
        self.model = model
    }

    // MARK: - 温标双格冲突

    /// 工作簿 ℃/K 双格冲突判定：两格都填且 |C+273.15−K| > 0.05 → true
    public static func validateDual(celsius: Double?, kelvin: Double?) -> Bool {
        guard let c = celsius, let k = kelvin else { return false }
        return abs(c + TempScale.celsiusOffset - k) > unitConflictTolK
    }

    /// 两处温标冲突的共用文案（工作簿 B4 编号格原文）
    public static let dualConflictMessage =
        "⚠ 温度 ℃/K 两格不一致：请检查总温/静温的两格温度输入，删除一格"

    // MARK: - 求解入口

    public func solve(_ input: ConvInput) -> ConvResult {
        solve(input: input, dual: nil)
    }

    /// 双格入口：dual 非 nil 时 T0/T 以双格为准（五槽同名槽忽略），
    /// 非空参数按「每格各计 1」统计
    public func solve(input: ConvInput, dual: ConvDualTemps?) -> ConvResult {
        var merged = input
        var filled: Int

        if let d = dual {
            // 冲突检查先于数量检查（工作簿顺序：双格不一致优先报冲突）
            if Self.validateDual(celsius: d.t0Celsius, kelvin: d.t0Kelvin) {
                return makeResult(code: "T0_UNIT_CONFLICT",
                                  filled: Self.countFilled(input: input, dual: d),
                                  caseId: nil, valid: false, severity: .error,
                                  message: Self.dualConflictMessage)
            }
            if Self.validateDual(celsius: d.tCelsius, kelvin: d.tKelvin) {
                return makeResult(code: "T_UNIT_CONFLICT",
                                  filled: Self.countFilled(input: input, dual: d),
                                  caseId: nil, valid: false, severity: .error,
                                  message: Self.dualConflictMessage)
            }
            merged.T0 = d.t0Kelvin ?? d.t0Celsius.map { $0 + TempScale.celsiusOffset }
            merged.T = d.tKelvin ?? d.tCelsius.map { $0 + TempScale.celsiusOffset }
            filled = Self.countFilled(input: input, dual: d)
        } else {
            filled = [merged.T0, merged.P0, merged.T, merged.P, merged.M]
                .compactMap { $0 }.count
        }

        if filled > 3 {
            return makeResult(code: "TOO_MANY_PARAMS", filled: filled, caseId: nil,
                              valid: false, severity: .error,
                              message: "⚠ 已填 \(filled) 个参数（超过 3 个）：请检查输入的 5 个参数中只能有 3 个，删除多余项")
        }
        if filled < 3 {
            return makeResult(code: "TOO_FEW_PARAMS", filled: filled, caseId: nil,
                              valid: false, severity: .hint,
                              message: "已填 \(filled)/3 个参数，继续补足后自动判况")
        }

        let slots = Set([merged.T0, merged.P0, merged.T, merged.P, merged.M]
            .enumerated().compactMap { $0.element != nil ? Self.slotNames[$0.offset] : nil })

        switch slots {
        case ["T0", "P0", "M"]:                       // 情况 1
            guard let t0 = merged.T0, let p0 = merged.P0, let mch = merged.M else { break }
            let T = model.TinvV(t0, mch)
            return makeResult(code: "SOLVED", filled: filled, caseId: 1, valid: true,
                              severity: .plain, message: "",
                              T: T, P: p0 / model.piV(t0, T))
        case ["T0", "P0", "T"]:                       // 情况 2
            guard let t0 = merged.T0, let p0 = merged.P0, let T = merged.T else { break }
            return makeResult(code: "SOLVED", filled: filled, caseId: 2, valid: true,
                              severity: .plain, message: "",
                              P: p0 / model.piV(t0, T), M: model.MofV(t0, T))
        case ["T0", "P0", "P"]:                       // 情况 3
            guard let t0 = merged.T0, let p0 = merged.P0, let p = merged.P else { break }
            let T = invertS(model.s(t0) - model.r * log(p0 / p))
            return makeResult(code: "SOLVED", filled: filled, caseId: 3, valid: true,
                              severity: .plain, message: "",
                              T: T, M: model.MofV(t0, T))
        case ["T0", "T", "M"]:                        // 情况 4（含 M 自洽提示）
            guard let t0 = merged.T0, let T = merged.T, let mch = merged.M else { break }
            let ratio = model.piV(t0, T)
            let refM = model.MofV(t0, T)
            if abs(mch - refM) > Self.mConsistencyTol {
                return makeResult(code: "SOLVED", filled: filled, caseId: 4, valid: true,
                                  severity: .warning,
                                  message: "⚠ 不自洽：该 T0/T 对应的 M="
                                      + String(format: "%.3f", refM) + "，与输入不符",
                                  p0OverP: ratio)
            }
            return makeResult(code: "SOLVED", filled: filled, caseId: 4, valid: true,
                              severity: .plain, message: "", p0OverP: ratio)
        case ["T0", "T", "P"]:                        // 情况 5
            guard let t0 = merged.T0, let T = merged.T, let p = merged.P else { break }
            return makeResult(code: "SOLVED", filled: filled, caseId: 5, valid: true,
                              severity: .plain, message: "",
                              P0: p * model.piV(t0, T), M: model.MofV(t0, T))
        case ["T0", "P", "M"]:                        // 情况 6
            guard let t0 = merged.T0, let p = merged.P, let mch = merged.M else { break }
            let T = model.TinvV(t0, mch)
            return makeResult(code: "SOLVED", filled: filled, caseId: 6, valid: true,
                              severity: .plain, message: "",
                              T: T, P0: p * model.piV(t0, T))
        case ["P0", "T", "M"]:                        // 情况 7
            guard let p0 = merged.P0, let T = merged.T, let mch = merged.M else { break }
            let t0 = model.T0ofV(T, mch)
            return makeResult(code: "SOLVED", filled: filled, caseId: 7, valid: true,
                              severity: .plain, message: "",
                              P: p0 / model.piV(t0, T), T0: t0)
        case ["P0", "P", "M"]:                        // 情况 8（先查可达范围）
            guard let p0 = merged.P0, let p = merged.P, let mch = merged.M else { break }
            let piTarget = p0 / p
            let range = reachableRange(M: mch)
            if piTarget < range.low || piTarget > range.high {
                return makeResult(code: "OUT_OF_REACHABLE_RANGE", filled: filled, caseId: 8,
                                  valid: false, severity: .warning,
                                  message: "⚠ 无解：P0/P 不在该 M 的可达范围 ["
                                      + String(format: "%.3f", range.low) + ", "
                                      + String(format: "%.3f", range.high) + "]")
            }
            let T = model.TinvPi(piTarget, mch)
            return makeResult(code: "SOLVED", filled: filled, caseId: 8, valid: true,
                              severity: .plain, message: "",
                              T: T, T0: model.T0ofV(T, mch))
        case ["P0", "P", "T"]:                        // 情况 9
            guard let p0 = merged.P0, let p = merged.P, let T = merged.T else { break }
            let t0 = invertS(model.s(T) + model.r * log(p0 / p))
            return makeResult(code: "SOLVED", filled: filled, caseId: 9, valid: true,
                              severity: .plain, message: "",
                              T0: t0, M: model.MofV(t0, T))
        case ["T", "P", "M"]:                         // 情况 10
            guard let T = merged.T, let p = merged.P, let mch = merged.M else { break }
            let t0 = model.T0ofV(T, mch)
            return makeResult(code: "SOLVED", filled: filled, caseId: 10, valid: true,
                              severity: .plain, message: "",
                              T0: t0, P0: p * model.piV(t0, T))
        default:
            preconditionFailure("恰 3 个参数的组合应被 10 种情况全覆盖")
        }
        preconditionFailure("switch 各分支均已 return")
    }

    // MARK: - 私有

    static let slotNames = ["T0", "P0", "T", "P", "M"]

    static func countFilled(input: ConvInput, dual: ConvDualTemps) -> Int {
        [dual.t0Celsius, dual.t0Kelvin, dual.tCelsius, dual.tKelvin,
         input.P0, input.P, input.M].compactMap { $0 }.count
    }

    /// 情况 8 的可达范围：π(T0ofV(T,M), T) 在 [tMin,tMax] 上的 min/max（连续细扫）。
    /// 与工作簿引擎 381 点网格的 MIN/MAX 有已知微差（网格离散），文案数字按本值拼装。
    func reachableRange(M: Double) -> (low: Double, high: Double) {
        var low = Double.infinity
        var high = -Double.infinity
        for i in 0..<Self.rangeScanPoints {
            let T = model.tMin + (model.tMax - model.tMin) * Double(i)
                / Double(Self.rangeScanPoints - 1)
            let p = model.piV(model.T0ofV(T, M), T)
            low = min(low, p)
            high = max(high, p)
        }
        return (low, high)
    }

    /// 熵反解温度 [K]（golden 情况 3/9 同款）：s(T) = target，[tMin,tMax] 上 80 次二分
    func invertS(_ target: Double) -> Double {
        var lo = model.tMin, hi = model.tMax
        for _ in 0..<AirModel.nBisect {
            let mid = (lo + hi) / 2
            if model.s(mid) < target { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    private func makeResult(code: String, filled: Int, caseId: Int?, valid: Bool,
                            severity: ConvResult.Severity, message: String,
                            T: Double? = nil, P: Double? = nil, T0: Double? = nil,
                            P0: Double? = nil, M: Double? = nil,
                            p0OverP: Double? = nil) -> ConvResult {
        ConvResult(code: code, filled: filled, caseId: caseId, valid: valid,
                   severity: severity, message: message,
                   T: T, P: P, T0: T0, P0: P0, M: M, p0OverP: p0OverP)
    }
}
