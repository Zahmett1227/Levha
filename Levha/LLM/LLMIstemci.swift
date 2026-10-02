import Foundation
import Security

struct LLMMesaj: Codable, Equatable {
    /// "user" | "assistant"
    let rol: String
    let icerik: String
}

/// Model gerektiren her özellik bu protokolün arkasındadır. Part 4'te tek uygulama `SahteLLMIstemci`;
/// gerçek sağlayıcı (OpenAI uyumlu) aynı protokolü uygulayacak.
protocol LLMIstemci {
    /// Metin, parça parça.
    func sor(sistem: String, mesajlar: [LLMMesaj]) -> AsyncThrowingStream<String, Error>
    /// Yalnız JSON cevabı.
    func jsonUret(sistem: String, istem: String) async throws -> Data
}

enum LLMHatasi: LocalizedError {
    case gecersizIstem(String)
    case sahteHata
    case http(Int, String)
    case reddedildi(Int, String)
    case cevrimdisi
    case bosYanit

    var errorDescription: String? {
        switch self {
        case .gecersizIstem(let m): return "İstem okunamadı: \(m)"
        case .sahteHata: return "Sahte bağlantı hatası (\"hata testi\" yazıldı)."
        case .http(401, _): return "Anahtar geçersiz"
        case .http(403, let m): return "Erişim reddedildi: \(m)"
        case .http(429, _): return "Hız sınırı, 20 sn sonra tekrar"
        case .http(let k, _) where k >= 500: return "Sağlayıcı hatası (\(k))"
        case .http(let k, let m), .reddedildi(let k, let m): return k > 0 ? "İstek reddedildi (\(k)): \(m)" : "İstek reddedildi: \(m)"
        case .cevrimdisi: return "Çevrimdışı"
        case .bosYanit: return "Boş yanıt (model çıktı üretmedi; max token düşük olabilir)"
        }
    }

    /// URLSession hatalarını kullanıcı diline çevirir.
    static func esle(_ hata: Error) -> Error {
        if hata is LLMHatasi { return hata }
        if let u = hata as? URLError {
            switch u.code {
            case .cancelled: return u
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
                 .timedOut, .dataNotAllowed, .internationalRoamingOff, .dnsLookupFailed:
                return LLMHatasi.cevrimdisi
            default: return u
            }
        }
        return hata
    }
}

/// Kullanım kaydında çağrının amacı.
enum LLMAmac: String, CaseIterable {
    case sor, genislet, editor, esleme
}

enum APIBicimi: String, CaseIterable, Identifiable {
    case chat, responses
    var id: String { rawValue }
    var ad: String { self == .chat ? "Chat (/chat/completions)" : "Responses (/responses)" }
}

enum LLMSaglayici: String, CaseIterable, Identifiable {
    case sahte
    case openaiUyumlu
    var id: String { rawValue }

    var ad: String {
        switch self {
        case .sahte: return "Sahte (çevrimdışı)"
        case .openaiUyumlu: return "OpenAI uyumlu"
        }
    }

    /// Bu sürümde seçilebilir mi?
    var hazir: Bool { true }
}

/// Ayarlar › Model. Anahtar Keychain'de, diğerleri UserDefaults'ta.
enum LLMAyarlari {
    static let varsayilanTabanURL = "https://api.openai.com/v1"
    static let varsayilanMaxToken = 800
    static let varsayilanModel = "chatgpt 5.6 luna"
    static let varsayilanSicaklik = 0.3

    private static let d = UserDefaults.standard

    static var saglayici: LLMSaglayici {
        get { LLMSaglayici(rawValue: d.string(forKey: "llmSaglayici") ?? "") ?? .sahte }
        set { d.set(newValue.rawValue, forKey: "llmSaglayici") }
    }

    static var apiTabanURL: String {
        get { d.string(forKey: "llmTabanURL") ?? varsayilanTabanURL }
        set { d.set(newValue, forKey: "llmTabanURL") }
    }

    /// Boş bırakılırsa varsayılan model.
    static var modelAdi: String {
        get { (d.string(forKey: "llmModelAdi")).flatMap { $0.isEmpty ? nil : $0 } ?? varsayilanModel }
        set { d.set(newValue, forKey: "llmModelAdi") }
    }

    static var apiBicimi: APIBicimi {
        get { APIBicimi(rawValue: d.string(forKey: "llmApiBicimi") ?? "") ?? .chat }
        set { d.set(newValue.rawValue, forKey: "llmApiBicimi") }
    }

    static var sicaklik: Double {
        get { d.object(forKey: "llmSicaklik") as? Double ?? varsayilanSicaklik }
        set { d.set(newValue, forKey: "llmSicaklik") }
    }

    /// Anahtarı olmayan "OpenAI uyumlu" seçimi açılışta Sahte'ye döner; Ayarlar bunu sarı uyarıyla gösterir.
    static var sahteyeDondu: Bool {
        get { d.bool(forKey: "llmSahteyeDondu") }
        set { d.set(newValue, forKey: "llmSahteyeDondu") }
    }

    static var maxCikisToken: Int {
        get { d.object(forKey: "llmMaxCikisToken") as? Int ?? varsayilanMaxToken }
        set { d.set(newValue, forKey: "llmMaxCikisToken") }
    }

    static var apiAnahtari: String {
        get { Anahtarlik.oku("apiAnahtari") ?? "" }
        set { Anahtarlik.yaz(newValue, "apiAnahtari") }
    }

    /// Anahtar varsa ve "OpenAI uyumlu" seçiliyse gerçek sağlayıcı, değilse sahte.
    static var sahteMi: Bool { saglayici == .sahte || apiAnahtari.isEmpty }

    static func istemci(_ amac: LLMAmac) -> LLMIstemci {
        guard !sahteMi, let url = URL(string: apiTabanURL.trimmingCharacters(in: .whitespaces)) else { return SahteLLMIstemci() }
        return OpenAIUyumluIstemci(tabanURL: url, anahtar: apiAnahtari, model: modelAdi, bicim: apiBicimi,
                                   maxCikis: maxCikisToken, sicaklik: sicaklik, amac: amac)
    }

    /// Açılışta: anahtarı olmayan gerçek sağlayıcı seçimi Sahte'ye döner.
    static func denetle() {
        if saglayici == .openaiUyumlu && apiAnahtari.isEmpty {
            saglayici = .sahte
            sahteyeDondu = true
        }
    }
}

/// Keychain (kSecClassGenericPassword, yalnız bu cihaz).
enum Anahtarlik {
    static let servis = "tr.kisisel.levha.model"

    static func oku(_ hesap: String) -> String? {
        let sorgu: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: servis,
            kSecAttrAccount as String: hesap, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var sonuc: AnyObject?
        guard SecItemCopyMatching(sorgu as CFDictionary, &sonuc) == errSecSuccess, let veri = sonuc as? Data else { return nil }
        return String(data: veri, encoding: .utf8)
    }

    /// Boş değer kaydı siler.
    static func yaz(_ deger: String, _ hesap: String) {
        let anahtar: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: servis, kSecAttrAccount as String: hesap,
        ]
        SecItemDelete(anahtar as CFDictionary)
        guard !deger.isEmpty else { return }
        var ekle = anahtar
        ekle[kSecValueData as String] = Data(deger.utf8)
        ekle[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(ekle as CFDictionary, nil)
    }
}

/// Ağ çağrısı yapmayan istemci: 400 ms gecikmeyle hazır metin ya da istemdeki `<veri>` bloğuna uyan küçük JSON döndürür.
struct SahteLLMIstemci: LLMIstemci {
    static let gecikme: Duration = .milliseconds(400)

    func sor(sistem: String, mesajlar: [LLMMesaj]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { devam in
            let gorev = Task {
                try? await Task.sleep(for: Self.gecikme)
                let soru = mesajlar.last?.icerik ?? ""
                // Türkçe klavye "testı" yazabilir: kelimeler ı→i katlanarak karşılaştırılır.
                if SayfaEsleme.kelimeler(soru).joined(separator: " ").contains("hata testi") {
                    devam.finish(throwing: LLMHatasi.sahteHata)
                    return
                }
                let baslik = IstemSablonlari.alan("Başlık", sistem) ?? "Bu levha"
                let dugum = IstemSablonlari.alan("Seçili düğüm", sistem).flatMap { $0 == "yok" ? nil : $0 }
                    .map { $0.replacingOccurrences(of: #" \([^)]*\)$"#, with: "", options: .regularExpression) }
                let metin = "«\(baslik)» levhasına göre bu sorunun yanıtı "
                    + (dugum.map { "«\($0)» düğümünün notunda ve ona bağlanan yolda duruyor. " } ?? "akılda kalan cümlede ve TUS vurgulu düğümlerde duruyor. ")
                    + "Bu, çevrimdışı sahte modelin hazır cevabıdır; emin olmadığın sayılar için kılavuza bak."
                // Kelime kelime akış.
                for parca in metin.split(separator: " ", omittingEmptySubsequences: false).map({ $0 + " " }) {
                    if Task.isCancelled { break }
                    devam.yield(String(parca))
                    try? await Task.sleep(for: .milliseconds(30))
                }
                devam.finish()
            }
            devam.onTermination = { _ in gorev.cancel() }
        }
    }

    func jsonUret(sistem: String, istem: String) async throws -> Data {
        try await Task.sleep(for: Self.gecikme)
        guard let veri = IstemSablonlari.veriBlogu(istem), let gorev = veri["gorev"] as? String else {
            throw LLMHatasi.gecersizIstem("<veri> bloğu yok")
        }
        let cikti: Any
        switch gorev {
        case "genislet": cikti = genislet(veri)
        case "degerlendir": cikti = degerlendir(veri)
        case "esleme": cikti = ["idler": ((veri["levhalar"] as? [[String: Any]]) ?? []).prefix(3).compactMap { $0["id"] as? String }]
        default: throw LLMHatasi.gecersizIstem("bilinmeyen görev \(gorev)")
        }
        return try JSONSerialization.data(withJSONObject: cikti, options: [.sortedKeys])
    }

    /// İlk iki boş konuma iki düğüm; ilki en yakın mevcut düğüme (ya da seçili düğüme) bağlanır.
    private func genislet(_ v: [String: Any]) -> [String: Any] {
        let bos = (v["bos_konumlar"] as? [[Int]]) ?? []
        let mevcut = (v["dugumler"] as? [[String: Any]]) ?? []
        let idler = Set(mevcut.compactMap { $0["id"] as? String })
        func yeniId(_ n: Int) -> String {
            var id = "y\(n)"
            var k = 2
            while idler.contains(id) { id = "y\(n)_\(k)"; k += 1 }
            return id
        }
        let konumlar = Array(bos.prefix(2))
        guard let ilk = konumlar.first else { return ["dugumler": [], "baglantilar": []] }
        let yakin = (v["secili"] as? String) ?? mevcut.min { a, b in
            uzaklik(a["konum"] as? [Int], ilk) < uzaklik(b["konum"] as? [Int], ilk)
        }?["id"] as? String
        var dugumler: [[String: Any]] = []
        var baglantilar: [[String: Any]] = []
        for (i, k) in konumlar.enumerated() {
            let id = yeniId(i + 1)
            dugumler.append(["id": id, "etiket": "Taslak düğüm \(i + 1)", "sekil": "durum", "renk": "gri",
                             "konum": k, "not": "Sahte model taslağı; içeriği kaynağa bakarak düzelt."])
            let onceki = i == 0 ? yakin : dugumler[i - 1]["id"] as? String
            if let onceki { baglantilar.append(["from": onceki, "to": id]) }
        }
        return ["dugumler": dugumler, "baglantilar": baglantilar]
    }

    private func uzaklik(_ a: [Int]?, _ b: [Int]) -> Int {
        guard let a, a.count == 2, b.count == 2 else { return .max }
        return abs(a[0] - b[0]) + abs(a[1] - b[1])
    }

    /// Ön denetimdeki her eksik 12 puan götürür; düzeltilmiş kök biçim hatalarını onarır.
    private func degerlendir(_ v: [String: Any]) -> [String: Any] {
        let kok = v["kok"] as? String ?? ""
        let secenekler = (v["secenekler"] as? [String]) ?? []
        let dogru = v["dogru"] as? Int ?? 0
        let satirlar = OnDenetim.denetle(kok: kok, secenekler: secenekler, dogru: dogru, klinik: v["klinik"] as? Bool ?? true)
        let eksik = satirlar.filter { !$0.gecti }
        func satir(_ ad: String) -> String {
            satirlar.first { $0.ad == ad }.map { ($0.gecti ? "Uygun: " : "Düzelt: ") + $0.mesaj } ?? "—"
        }
        var duzeltilmis = kok.replacingOccurrences(of: #"(\d)\.(\d)"#, with: "$1,$2", options: .regularExpression)
        for (a, b) in [("her zaman", "çoğunlukla"), ("hiçbir zaman", "nadiren"), ("asla", "nadiren"), ("sadece", "çoğunlukla"), ("daima", "çoğunlukla")] {
            duzeltilmis = duzeltilmis.replacingOccurrences(of: a, with: b, options: .caseInsensitive)
        }
        if !duzeltilmis.lowercased(with: Locale(identifier: "tr_TR")).contains("aşağıdakilerden hangisi") {
            if let r = duzeltilmis.range(of: "hangisidir?", options: .backwards) {
                duzeltilmis.replaceSubrange(r, with: "aşağıdakilerden hangisidir?")
            } else {
                duzeltilmis += " Bu hasta için en uygun seçenek aşağıdakilerden hangisidir?"
            }
        }
        return [
            "puan": max(35, 92 - 12 * eksik.count),
            "kalip_uyumu": true,
            "celdirici": "Sahte değerlendirme: çeldiricilerin aynı aileden ve spesifik olduğunu kendin kontrol et.",
            "kok_dili": satir("Soru cümlesi"),
            "uzunluk": [satir("Kök uzunluğu"), satir("Şık uzunluğu")].joined(separator: " · "),
            "ikinci_cevap": NSNull(),
            "oneriler": eksik.isEmpty ? ["Biçim kuralları temiz; içerik doğruluğunu kaynakla teyit et."] : eksik.map { "\($0.ad): \($0.mesaj)" },
            "duzeltilmis": ["kok": duzeltilmis, "secenekler": secenekler.map { $0.trimmingCharacters(in: .whitespaces) }, "dogru": dogru],
        ]
    }
}
