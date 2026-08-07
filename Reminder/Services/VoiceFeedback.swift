import Foundation
import AVFoundation

/// Głosowe potwierdzenie po polsku (AVSpeechSynthesizer).
final class VoiceFeedback {
    static let shared = VoiceFeedback()
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "pl-PL")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }
}
