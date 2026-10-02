import SwiftUI
import Observation

/// Sekme seçimi ve dışarıdan gelen açma istekleri (deep link, App Intent).
@Observable
@MainActor
final class Yonlendirici {
    static let ortak = Yonlendirici()

    var sekme: Sekme = Sekme(rawValue: UserDefaults.standard.string(forKey: "baslangicSekme") ?? "") ?? .bugun
    /// Levha sekmesinde açılacak levha ve mod; `istek` her yeni istekte artar.
    private(set) var hedefLevhaId: String?
    private(set) var hedefMod: LevhaModu?
    private(set) var istek = 0

    /// levha://levha/<id>?mode=ortme · levha://bugun
    func ac(_ url: URL) {
        guard url.scheme == "levha" else { return }
        switch url.host() {
        case "levha":
            guard let id = url.pathComponents.dropFirst().first else { return }
            let mod = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "mode" }?.value.flatMap(LevhaModu.init(rawValue:))
            levhaAc(id, mod: mod)
        case "bugun":
            sekme = .bugun
        default:
            break
        }
    }

    func levhaAc(_ id: String, mod: LevhaModu?) {
        hedefLevhaId = id
        hedefMod = mod
        istek += 1
        sekme = .levha
    }
}
