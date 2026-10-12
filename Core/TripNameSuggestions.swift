import Foundation

enum TripNameSuggestions {
    static let places = [
        "京都", "东京", "大阪", "奈良", "神户", "札幌", "福冈", "冲绳", "首尔", "釜山",
        "北京", "上海", "杭州", "苏州", "南京", "成都", "重庆", "西安", "厦门", "青岛",
        "大理", "丽江", "桂林", "长沙", "武汉", "广州", "深圳", "台北", "香港", "澳门"
    ]
    static let themes = [
        "美食", "风景", "休闲", "漫步", "探索", "文化", "历史", "摄影", "自然", "人文",
        "寻味", "小憩", "慢游", "发现", "赏景", "散心", "闲逛", "拾光", "寻趣", "放松"
    ]
    static let rollDuration: TimeInterval = 1.4
    static let holdDuration: TimeInterval = 3

    static func roll(from current: String, words: [String]) -> [String] {
        [current] + (0..<Int.random(in: 4...5)).map { _ in words.randomElement()! }
    }

    static func progress(elapsed: TimeInterval) -> Double {
        let t = min(max(elapsed / rollDuration, 0), 1)
        return t * t * (3 - 2 * t)
    }
}
