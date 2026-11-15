// ---------------------------------------------------------------
// FlowSolver.swift —— 一维管流计算（工作簿页 2 语义）
//
// 由 ṁ/T0/P0/A（或 r）/η_blk 反演静温并输出全套参数。近堵塞防护：
//   1. 在 [tMin, t0] 细扫（4001 点）找密流 g(T) 的峰值 g_crit 与峰位 Tpeak
//     （峰值处 M≈1，即堵塞点；g 在 [tMin,t0] 上单峰）；
//   2. 目标密流 > g_crit → 堵塞，无亚声速解（choked = true）；
//   3. 否则在 [Tpeak, t0]（显式亚声速支）80 次二分求根。
// 括弧与方向 = 仓内 golden 生成脚本 invertGSub 的同款（g<target → hi=mid）。
// 默认括弧 [tMin,t0] 在近堵塞时会收敛到超声速支（证明书已复现该失败模式：
// near_choke 工况收敛到 T=100 K、M=4.48），故 App 侧一律走本结构。
// ---------------------------------------------------------------
import Foundation

/// 管流计算结果。choked = true 时无亚声速解，T/P/rho/V/a/M 均为 nil。
public struct FlowResult {
    /// 是否堵塞（目标密流超过临界密流）
    public let choked: Bool
    /// 临界密流 g_crit [kg/(m²·s)]（细扫峰值）
    public let gCrit: Double
    /// 峰位静温 Tpeak [K]（M≈1）
    public let tPeak: Double
    /// 目标密流 ṁ/(A·η_blk) [kg/(m²·s)]
    public let flux: Double
    /// 静温 [K]
    public let T: Double?
    /// 静压 [Pa 绝对]
    public let P: Double?
    /// 密度 [kg/m³]
    public let rho: Double?
    /// 速度 [m/s]
    public let V: Double?
    /// 声速 [m/s]
    public let a: Double?
    /// 马赫数 [1]
    public let M: Double?
}

public struct FlowSolver {
    public let model: AirModel

    /// 峰值细扫点数（≥2001，步长 = (t0−tMin)/4000；峰值误差只影响括弧下界，
    /// 不影响二分收敛到的根——根由 g(T)=target 本身决定）
    public static let scanPoints = 4001

    public init(model: AirModel) {
        self.model = model
    }

    /// 由半径换算圆截面面积 [m²]（工作簿 A/r 双输入关系）
    public static func areaFromRadius(_ radius: Double) -> Double {
        Double.pi * radius * radius
    }

    /// 细扫 [tMin, t0] 求密流峰值 g_crit 与峰位 Tpeak
    public func peak(t0: Double, p0: Double) -> (g: Double, t: Double) {
        precondition(t0 > model.tMin, "T0 必须大于有效温度下限")
        var bestG = -Double.infinity
        var bestT = model.tMin
        for i in 0..<Self.scanPoints {
            let T = model.tMin + (t0 - model.tMin) * Double(i) / Double(Self.scanPoints - 1)
            let gv = model.gRef(T, t0: t0, p0: p0)
            if gv > bestG {
                bestG = gv
                bestT = T
            }
        }
        return (bestG, bestT)
    }

    /// 管流求解：mdot [kg/s]、t0 [K]、p0 [Pa 绝对]、area [m²]、etaBlk 堵塞系数 [1]
    public func solve(mdot: Double, t0: Double, p0: Double, area: Double, etaBlk: Double) -> FlowResult {
        precondition(t0 > model.tMin, "T0 必须大于有效温度下限")
        precondition(area > 0 && etaBlk > 0, "面积与 η_blk 必须为正")
        let flux = mdot / (area * etaBlk)
        let pk = peak(t0: t0, p0: p0)
        if flux > pk.g {
            return FlowResult(choked: true, gCrit: pk.g, tPeak: pk.t, flux: flux,
                              T: nil, P: nil, rho: nil, V: nil, a: nil, M: nil)
        }
        // 亚声速支括弧 [Tpeak, t0]，80 次二分
        var lo = pk.t, hi = t0
        for _ in 0..<AirModel.nBisect {
            let mid = (lo + hi) / 2
            if model.gRef(mid, t0: t0, p0: p0) < flux { hi = mid } else { lo = mid }
        }
        let T = (lo + hi) / 2
        let P = p0 * exp((model.s(T) - model.s(t0)) / model.r)
        let V = sqrt(2 * (model.h(t0) - model.h(T)))
        let a = sqrt(model.gamV(T) * model.r * T)
        return FlowResult(choked: false, gCrit: pk.g, tPeak: pk.t, flux: flux,
                          T: T, P: P, rho: P / (model.r * T), V: V, a: a, M: V / a)
    }
}
