import Foundation
import Core1D

// 各页输入的持久化：UserDefaults 存 Codable JSON，属性 didSet 即存
//（击键粒度，数据量小可接受）。只持久化原始输入文本与温标/几何开关，
// 不持久化任何计算结果——结果一律由 Core1D 实时重算。

/// 评估页表单（压气机块 + 涡轮块）
final class EvaluateForm: ObservableObject, Codable {
    static let storageKey = "evaluateForm.v1"

    @Published var compPi = "" { didSet { save() } }
    @Published var compT1 = "" { didSet { save() } }
    @Published var compT1Celsius = false { didSet { save() } }
    @Published var compEta = "" { didSet { save() } }
    @Published var compMdot = "" { didSet { save() } }
    @Published var turbEps = "" { didSet { save() } }
    @Published var turbT1 = "" { didSet { save() } }
    @Published var turbT1Celsius = false { didSet { save() } }
    @Published var turbEta = "" { didSet { save() } }
    @Published var turbMdot = "" { didSet { save() } }

    init() {}

    private enum Keys: String, CodingKey {
        case compPi, compT1, compT1Celsius, compEta, compMdot
        case turbEps, turbT1, turbT1Celsius, turbEta, turbMdot
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(compPi, forKey: .compPi)
        try c.encode(compT1, forKey: .compT1)
        try c.encode(compT1Celsius, forKey: .compT1Celsius)
        try c.encode(compEta, forKey: .compEta)
        try c.encode(compMdot, forKey: .compMdot)
        try c.encode(turbEps, forKey: .turbEps)
        try c.encode(turbT1, forKey: .turbT1)
        try c.encode(turbT1Celsius, forKey: .turbT1Celsius)
        try c.encode(turbEta, forKey: .turbEta)
        try c.encode(turbMdot, forKey: .turbMdot)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        compPi = try c.decodeIfPresent(String.self, forKey: .compPi) ?? ""
        compT1 = try c.decodeIfPresent(String.self, forKey: .compT1) ?? ""
        compT1Celsius = try c.decodeIfPresent(Bool.self, forKey: .compT1Celsius) ?? false
        compEta = try c.decodeIfPresent(String.self, forKey: .compEta) ?? ""
        compMdot = try c.decodeIfPresent(String.self, forKey: .compMdot) ?? ""
        turbEps = try c.decodeIfPresent(String.self, forKey: .turbEps) ?? ""
        turbT1 = try c.decodeIfPresent(String.self, forKey: .turbT1) ?? ""
        turbT1Celsius = try c.decodeIfPresent(Bool.self, forKey: .turbT1Celsius) ?? false
        turbEta = try c.decodeIfPresent(String.self, forKey: .turbEta) ?? ""
        turbMdot = try c.decodeIfPresent(String.self, forKey: .turbMdot) ?? ""
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    static func load() -> EvaluateForm {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let form = try? JSONDecoder().decode(EvaluateForm.self, from: data) else {
            return EvaluateForm()
        }
        return form
    }
}

/// 管流页表单（A 与 r 双输入，用开关选择生效的那一个）
final class FlowForm: ObservableObject, Codable {
    static let storageKey = "flowForm.v1"

    @Published var mdot = "" { didSet { save() } }
    @Published var t0 = "" { didSet { save() } }
    @Published var t0Celsius = false { didSet { save() } }
    @Published var p0 = "" { didSet { save() } }
    @Published var etaBlk = "0.97" { didSet { save() } }
    @Published var useRadius = false { didSet { save() } }
    @Published var area = "" { didSet { save() } }
    @Published var radius = "" { didSet { save() } }

    init() {}

    private enum Keys: String, CodingKey {
        case mdot, t0, t0Celsius, p0, etaBlk, useRadius, area, radius
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(mdot, forKey: .mdot)
        try c.encode(t0, forKey: .t0)
        try c.encode(t0Celsius, forKey: .t0Celsius)
        try c.encode(p0, forKey: .p0)
        try c.encode(etaBlk, forKey: .etaBlk)
        try c.encode(useRadius, forKey: .useRadius)
        try c.encode(area, forKey: .area)
        try c.encode(radius, forKey: .radius)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        mdot = try c.decodeIfPresent(String.self, forKey: .mdot) ?? ""
        t0 = try c.decodeIfPresent(String.self, forKey: .t0) ?? ""
        t0Celsius = try c.decodeIfPresent(Bool.self, forKey: .t0Celsius) ?? false
        p0 = try c.decodeIfPresent(String.self, forKey: .p0) ?? ""
        etaBlk = try c.decodeIfPresent(String.self, forKey: .etaBlk) ?? "0.97"
        useRadius = try c.decodeIfPresent(Bool.self, forKey: .useRadius) ?? false
        area = try c.decodeIfPresent(String.self, forKey: .area) ?? ""
        radius = try c.decodeIfPresent(String.self, forKey: .radius) ?? ""
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    static func load() -> FlowForm {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let form = try? JSONDecoder().decode(FlowForm.self, from: data) else {
            return FlowForm()
        }
        return form
    }
}

/// 总静换算页表单（五槽）
final class ConvForm: ObservableObject, Codable {
    static let storageKey = "convForm.v1"

    @Published var t0 = "" { didSet { save() } }
    @Published var t0Celsius = false { didSet { save() } }
    @Published var p0 = "" { didSet { save() } }
    @Published var t = "" { didSet { save() } }
    @Published var tCelsius = false { didSet { save() } }
    @Published var p = "" { didSet { save() } }
    @Published var m = "" { didSet { save() } }

    init() {}

    private enum Keys: String, CodingKey {
        case t0, t0Celsius, p0, t, tCelsius, p, m
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(t0, forKey: .t0)
        try c.encode(t0Celsius, forKey: .t0Celsius)
        try c.encode(p0, forKey: .p0)
        try c.encode(t, forKey: .t)
        try c.encode(tCelsius, forKey: .tCelsius)
        try c.encode(p, forKey: .p)
        try c.encode(m, forKey: .m)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        t0 = try c.decodeIfPresent(String.self, forKey: .t0) ?? ""
        t0Celsius = try c.decodeIfPresent(Bool.self, forKey: .t0Celsius) ?? false
        p0 = try c.decodeIfPresent(String.self, forKey: .p0) ?? ""
        t = try c.decodeIfPresent(String.self, forKey: .t) ?? ""
        tCelsius = try c.decodeIfPresent(Bool.self, forKey: .tCelsius) ?? false
        p = try c.decodeIfPresent(String.self, forKey: .p) ?? ""
        m = try c.decodeIfPresent(String.self, forKey: .m) ?? ""
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    static func load() -> ConvForm {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let form = try? JSONDecoder().decode(ConvForm.self, from: data) else {
            return ConvForm()
        }
        return form
    }
}
