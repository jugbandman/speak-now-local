import Foundation

enum MenuBarIconChoice: String, CaseIterable, Identifiable {
    case sparkles = "sparkles"
    case heartHands = "heart_hands"
    case bird = "bird.fill"
    case cat = "cat.fill"
    case heart = "heart.fill"
    case moon = "moon.fill"
    case wandAndStars = "wand.and.stars"
    case star = "star.fill"
    case mic = "mic.fill"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sparkles: return "Sparkles (Speak Now)"
        case .heartHands: return "Heart Hands 🫶"
        case .bird: return "Bird (1989)"
        case .cat: return "Cat (Meredith)"
        case .heart: return "Heart (Lover)"
        case .moon: return "Moon (Midnights)"
        case .wandAndStars: return "Magic Wand (Enchanted)"
        case .star: return "Star (Midnights)"
        case .mic: return "Microphone"
        }
    }

    var isEmoji: Bool {
        self == .heartHands
    }

    var sfSymbolName: String {
        rawValue
    }

    var emojiText: String {
        "🫶"
    }
}
