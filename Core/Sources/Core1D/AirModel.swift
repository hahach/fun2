// ---------------------------------------------------------------
// AirModel.swift —— 干空气一维气动参考内核（golden.json 对拍实现）
//
// 移植蓝本：仓内 work/model/kernel.mjs；移植前已经 node 算法证明书
//（.tmp/swift-alg-proof.mjs）逐域对拍全绿：cp ≤ polyTol(1e-9)，
// han/phi/ts/eval/flow/conv ≤ integrateTol(1e-6)。
//
// 与参考内核唯一的算法差异（有意为之，证明书已用数字证明）：
//   焓/熵不用 20 万步复合梯形，而用多项式闭式原函数——把 golden.coeffs.poly
//  （x=(T−tMid)/tScale 空间）展开为 T 幂系数 c0..c4，
//     h(T)−h(t0) = Σ_{k≥1} c_{k−1}/k·(T^k − t0^k)
//     s(T)−s(t0) = c0·ln(T/t0) + Σ_{k≥1} c_k/k·(T^k − t0^k)
//   闭式相对 20 万步梯形的偏差：h 6.9e-13、s 2.4e-10（相对量），
//   距 integrateTol=1e-6 分别有 6.2 / 3.6 个数量级裕度。
// 其余结构 1:1 复刻 kernel.mjs：全部二分 80 次、相同括弧、相同方向；
// TinvPi 保留 M>2.5 的增支分支；近堵塞防护见 FlowSolver。
//
// 单位约定（= golden.meta.units）：
//   T/t0/tRef/tMin/tMax [K]、p [Pa 绝对]、h [J/kg]、s/cp/R [J/(kg·K)]、
//   密流 g [kg/(m²·s)]、V/a [m/s]、ρ [kg/m³]、M/γ/π/η 无量纲、功 [kW]（调用方 /1000）。
// ---------------------------------------------------------------
import Foundation

public struct AirModel {

    /// 拟合系数 b0..b4（x=(T−tMid)/tScale 空间）= golden.coeffs.poly
    /// = 工作簿 cp(T) 表 I17:I21（引擎正规方程最小二乘解）
    public let poly: [Double]
    /// x 空间中点 [K]（cp 数据表中点）
    public let tMid: Double
    /// x 空间半宽 [K]
    public let tScale: Double
    /// 焓/熵基准温度 [K]（= 数据最低温）
    public let tRef: Double
    /// 干空气气体常数 [J/(kg·K)]（= golden.coeffs.r）
    public let r: Double
    /// 有效温度下限 [K]
    public let tMin: Double
    /// 有效温度上限 [K]
    public let tMax: Double

    /// T 幂系数 c0..c4（由 poly 展开，仅供 h/s 闭式原函数使用）
    private let c: [Double]

    /// 全部二分反演的固定迭代次数（kernel.mjs 同款）
    public static let nBisect = 80

    public init(poly: [Double], tMid: Double, tScale: Double, tRef: Double,
                r: Double, tMin: Double, tMax: Double) {
        precondition(poly.count == 5 && poly.allSatisfy({ $0.isFinite }),
                     "poly 必须是 5 个有限数 b0..b4")
        precondition([tMid, tScale, tRef, r, tMin, tMax].allSatisfy({ $0.isFinite }),
                     "模型常数必须全是有限数")
        self.poly = poly
        self.tMid = tMid
        self.tScale = tScale
        self.tRef = tRef
        self.r = r
        self.tMin = tMin
        self.tMax = tMax

        // x^j = ((T−m)/s)^j = s^(−j)·Σ_{i≤j} C(j,i)·T^i·(−m)^(j−i)，按二项式表展开
        let binom = [[1], [1, 1], [1, 2, 1], [1, 3, 3, 1], [1, 4, 6, 4, 1]]
        var expanded = [Double](repeating: 0, count: 5)
        for j in 0...4 {
            for i in 0...j {
                expanded[i] += poly[j] * Double(binom[j][i])
                    * pow(-tMid, Double(j - i)) / pow(tScale, Double(j))
            }
        }
        self.c = expanded
    }

    /// 工作簿基线模型：数值 = golden.coeffs 硬编码（2026-11 基线；
    /// 若工作簿重新拟合，须用新 cp(T) 表 I17:I21 同步这里与 golden）
    public static func standard() -> AirModel {
        AirModel(
            poly: [1149.276388198407, 181.6696577000325, -91.69178411911707,
                   -57.15698689258344, 70.03676943845494],
            tMid: 1050,
            tScale: 950,
            tRef: 100,
            r: 287.02,
            tMin: 100,
            tMax: 2000)
    }

    // MARK: - 直接求值

    /// 比热容 cp(T) [J/(kg·K)]：x 空间 Horner 求值（工作簿 CP 函数语义）
    public func cp(_ T: Double) -> Double {
        let x = (T - tMid) / tScale
        return (((poly[4] * x + poly[3]) * x + poly[2]) * x + poly[1]) * x + poly[0]
    }

    /// 参考比焓 h(T)−h(tRef) [J/kg]：闭式原函数（工作簿 HAN 函数参考语义，
    /// = ∫[tRef→T] cp dT 的连续精确值；对拍容差见证明书）
    public func h(_ T: Double) -> Double {
        var sum = 0.0
        for k in 1...5 {
            sum += c[k - 1] / Double(k) * (pow(T, Double(k)) - pow(tRef, Double(k)))
        }
        return sum
    }

    /// 参考比熵 s(T)−s(tRef) [J/(kg·K)]：闭式原函数（工作簿 PHI 函数参考语义，
    /// = ∫[tRef→T] (cp/T) dT 的连续精确值）
    public func s(_ T: Double) -> Double {
        var sum = c[0] * log(T / tRef)
        for k in 1...4 {
            sum += c[k] / Double(k) * (pow(T, Double(k)) - pow(tRef, Double(k)))
        }
        return sum
    }

    /// 比热比 γ(T) [1]：cp/(cp−R)
    public func gamV(_ T: Double) -> Double {
        cp(T) / (cp(T) - r)
    }

    // MARK: - 二分反演（80 次、同括弧、同方向 = kernel.mjs）

    /// 等熵温度 TS(T0, π) [K]：解 s(Ts)−s(T0) = R·ln π，[tMin,tMax] 上二分
    /// （工作簿 TS 函数参考语义；kernel.mjs 的 Rv 参数在全部消费方恒取模型 R）
    public func ts(t0: Double, pi: Double) -> Double {
        let target = s(t0) + r * log(pi)
        var lo = tMin, hi = tMax
        for _ in 0..<Self.nBisect {
            let mid = (lo + hi) / 2
            if s(mid) < target { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    /// 焓反求温度 [K]：解 h(T) = hVal，[tMin,tMax] 上二分（工作簿 HANT 参考语义）
    public func invertH(_ hVal: Double) -> Double {
        var lo = tMin, hi = tMax
        for _ in 0..<Self.nBisect {
            let mid = (lo + hi) / 2
            if h(mid) < hVal { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    /// 管流密流 g(T) [kg/(m²·s)]：等熵+能量+状态，g = P·V/(R·T)；
    /// V = √(2(h(T0)−h(T)))，P = P0·exp((s(T)−s(T0))/R)
    public func gRef(_ T: Double, t0: Double, p0: Double) -> Double {
        let v = sqrt(2 * (h(t0) - h(T)))
        let p = p0 * exp((s(T) - s(t0)) / r)
        return p * v / (r * T)
    }

    /// 密流反求静温 [K]：解 g(T) = target，[tMin,t0] 上二分，收敛到亚声速支
    /// （工作簿管流网格反演参考语义）。注意：密流接近临界时默认括弧的初始
    /// 中点落在超声速支、会收敛到错误端——App 侧一律走 FlowSolver（细扫找峰
    /// + [Tpeak,t0] 括弧），本方法保留作为 kernel.mjs 的 1:1 对拍基线。
    public func invertG(_ target: Double, t0: Double, p0: Double) -> Double {
        var lo = tMin, hi = t0
        for _ in 0..<Self.nBisect {
            let mid = (lo + hi) / 2
            if gRef(mid, t0: t0, p0: p0) < target { hi = mid } else { lo = mid }
        }
        return (lo + hi) / 2
    }

    // MARK: - 外推段（总静换算用；T>tMax 沿端点斜率线性外推 = 工作簿『拟合内部』J/L 列语义）

    /// 外推版参考焓 [J/kg]：T>tMax 沿 (tMax, cp(tMax)) 线性外推
    public func hRefX(_ T: Double) -> Double {
        T <= tMax ? h(T) : h(tMax) + cp(tMax) * (T - tMax)
    }

    /// 外推版参考熵 [J/(kg·K)]：T>tMax 沿端点斜率 cp(tMax)/tMax 线性外推
    public func sRefX(_ T: Double) -> Double {
        T <= tMax ? s(T) : s(tMax) + (cp(tMax) / tMax) * (T - tMax)
    }

    /// 焓反求温度（含外推段）[K]：h ≥ h(tMax) 时直接线性外推，否则二分
    public func HANTx(_ hVal: Double) -> Double {
        if hVal >= hRefX(tMax) { return tMax + (hVal - hRefX(tMax)) / cp(tMax) }
        var lo = tMin, hi = tMax
        for _ in 0..<Self.nBisect {
            let mid = (lo + hi) / 2
            if hRefX(mid) < hVal { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    // MARK: - 总静换算（均用外推版 hRefX/sRefX）

    /// 由 (T, M) 反求总温 T0 [K]：T0 = HANTx(h(T) + ½M²γRT)，可越过 tMax 外推
    public func T0ofV(_ T: Double, _ M: Double) -> Double {
        HANTx(hRefX(T) + 0.5 * M * M * gamV(T) * r * T)
    }

    /// 由 (T0, T) 求马赫数 M [1]：√(2(h(T0)−h(T))/(γ(T)·R·T))
    public func MofV(_ t0: Double, _ T: Double) -> Double {
        sqrt(2 * (hRefX(t0) - hRefX(T)) / (gamV(T) * r * T))
    }

    /// 由 (T0, T) 求总静压比 π = P0/P [1]：exp((s(T0)−s(T))/R)
    public func piV(_ t0: Double, _ T: Double) -> Double {
        exp((sRefX(t0) - sRefX(T)) / r)
    }

    /// 由 (T0, M) 反求静温 T [K]：解 h(T)+½M²γ(T)RT = h(T0)，[tMin,tMax] 上二分
    public func TinvV(_ t0: Double, _ M: Double) -> Double {
        let target = hRefX(t0)
        var lo = tMin, hi = tMax
        for _ in 0..<Self.nBisect {
            let mid = (lo + hi) / 2
            let f = hRefX(mid) + 0.5 * M * M * gamV(mid) * r * mid
            if f < target { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    /// 由 (π 目标, M) 反求静温 T [K]：解 π(T0(T), T) = π目标，[tMin,tMax] 上二分；
    /// M > 2.5 时 π 随 T 递增（p<π目标 → lo 上移），否则递减（kernel.mjs 分支）
    public func TinvPi(_ piTarget: Double, _ M: Double) -> Double {
        let increasing = M > 2.5
        var lo = tMin, hi = tMax
        for _ in 0..<Self.nBisect {
            let mid = (lo + hi) / 2
            let p = piV(T0ofV(mid, M), mid)
            if (increasing && p < piTarget) || (!increasing && p > piTarget) { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }
}

/// 温标换算（工作簿 ℃/K 双格关系 273.15 的单一出处）
public enum TempScale {
    public static let celsiusOffset = 273.15

    /// 输入值换算为开尔文
    public static func toKelvin(_ value: Double, isCelsius: Bool) -> Double {
        isCelsius ? value + celsiusOffset : value
    }
}

/// 压强单位换算（工作簿单位 Pa 的单一出处；bar = 1e5 Pa）
public enum PressureScale {
    public static let paPerBar = 100_000.0

    /// 输入值换算为帕斯卡
    public static func toPascal(_ value: Double, isBar: Bool) -> Double {
        isBar ? value * paPerBar : value
    }

    /// 帕斯卡换算为显示单位
    public static func fromPascal(_ p: Double, isBar: Bool) -> Double {
        isBar ? p / paPerBar : p
    }
}
