import Foundation
import SwiftData

/// "Bu levhayı genişlet": modelden taslak üretir, şemayla doğrular, İçerik › Taslaklar'a yazar; "Levhaya ekle" uygular.
@MainActor
enum TaslakServisi {
    static func genisletilebilir(_ levha: Levha) -> Bool { levha.levhaTipi?.izgaraTabanli ?? false }

    static func bosKonumlar(_ levha: Levha) -> [[Int]] {
        LevhaGenisletme.bosKonumlar(izgara: levha.izgara, dolu: levha.dugumler.map(\.konum))
    }

    /// Modelden taslak ister; geçerli ya da geçersiz, sonuç her durumda `Taslak` olarak kaydedilir.
    static func uret(levha: Levha, seciliDugum: String?, cevap: String?, _ context: ModelContext) async throws -> Taslak {
        let bos = bosKonumlar(levha)
        let istem = IstemSablonlari.genisletIstemi(levha: levha, bosKonumlar: bos, seciliDugum: seciliDugum, cevap: cevap)
        let veri = IstemSablonlari.jsonAyikla(try await LLMAyarlari.istemci.jsonUret(sistem: IstemSablonlari.genisletSistemi, istem: istem))
        let ham = String(data: veri, encoding: .utf8) ?? ""
        let taslak: Taslak
        do {
            let ek = try JSONDecoder().decode(GenisletmeJSON.self, from: veri)
            let hatalar = dogrula(levha, ek)
            let duzenli = JSONEncoder()
            duzenli.outputFormatting = [.sortedKeys]
            taslak = Taslak(levhaId: levha.id, tarih: .now, ham: ham, json: hatalar.isEmpty ? try duzenli.encode(ek) : nil, hatalar: hatalar)
        } catch {
            taslak = Taslak(levhaId: levha.id, tarih: .now, ham: ham, json: nil, hatalar: ["şemaya uymuyor: \(error.localizedDescription)"])
        }
        context.insert(taslak)
        try? context.save()
        return taslak
    }

    static func dogrula(_ levha: Levha, _ ek: GenisletmeJSON) -> [String] {
        guard let lj = levha.izgaraJSON else { return ["\(levha.tipAdi) levhası genişletilemez"] }
        return LevhaGenisletme.dogrula(lj, ek: ek, bosKonumlar: bosKonumlar(levha)).hatalar
    }

    /// Taslağı levhaya ekler (yerel düğüm/bağlantı, ızgara gerekirse büyür, yerelRevizyon +1).
    /// Aradan geçen sürede konum dolduysa yeniden doğrulanır; hata dönerse taslak değişmez.
    @discardableResult
    static func uygula(_ taslak: Taslak, _ context: ModelContext) -> [String] {
        let lid = taslak.levhaId
        guard let levha = try? context.fetch(FetchDescriptor<Levha>(predicate: #Predicate { $0.id == lid })).first else {
            return ["levha bulunamadı"]
        }
        guard let ek = taslak.genisletme else { return ["taslak geçersiz"] }
        let hatalar = dogrula(levha, ek)
        guard hatalar.isEmpty else { return hatalar }

        var sira = (levha.dugumler.map(\.sira).max() ?? -1) + 1
        var izgara = levha.izgara
        for d in ek.dugumler {
            let konum = d.konum ?? []
            let dugum = Dugum(id: d.id, etiket: d.etiket, sekil: (d.sekil ?? .durum).rawValue, renk: (d.renk ?? .gri).rawValue,
                              konum: konum, tus: d.tus ?? false, not: d.not ?? "", deger: nil, sira: sira)
            dugum.yerel = true
            context.insert(dugum)
            dugum.levha = levha
            sira += 1
            if konum.count == 2, izgara.count == 2 {
                izgara[0] = max(izgara[0], konum[0] + 1)
                izgara[1] = max(izgara[1], konum[1] + 1)
            }
        }
        var bsira = (levha.baglantilar.map(\.sira).max() ?? -1) + 1
        for b in ek.baglantilar ?? [] {
            let bag = Baglanti(from: b.from, to: b.to, etiket: b.etiket ?? "", tip: b.tip?.rawValue, sira: bsira)
            bag.yerel = true
            context.insert(bag)
            bag.levha = levha
            bsira += 1
        }
        levha.izgara = izgara
        levha.yerelRevizyon = (levha.yerelRevizyon ?? 0) + 1
        taslak.eklendi = true
        try? context.save()
        return []
    }
}
