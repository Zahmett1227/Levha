import Foundation

/// Editör: modelden önce cihazda yapılan biçim denetimi.
public struct OnDenetimSatiri: Equatable, Identifiable {
    public var id: String { ad }
    public let ad: String
    public let gecti: Bool
    public let mesaj: String
}

public enum OnDenetim {
    public static let mutlakIfadeler = ["her zaman", "hiçbir zaman", "asla", "sadece", "daima", "kesinlikle"]
    public static let klinikKelime = 50...80
    public static let uzunlukFarki = 15

    static let tr = Locale(identifier: "tr_TR")

    public static func kelimeSayisi(_ metin: String) -> Int {
        metin.split(whereSeparator: { $0.isWhitespace }).count
    }

    /// `klinik`: kök bir vaka anlatıyor mu (50–80 kelime kuralı yalnız buna uygulanır).
    public static func denetle(kok: String, secenekler: [String], dogru: Int, klinik: Bool) -> [OnDenetimSatiri] {
        var s: [OnDenetimSatiri] = []
        let n = kelimeSayisi(kok)
        if klinik {
            s.append(.init(ad: "Kök uzunluğu", gecti: klinikKelime.contains(n),
                           mesaj: "\(n) kelime (klinik kökte \(klinikKelime.lowerBound)–\(klinikKelime.upperBound))"))
        } else {
            s.append(.init(ad: "Kök uzunluğu", gecti: n >= 5, mesaj: "\(n) kelime (bilgi sorusu)"))
        }

        let kucuk = kok.lowercased(with: tr)
        let soruKalibi: (Bool, String)
        if kucuk.contains("aşağıdakilerden hangisi") {
            soruKalibi = (true, "\"aşağıdakilerden hangisi…\" var")
        } else if kucuk.contains("hangisi") {
            soruKalibi = (false, "\"hangisidir?\" önünde \"aşağıdakilerden\" yok")
        } else {
            soruKalibi = (false, "soru cümlesi \"aşağıdakilerden hangisidir?\" kalıbında değil")
        }
        s.append(.init(ad: "Soru cümlesi", gecti: soruKalibi.0, mesaj: soruKalibi.1))

        let doluSik = secenekler.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let bosYok = doluSik.count == 5 && doluSik.allSatisfy { !$0.isEmpty }
        let tekil = Set(doluSik.map { $0.lowercased(with: tr) }).count == doluSik.count
        s.append(.init(ad: "Şıklar", gecti: bosYok && tekil,
                       mesaj: !bosYok ? "5 şıkkın hepsi dolu olmalı" : (tekil ? "5 farklı şık" : "aynı şık iki kez yazılmış")))

        if doluSik.indices.contains(dogru), doluSik.count > 1 {
            let dogruU = doluSik[dogru].count
            let enUzunDiger = doluSik.enumerated().filter { $0.offset != dogru }.map(\.element.count).max() ?? 0
            let fark = dogruU - enUzunDiger
            s.append(.init(ad: "Şık uzunluğu", gecti: fark < uzunlukFarki,
                           mesaj: fark >= uzunlukFarki ? "doğru şık en uzun çeldiriciden \(fark) karakter uzun" : "dengeli (fark \(max(0, fark)))"))
        }

        let tumMetin = ([kok] + doluSik).joined(separator: " \n ").lowercased(with: tr)
        let bulunan = mutlakIfadeler.filter { ifadeVar($0, tumMetin) }
        s.append(.init(ad: "Mutlak ifade", gecti: bulunan.isEmpty,
                       mesaj: bulunan.isEmpty ? "yok" : bulunan.map { "\"\($0)\"" }.joined(separator: ", ")))

        let noktali = tumMetin.range(of: #"\d\.\d"#, options: .regularExpression) != nil
        s.append(.init(ad: "Ondalık", gecti: !noktali, mesaj: noktali ? "ondalıkta nokta var; virgül kullan (2,5)" : "uygun"))
        return s
    }

    public static func temiz(_ satirlar: [OnDenetimSatiri]) -> Bool { satirlar.allSatisfy(\.gecti) }

    /// Kelime sınırıyla arar ("asla" "aslan"ı yakalamasın).
    static func ifadeVar(_ ifade: String, _ metin: String) -> Bool {
        var aralik = metin.startIndex..<metin.endIndex
        while let r = metin.range(of: ifade, range: aralik) {
            let onceHarf = r.lowerBound > metin.startIndex && metin[metin.index(before: r.lowerBound)].isLetter
            let sonraHarf = r.upperBound < metin.endIndex && metin[r.upperBound].isLetter
            if !onceHarf && !sonraHarf { return true }
            aralik = r.upperBound..<metin.endIndex
        }
        return false
    }
}
