import AVFoundation

@MainActor
final class SpeechService {
    static let shared = SpeechService()

    private let synthesizer = AVSpeechSynthesizer()
    private let preferences = AppPreferences.shared

    private init() {}

    func speak(_ text: String, language: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        synthesizer.stopSpeaking(at: .immediate)

        let chunks = splitIntoNaturalChunks(trimmed)
        if chunks.count <= 1 {
            synthesizer.speak(makeUtterance(chunks.first ?? trimmed, language: language))
            return
        }

        for (index, chunk) in chunks.enumerated() {
            let isLast = index == chunks.count - 1
            synthesizer.speak(makeUtterance(chunk, language: language, isLast: isLast))
        }
    }

    private func bestVoice(for language: String) -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let exact = voices.filter { $0.language == language }
        if let preferred = rankedVoice(from: exact) {
            return preferred
        }

        let family = voices.filter { $0.language.hasPrefix(String(language.prefix(2))) }
        return rankedVoice(from: family)
    }

    private func rankedVoice(from voices: [AVSpeechSynthesisVoice]) -> AVSpeechSynthesisVoice? {
        voices.sorted { lhs, rhs in
            let lScore = voiceScore(lhs, role: preferences.speechRolePreset)
            let rScore = voiceScore(rhs, role: preferences.speechRolePreset)
            if lScore == rScore {
                return lhs.name < rhs.name
            }
            return lScore > rScore
        }.first
    }

    private func voiceScore(_ voice: AVSpeechSynthesisVoice, role: SpeechRolePreset) -> Int {
        var score = 0
        switch voice.quality {
        case .premium:
            score += 300
        case .enhanced:
            score += 200
        default:
            score += 100
        }

        let name = voice.name.lowercased()
        if name.contains("siri") { score += 40 }
        if name.contains("neural") { score += 30 }
        if name.contains("natural") { score += 20 }
        score += roleBonus(name: name, role: role)
        return score
    }

    private func makeUtterance(_ text: String, language: String, isLast: Bool = true) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = bestVoice(for: language) ?? AVSpeechSynthesisVoice(language: language)

        // Prosody tuning: closer to natural speaking rhythm.
        if language.hasPrefix("zh") {
            utterance.rate = 0.43
            utterance.pitchMultiplier = 1.02
        } else {
            utterance.rate = 0.45
            utterance.pitchMultiplier = 1.01
        }
        applyRolePreset(utterance, role: preferences.speechRolePreset)
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.02
        utterance.postUtteranceDelay = isLast ? 0.05 : 0.11
        return utterance
    }

    private func splitIntoNaturalChunks(_ text: String) -> [String] {
        let separators = CharacterSet(charactersIn: "。！？!?；;，,\n")
        let parts = text
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Avoid over-segmentation for short text.
        if parts.count <= 1 { return [text] }
        return parts
    }

    private func roleBonus(name: String, role: SpeechRolePreset) -> Int {
        switch role {
        case .balanced:
            return 0
        case .warmFemale:
            return hasAnyKeyword(name, [
                "female", "samantha", "ava", "victoria", "karen", "moira",
                "ting", "xiaoxiao", "xiaochen", "siri"
            ]) ? 55 : 0
        case .steadyMale:
            return hasAnyKeyword(name, [
                "male", "alex", "daniel", "fred", "yu", "yunjian", "siri"
            ]) ? 55 : 0
        case .brightNarrator:
            return hasAnyKeyword(name, [
                "narrator", "news", "siri", "neural", "premium"
            ]) ? 55 : 0
        }
    }

    private func applyRolePreset(_ utterance: AVSpeechUtterance, role: SpeechRolePreset) {
        switch role {
        case .balanced:
            break
        case .warmFemale:
            // Softer and warmer: slower pace + higher pitch.
            utterance.pitchMultiplier = min(1.35, utterance.pitchMultiplier + 0.14)
            utterance.rate = max(0.34, utterance.rate - 0.05)
            utterance.postUtteranceDelay += 0.02
        case .steadyMale:
            // Deeper and calmer: lower pitch + slower pace.
            utterance.pitchMultiplier = max(0.78, utterance.pitchMultiplier - 0.12)
            utterance.rate = max(0.34, utterance.rate - 0.04)
            utterance.postUtteranceDelay += 0.015
        case .brightNarrator:
            // Brighter and energetic: slightly higher pitch + faster pace.
            utterance.pitchMultiplier = min(1.26, utterance.pitchMultiplier + 0.06)
            utterance.rate = min(0.56, utterance.rate + 0.06)
        }
    }

    private func hasAnyKeyword(_ value: String, _ keywords: [String]) -> Bool {
        keywords.contains { value.contains($0) }
    }
}
