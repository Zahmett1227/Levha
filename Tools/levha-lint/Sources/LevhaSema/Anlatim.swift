import Foundation

/// Konu anlatımı (v5): markdown metindeki `[[...]]` referansları, başlıklar ve kelime sayısı.
/// Referans biçimleri: `[[n2]]` (paketteki düğüm), `[[levha_id]]` (tam ya da paket içi kısa id),
/// `[[levha_id#n2]]` (belirli levhanın düğümü); `|` sonrası görünen metindir: `[[n2|ilk 24 saatte]]`.
public enum AnlatimMetni {
    public static let kelimeAraligi = 2000...6000

    public struct Referans: Equatable {
        /// Köşeli parantezlerin içi, olduğu gibi.
        public var ham: String
        /// `|` ve `#` öncesi: düğüm ya da levha kimliği.
        public var hedef: String
        /// `levha_id#düğüm` biçiminde düğüm.
        public var dugum: String?
        /// `|` sonrası görünen metin.
        public var metin: String?
        /// Metindeki konumu (`[[` dahil).
        public var aralik: Range<String.Index>
    }

    public enum Cozum: Equatable {
        case levha(String)
        case dugum(levha: String, dugum: String)
        /// Düğüm paketin birden çok levhasında var; ilk levha kullanılır.
        case belirsiz(levha: String, dugum: String, adaylar: [String])
        /// Başka pakete referans (tam levha id'si); içe aktarılmışsa uygulamada çözülür.
        case disPaket(String)
        case yok
    }

    private static let desen = try! NSRegularExpression(pattern: #"\[\[([^\[\]]+?)\]\]"#)

    public static func referanslar(_ metin: String) -> [Referans] {
        let ns = metin as NSString
        return desen.matches(in: metin, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            guard let tum = Range(m.range, in: metin), let ic = Range(m.range(at: 1), in: metin) else { return nil }
            let ham = String(metin[ic])
            let parca = ham.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            let yol = parca[0].split(separator: "#", maxSplits: 1).map(String.init)
            let gorunen = parca.count > 1 && !parca[1].isEmpty ? parca[1] : nil
            return Referans(ham: ham, hedef: yol.first ?? "", dugum: yol.count > 1 ? yol[1] : nil, metin: gorunen, aralik: tum)
        }
    }

    /// `[[...]]` → görünen metin ya da hedef (kelime sayımı ve düz metin için).
    public static func referanssiz(_ metin: String) -> String {
        var sonuc = metin
        for r in referanslar(metin).reversed() {
            sonuc.replaceSubrange(r.aralik, with: r.metin ?? r.dugum ?? r.hedef)
        }
        return sonuc
    }

    /// `#`, `##`, `###` satırlarının metni (vurgu işaretleri atılmış).
    public static func basliklar(_ metin: String) -> [(seviye: Int, metin: String)] {
        metin.split(separator: "\n", omittingEmptySubsequences: false).compactMap { satir in
            let s = satir.trimmingCharacters(in: .whitespaces)
            let diyez = s.prefix { $0 == "#" }.count
            guard (1...3).contains(diyez), s.dropFirst(diyez).first == " " else { return nil }
            return (diyez, sadeBaslik(String(s.dropFirst(diyez))))
        }
    }

    public static func sadeBaslik(_ s: String) -> String {
        referanssiz(s).replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "").trimmingCharacters(in: .whitespaces)
    }

    /// Başlık eşlemesi için anahtar: Türkçe küçük harf, aksan ve noktalama yok, tek boşluk.
    public static func baslikAnahtari(_ s: String) -> String {
        let kucuk = sadeBaslik(s).replacingOccurrences(of: "I", with: "ı").replacingOccurrences(of: "İ", with: "i")
            .lowercased(with: Locale(identifier: "tr_TR"))
        let katlanmis = kucuk.replacingOccurrences(of: "ı", with: "i")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "tr_TR"))
        let harfler = katlanmis.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(harfler).split(separator: " ").joined(separator: " ")
    }

    /// Markdown işaretleri ve referans sözdizimi dışında kalan kelimeler.
    public static func kelimeSayisi(_ metin: String) -> Int {
        referanssiz(metin).split(whereSeparator: { $0.isWhitespace }).filter { k in
            k.contains { $0.isLetter || $0.isNumber }
        }.count
    }

    /// Referansı paketin levhalarına göre çözer. `levhalar` paket sırasıyla (id, düğüm kimlikleri).
    public static func coz(_ r: Referans, paketId: String, levhalar: [(id: String, dugumler: Set<String>)]) -> Cozum {
        func levhaId(_ ad: String) -> String? {
            if levhalar.contains(where: { $0.id == ad }) { return ad }
            let tam = "\(paketId).\(ad)"
            return levhalar.contains(where: { $0.id == tam }) ? tam : nil
        }
        if let d = r.dugum {
            guard let lid = levhaId(r.hedef) else { return disMi(r.hedef, paketId) ? .disPaket(r.hedef) : .yok }
            return levhalar.first { $0.id == lid }?.dugumler.contains(d) == true ? .dugum(levha: lid, dugum: d) : .yok
        }
        if let lid = levhaId(r.hedef) { return .levha(lid) }
        let adaylar = levhalar.filter { $0.dugumler.contains(r.hedef) }.map(\.id)
        if adaylar.count == 1 { return .dugum(levha: adaylar[0], dugum: r.hedef) }
        if let ilk = adaylar.first { return .belirsiz(levha: ilk, dugum: r.hedef, adaylar: adaylar) }
        return disMi(r.hedef, paketId) ? .disPaket(r.hedef) : .yok
    }

    /// Noktalı ve bu paketin önekini taşımayan kimlik başka paketin levhası sayılır.
    private static func disMi(_ hedef: String, _ paketId: String) -> Bool {
        hedef.contains(".") && !hedef.hasPrefix("\(paketId).")
    }
}
