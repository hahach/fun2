// ---------------------------------------------------------------
// EvalSolver.swift —— 评估页两块（工作簿页 1 语义）
//
// 压气机块：π 增压比、T1 入口总温、ηc 等熵效率、ṁ → Ts 等熵出口温、
//           T2 实际出口温、W 耗功 [kW]；
// 涡轮块：  ε 膨胀比（p1/p2）主位、T1、ηt、ṁ → Ts、T2、W 产功 [kW]。
// 另提供由实测 T2 反算效率的方向（工作簿校验段同款语义，golden eval 对拍用）。
// 全部经由 AirModel，本文件不含独立数值近似。
// ---------------------------------------------------------------
import Foundation

public struct EvalSolver {
    public let model: AirModel

    public init(model: AirModel) {
        self.model = model
    }

    /// 功率方向输出：TsIsen 等熵出口静温 [K]、T2 实际出口温度 [K]、wKW 功 [kW]
    public struct PowerOutput {
        public let tsIsen: Double
        public let t2: Double
        public let wKW: Double
    }

    /// 效率方向输出：tsIsen 等熵出口静温 [K]、eta 等熵效率 [1]
    public struct EfficiencyOutput {
        public let tsIsen: Double
        public let eta: Double
    }

    /// 压气机耗功：pi 增压比、t1 入口总温 [K]、etaC 等熵效率、mdot [kg/s]
    public func compressor(pi: Double, t1: Double, etaC: Double, mdot: Double) -> PowerOutput {
        let ts = model.ts(t0: t1, pi: pi)
        let h1 = model.h(t1)
        let h2 = h1 + (model.h(ts) - h1) / etaC
        return PowerOutput(tsIsen: ts, t2: model.invertH(h2), wKW: mdot * (h2 - h1) / 1000)
    }

    /// 涡轮产功：eps 膨胀比（p1/p2）、t1 入口总温 [K]、etaT 等熵效率、mdot [kg/s]
    public func turbine(eps: Double, t1: Double, etaT: Double, mdot: Double) -> PowerOutput {
        let ts = model.ts(t0: t1, pi: 1 / eps)
        let h1 = model.h(t1)
        let h2 = h1 - etaT * (h1 - model.h(ts))
        return PowerOutput(tsIsen: ts, t2: model.invertH(h2), wKW: mdot * (h1 - h2) / 1000)
    }

    /// 由实测出口温反算压气机等熵效率：pi 增压比、t1/t2 [K]
    public func compressorEfficiency(pi: Double, t1: Double, t2: Double) -> EfficiencyOutput {
        let ts = model.ts(t0: t1, pi: pi)
        let eta = (model.h(ts) - model.h(t1)) / (model.h(t2) - model.h(t1))
        return EfficiencyOutput(tsIsen: ts, eta: eta)
    }

    /// 由实测出口温反算涡轮等熵效率：eps 膨胀比（p1/p2）、t1/t2 [K]
    public func turbineEfficiency(eps: Double, t1: Double, t2: Double) -> EfficiencyOutput {
        let ts = model.ts(t0: t1, pi: 1 / eps)
        let eta = (model.h(t1) - model.h(t2)) / (model.h(t1) - model.h(ts))
        return EfficiencyOutput(tsIsen: ts, eta: eta)
    }
}
