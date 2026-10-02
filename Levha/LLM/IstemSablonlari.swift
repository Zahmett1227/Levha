import Foundation

/// Tüm model istemleri tek yerde. JSON isteyen istemler, makinece okunacak verileri `<veri>…</veri>` bloğunda da taşır
/// (sahte istemci bunu okur; gerçek model için ek bağlamdır).
@MainActor
enum IstemSablonlari {
    // MARK: - Sor

    static func sorSistemi(levha: Levha, seciliDugum: Dugum?) -> String {
        let kazanimlar = levha.paket?.kazanimlar(levha) ?? []
        var s = """
        TUS hazırlığı yapan bir hekime, aşağıdaki levha bağlamında, en fazla 150 kelimeyle cevap ver. \
        Emin olmadığın sayıları "kılavuza bak" diye işaretle.

        Levha:
        \(levhaOzeti(levha))
        """
        if !kazanimlar.isEmpty {
            s += "\nKazanımlar:\n" + kazanimlar.map { "- \($0.id): \($0.metin)" }.joined(separator: "\n")
        }
        s += "\nSeçili düğüm: " + (seciliDugum.map { "\($0.etiket) (\($0.id))" } ?? "yok")
        return s
    }

    static func levhaOzeti(_ levha: Levha) -> String {
        var s = "Başlık: \(levha.baslik)\nTip: \(levha.tipAdi)\nAkılda kalan: \(levha.akilda_kalan)\nDüğümler:\n"
        s += levha.siraliDugumler.map { d in "- \(d.id) · \(d.etiket)" + (d.not.isEmpty ? "" : " — \(d.not)") }.joined(separator: "\n")
        let etiket = Dictionary(levha.dugumler.map { ($0.id, $0.etiket) }, uniquingKeysWith: { a, _ in a })
        let baglantilar = levha.siraliBaglantilar
        if !baglantilar.isEmpty {
            s += "\nBağlantılar:\n" + baglantilar.map { b in
                "- \(etiket[b.from] ?? b.from) → \(etiket[b.to] ?? b.to)" + (b.etiket.isEmpty ? "" : " (\(b.etiket))")
            }.joined(separator: "\n")
        }
        return s
    }

    // MARK: - Genişlet

    static let genisletSistemi = """
    TUS levhaları hazırlayan bir editörsün. Yalnız geçerli JSON döndür; açıklama, markdown ya da kod bloğu yazma. \
    Emin olmadığın sayıyı yazma; düğüm notuna "kaynağa bak" yaz.
    """

    static func genisletIstemi(levha: Levha, bosKonumlar: [[Int]], seciliDugum: String?, cevap: String?) -> String {
        let konumMetni = bosKonumlar.map { "[\($0[0]), \($0[1])]" }.joined(separator: ", ")
        var s = """
        Bu levhaya eklenmesi gereken 2–5 düğümü ve bağlantılarını, şema v4'e uygun yalnız JSON olarak döndür \
        (`dugumler`, `baglantilar`, boş ızgara konumlarını kullan: \(konumMetni)).
        Biçim: {"dugumler": [{"id": "yeni tekil id", "etiket": "en fazla 28 karakter", "sekil": "durum|karar|surec|madde", \
        "renk": "kirmizi|mavi|yesil|sari|gri", "konum": [sütun, satır], "tus": false, "not": "..."}], \
        "baglantilar": [{"from": "id", "to": "id", "etiket": "isteğe bağlı", "tip": "normal|inhibe|uyarir|olasi"}]}
        Her bağlantının en az bir ucu yeni düğüm olmalı.

        Levha (ızgara \(levha.izgara.first ?? 0) sütun × \(levha.izgara.last ?? 0) satır):
        \(levhaOzeti(levha))
        """
        if let cevap { s += "\n\nBu genişletmeyi isteyen cevap:\n\(cevap)" }
        var veri: [String: Any] = [
            "gorev": "genislet",
            "bos_konumlar": bosKonumlar,
            "dugumler": levha.siraliDugumler.map { ["id": $0.id, "konum": $0.konum] },
        ]
        if let seciliDugum { veri["secili"] = seciliDugum }
        return s + "\n\n" + veriBlogu(veri)
    }

    // MARK: - Editör

    static let editorSistemi = """
    ÖSYM TUS soru editörüsün. Kullanıcının yazdığı soruyu şu kurallarla değerlendir:
    1. ÖSYM kök dili: soru "aşağıdakilerden hangisidir?" kalıbıyla biter; vaka üçüncü tekil, resmî dille anlatılır; ondalıkta virgül kullanılır.
    2. Klinik kök 50–80 kelimedir.
    3. Şık uzunlukları dengelidir: doğru şık diğerlerinden 15 karakterden fazla uzun olmaz.
    4. Mutlak ifade yoktur (her zaman, asla, sadece).
    5. Çeldiriciler doğru cevapla aynı aileden ve spesifiktir.
    6. Tek bir savunulabilir doğru cevap vardır.
    7. Soru belirtilen kalıba uyar.
    Yalnız şu JSON'u döndür, başka metin yazma:
    {"puan": 0-100, "kalip_uyumu": true/false, "celdirici": "...", "kok_dili": "...", "uzunluk": "...", \
    "ikinci_cevap": "savunulabilir ikinci şık ve nedeni" ya da null, "oneriler": ["..."], \
    "duzeltilmis": {"kok": "...", "secenekler": ["A", "B", "C", "D", "E"], "dogru": 0-4}}
    """

    static func editorIstemi(kok: String, secenekler: [String], dogru: Int, kalip: KalipTipi, kazanim: Kazanim?, klinik: Bool) -> String {
        let harfler = ["A", "B", "C", "D", "E"]
        var s = "Kalıp: \(kalip.ad) (\(kalip.rawValue))\n"
        if let kazanim { s += "Kazanım: \(kazanim.metin)\n" }
        s += "Kök:\n\(kok)\nŞıklar:\n"
        s += secenekler.enumerated().map { "\(harfler[min($0.offset, 4)])) \($0.element)" }.joined(separator: "\n")
        s += "\nDoğru şık: \(harfler[min(max(dogru, 0), 4)])"
        let veri: [String: Any] = ["gorev": "degerlendir", "kok": kok, "secenekler": secenekler, "dogru": dogru,
                                   "kalip": kalip.rawValue, "klinik": klinik]
        return s + "\n\n" + veriBlogu(veri)
    }

    // MARK: - Kitap sayfası

    static let eslemeSistemi = "Yalnız JSON nesnesi döndür; başka metin yazma."

    static func eslemeIstemi(ocr: String, levhalar: [(id: String, baslik: String)]) -> String {
        var s = "Aşağıdaki kitap sayfası metnine en uygun 3 levha id'sini JSON olarak döndür: {\"idler\": [\"id1\", \"id2\", \"id3\"]}.\n\nLevhalar:\n"
        s += levhalar.map { "- \($0.id): \($0.baslik)" }.joined(separator: "\n")
        s += "\n\nSayfa metni:\n\(ocr.prefix(4000))"
        let veri: [String: Any] = ["gorev": "esleme", "levhalar": levhalar.map { ["id": $0.id, "baslik": $0.baslik] }]
        return s + "\n\n" + veriBlogu(veri)
    }

    // MARK: - Yardımcılar

    static func veriBlogu(_ veri: [String: Any]) -> String {
        let json = (try? JSONSerialization.data(withJSONObject: veri, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return "<veri>\n\(json)\n</veri>"
    }

    nonisolated static func veriBlogu(_ istem: String) -> [String: Any]? {
        guard let bas = istem.range(of: "<veri>"), let son = istem.range(of: "</veri>", range: bas.upperBound..<istem.endIndex) else { return nil }
        let json = istem[bas.upperBound..<son.lowerBound]
        return (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]
    }

    /// Sistem istemindeki "Ad: değer" satırı.
    nonisolated static func alan(_ ad: String, _ metin: String) -> String? {
        for satir in metin.split(separator: "\n") where satir.hasPrefix("\(ad): ") {
            return String(satir.dropFirst(ad.count + 2))
        }
        return nil
    }

    /// Model JSON'u kod bloğuna sararsa ```json … ``` çitlerini atar.
    nonisolated static func jsonAyikla(_ veri: Data) -> Data {
        guard var metin = String(data: veri, encoding: .utf8) else { return veri }
        metin = metin.trimmingCharacters(in: .whitespacesAndNewlines)
        if metin.hasPrefix("```") {
            metin = metin.split(separator: "\n", omittingEmptySubsequences: false).dropFirst().joined(separator: "\n")
            if let r = metin.range(of: "```", options: .backwards) { metin = String(metin[..<r.lowerBound]) }
        }
        return Data(metin.utf8)
    }
}
