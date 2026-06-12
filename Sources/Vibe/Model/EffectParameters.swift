import Foundation

/// 全部音效参数(全局生效,作用于所有被接管的应用)
struct EffectParameters: Codable, Equatable {

    // MARK: 10 段图示 EQ
    var eqEnabled = false
    /// 各频段增益,单位 dB,范围 -12...+12
    var eqGains: [Float] = Array(repeating: 0, count: 10)
    /// 前级增益(dB),EQ 大幅提升时用来留余量
    var eqPreamp: Float = 0

    // MARK: 纯净低音 P.Bass(心理声学低音增强)
    var bassEnabled = false
    /// 强度 0...1
    var bassAmount: Float = 0.45
    /// 低频提取截止频率 60...160 Hz
    var bassFrequency: Float = 100

    // MARK: 清晰度激励(BBE 风格)
    var clarityEnabled = false
    /// 强度 0...1
    var clarityAmount: Float = 0.4
    /// 低频轮廓(Lo Contour)dB,0...6
    var clarityLowContour: Float = 2.0

    // MARK: 水晶人声(Crystal Voice)
    var crystalEnabled = false
    /// 亮度 0...1:3.2kHz 临场亮度 + 300Hz 去浑浊
    var crystalAmount: Float = 0.5
    /// 气感 0...1:11kHz 空气感高架
    var crystalAir: Float = 0.5

    // MARK: 空间环绕(SRS 风格)
    var spatialEnabled = false
    /// 声场宽度 0...1
    var spatialWidth: Float = 0.5
    /// 空间亮度 0...1
    var spatialBrightness: Float = 0.5

    // MARK: 临场感 C.Sound(Concert Sound 风格)
    var concertEnabled = false
    /// 强度 0...1
    var concertAmount: Float = 0.35
    /// 空间大小 0...1
    var concertSize: Float = 0.5

    // MARK: 动感响度(LifeVibes 风格等响度补偿)
    var loudnessEnabled = false
    /// 强度 0...1
    var loudnessAmount: Float = 0.5

    // MARK: 输出保护(常开)
    /// 限幅器输出上限 dBFS,-3...0
    var limiterCeilingDB: Float = -1.0

    /// EQ 中心频率
    static let eqFrequencies: [Float] = [31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    static let eqLabels = ["31", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]

    init() {}

    private enum CodingKeys: String, CodingKey {
        case eqEnabled, eqGains, eqPreamp
        case bassEnabled, bassAmount, bassFrequency
        case clarityEnabled, clarityAmount, clarityLowContour
        case crystalEnabled, crystalAmount, crystalAir
        case spatialEnabled, spatialWidth, spatialBrightness
        case concertEnabled, concertAmount, concertSize
        case loudnessEnabled, loudnessAmount
        case limiterCeilingDB
    }

    /// 容错解码:旧配置文件缺少新增字段时取默认值,不会整体重置
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = EffectParameters()
        eqEnabled = try c.decodeIfPresent(Bool.self, forKey: .eqEnabled) ?? d.eqEnabled
        var gains = try c.decodeIfPresent([Float].self, forKey: .eqGains) ?? d.eqGains
        if gains.count != 10 {
            gains = Array((gains + Array(repeating: 0, count: 10)).prefix(10))
        }
        eqGains = gains
        eqPreamp = try c.decodeIfPresent(Float.self, forKey: .eqPreamp) ?? d.eqPreamp
        bassEnabled = try c.decodeIfPresent(Bool.self, forKey: .bassEnabled) ?? d.bassEnabled
        bassAmount = try c.decodeIfPresent(Float.self, forKey: .bassAmount) ?? d.bassAmount
        bassFrequency = try c.decodeIfPresent(Float.self, forKey: .bassFrequency) ?? d.bassFrequency
        clarityEnabled = try c.decodeIfPresent(Bool.self, forKey: .clarityEnabled) ?? d.clarityEnabled
        clarityAmount = try c.decodeIfPresent(Float.self, forKey: .clarityAmount) ?? d.clarityAmount
        clarityLowContour = try c.decodeIfPresent(Float.self, forKey: .clarityLowContour) ?? d.clarityLowContour
        crystalEnabled = try c.decodeIfPresent(Bool.self, forKey: .crystalEnabled) ?? d.crystalEnabled
        crystalAmount = try c.decodeIfPresent(Float.self, forKey: .crystalAmount) ?? d.crystalAmount
        crystalAir = try c.decodeIfPresent(Float.self, forKey: .crystalAir) ?? d.crystalAir
        spatialEnabled = try c.decodeIfPresent(Bool.self, forKey: .spatialEnabled) ?? d.spatialEnabled
        spatialWidth = try c.decodeIfPresent(Float.self, forKey: .spatialWidth) ?? d.spatialWidth
        spatialBrightness = try c.decodeIfPresent(Float.self, forKey: .spatialBrightness) ?? d.spatialBrightness
        concertEnabled = try c.decodeIfPresent(Bool.self, forKey: .concertEnabled) ?? d.concertEnabled
        concertAmount = try c.decodeIfPresent(Float.self, forKey: .concertAmount) ?? d.concertAmount
        concertSize = try c.decodeIfPresent(Float.self, forKey: .concertSize) ?? d.concertSize
        loudnessEnabled = try c.decodeIfPresent(Bool.self, forKey: .loudnessEnabled) ?? d.loudnessEnabled
        loudnessAmount = try c.decodeIfPresent(Float.self, forKey: .loudnessAmount) ?? d.loudnessAmount
        limiterCeilingDB = try c.decodeIfPresent(Float.self, forKey: .limiterCeilingDB) ?? d.limiterCeilingDB
    }
}

/// 音效预设
struct Preset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var params: EffectParameters
}

enum BuiltinPresets {

    /// 默认推荐:温和 V 型 + 低音谐波 + 少量高频空气感,耐听不轰头
    static let recommended: Preset = {
        var p = EffectParameters()
        p.eqEnabled = true
        p.eqGains = [2.5, 2.0, 1.0, 0, -0.5, -0.5, 0.5, 1.5, 2.5, 3.0]
        p.eqPreamp = -2
        p.bassEnabled = true
        p.bassAmount = 0.35
        p.bassFrequency = 95
        p.clarityEnabled = true
        p.clarityAmount = 0.3
        p.clarityLowContour = 1.5
        p.spatialEnabled = true
        p.spatialWidth = 0.35
        p.spatialBrightness = 0.4
        p.loudnessEnabled = true
        p.loudnessAmount = 0.35
        return Preset(name: "Vibe 推荐", params: p)
    }()

    static let passthrough = Preset(name: "原声直通", params: EffectParameters())

    static let deepBass: Preset = {
        var p = EffectParameters()
        p.eqEnabled = true
        p.eqGains = [4.0, 3.5, 2.0, 0.5, 0, 0, 0, 0.5, 1.0, 1.0]
        p.eqPreamp = -3
        p.bassEnabled = true
        p.bassAmount = 0.7
        p.bassFrequency = 110
        p.loudnessEnabled = true
        p.loudnessAmount = 0.5
        return Preset(name: "醇厚低音", params: p)
    }()

    static let concert: Preset = {
        var p = EffectParameters()
        p.concertEnabled = true
        p.concertAmount = 0.6
        p.concertSize = 0.65
        p.spatialEnabled = true
        p.spatialWidth = 0.55
        p.spatialBrightness = 0.45
        p.loudnessEnabled = true
        p.loudnessAmount = 0.45
        p.bassEnabled = true
        p.bassAmount = 0.3
        return Preset(name: "演唱会现场", params: p)
    }()

    static let vocal: Preset = {
        var p = EffectParameters()
        p.eqEnabled = true
        p.eqGains = [-1.0, -1.0, 0, 1.0, 2.5, 3.0, 2.5, 1.5, 0.5, 0]
        p.eqPreamp = -2
        p.clarityEnabled = true
        p.clarityAmount = 0.6
        p.clarityLowContour = 0.5
        return Preset(name: "人声清晰", params: p)
    }()

    static let vShape: Preset = {
        var p = EffectParameters()
        p.eqEnabled = true
        p.eqGains = [5.0, 4.0, 2.0, 0, -1.5, -1.5, 0, 2.0, 4.0, 4.5]
        p.eqPreamp = -4
        p.bassEnabled = true
        p.bassAmount = 0.5
        p.bassFrequency = 100
        p.spatialEnabled = true
        p.spatialWidth = 0.4
        p.spatialBrightness = 0.5
        return Preset(name: "律动 V 型", params: p)
    }()

    /// 水晶亮嗓:人声透亮如水晶——3.2kHz 亮度 + 11kHz 空气感,
    /// 避开 6–8kHz 齿音区,亮而不刺
    static let crystalVocal: Preset = {
        var p = EffectParameters()
        p.eqEnabled = true
        p.eqGains = [-1.5, -1.0, -0.5, 0, 1.0, 2.0, 2.0, 1.5, 1.0, 0.5]
        p.eqPreamp = -2
        p.crystalEnabled = true
        p.crystalAmount = 0.65
        p.crystalAir = 0.6
        p.clarityEnabled = true
        p.clarityAmount = 0.35
        p.clarityLowContour = 0.5
        p.spatialEnabled = true
        p.spatialWidth = 0.25
        p.spatialBrightness = 0.55
        return Preset(name: "水晶亮嗓", params: p)
    }()

    static let all: [Preset] = [passthrough, recommended, crystalVocal, deepBass, concert, vocal, vShape]
}
