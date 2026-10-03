import Foundation
import SwiftData

/// iCloud Drive › Levha › Paketler (uygulama container'ı). iCloud yoksa
/// "Bu iPhone'da › Levha › Paketler" klasörüne düşer (Files'ta görünür).
@MainActor
final class PaketKlasoru: ObservableObject {
    struct Ozet {
        var paketId: String
        var altKonu: String
        var levha: Int
        var soru: Int
        /// Levhasız sorular (soru paketi).
        var bagimsiz: Int
        var anlatimKelime: Int?
        var uyarilar: [LintBulgusu]
    }

    enum Durum {
        case gecerli(Ozet)
        case hatali([LintBulgusu])
        case indiriliyor
    }

    struct Dosya: Identifiable {
        let url: URL
        let durum: Durum
        /// `tur: "soru_paketi"` (hatalı dosyada da JSON'dan okunur).
        var soruPaketi = false
        var id: String { url.lastPathComponent }
        var ad: String { url.lastPathComponent }
    }

    @Published private(set) var kok: URL?
    @Published private(set) var iCloud = false
    @Published private(set) var dosyalar: [Dosya] = []

    var konumAdi: String {
        guard kok != nil else { return "Hazırlanıyor…" }
        return iCloud ? "iCloud Drive › Levha › Paketler" : "Bu iPhone'da › Levha › Paketler"
    }

    func hazirla() async {
        guard kok == nil else { return }
        // url(forUbiquityContainerIdentifier:) ana iş parçacığını bloklayabilir.
        let (url, bulut) = await Task.detached(priority: .userInitiated) { () -> (URL, Bool) in
            if let kap = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
                return (kap.appending(path: "Documents/Paketler", directoryHint: .isDirectory), true)
            }
            return (URL.documentsDirectory.appending(path: "Paketler", directoryHint: .isDirectory), false)
        }.value
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        kok = url
        iCloud = bulut
        tara()
    }

    func tara() {
        guard let kok else { return }
        let fm = FileManager.default
        let icerik = (try? fm.contentsOfDirectory(at: kok, includingPropertiesForKeys: nil)) ?? []
        var sonuc: [Dosya] = []
        for url in icerik {
            let ad = url.lastPathComponent
            if ad.hasPrefix("."), ad.hasSuffix(".json.icloud") {
                // iCloud'da olup cihaza inmemiş dosya: indirmeyi başlat.
                let gercek = kok.appending(path: String(ad.dropFirst().dropLast(".icloud".count)))
                try? fm.startDownloadingUbiquitousItem(at: gercek)
                sonuc.append(Dosya(url: gercek, durum: .indiriliyor))
            } else if url.pathExtension.lowercased() == "json" {
                let veri = Self.oku(url)
                sonuc.append(Dosya(url: url, durum: Self.incele(veri), soruPaketi: veri.map(Self.soruPaketiMi) ?? false))
            }
        }
        dosyalar = sonuc.sorted { $0.ad.localizedStandardCompare($1.ad) == .orderedAscending }
    }

    static func oku(_ url: URL) -> Data? {
        var veri: Data?
        var hata: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &hata) { u in
            veri = try? Data(contentsOf: u)
        }
        return veri
    }

    static func incele(_ veri: Data?) -> Durum {
        guard let veri else { return .hatali([LintBulgusu("", "dosya okunamadı")]) }
        let s = LevhaLint.denetle(veri: veri)
        guard let p = s.paket, !s.engelleyiciVar else {
            return .hatali(s.bulgular.filter(\.engelleyici) + s.bulgular.filter { !$0.engelleyici })
        }
        let sorular = p.sorular ?? []
        return .gecerli(Ozet(paketId: p.paket_id, altKonu: p.alt_konu, levha: p.levhalar.count, soru: sorular.count,
                             bagimsiz: p.soruPaketiMi ? sorular.filter { ($0.levha ?? "").isEmpty }.count : 0,
                             anlatimKelime: p.anlatim.map(AnlatimMetni.kelimeSayisi), uyarilar: s.bulgular))
    }

    /// JSON'un kökünde `"tur": "soru_paketi"` var mı (şema hatalı olsa da).
    static func soruPaketiMi(_ veri: Data) -> Bool {
        ((try? JSONSerialization.jsonObject(with: veri)) as? [String: Any])?["tur"] as? String == PaketJSON.soruPaketiTuru
    }

    /// Elle seçilen dosyayı klasöre kopyalar; böylece listede kalıcı olarak görünür.
    @discardableResult
    func yaz(_ veri: Data, ad: String) throws -> URL {
        guard let kok else { throw CocoaError(.fileNoSuchFile) }
        let hedef = kok.appending(path: ad)
        var hata: NSError?
        var yazmaHatasi: Error?
        NSFileCoordinator().coordinate(writingItemAt: hedef, options: .forReplacing, error: &hata) { u in
            do { try veri.write(to: u, options: .atomic) } catch { yazmaHatasi = error }
        }
        if let e = hata ?? yazmaHatasi { throw e }
        return hedef
    }
}

/// Uygulamayla gelen örnek paketleri klasöre koyar ve içe aktarır. Her dosyanın içerik özeti
/// saklanır: yeni eklenen ya da yeni sürümle değişen örnek paket bir kez daha yüklenir.
@MainActor
enum Baslangic {
    static let anahtar = "yuklenenOrnekler"

    static func calistir(klasor: PaketKlasoru, context: ModelContext) async {
        await klasor.hazirla()
        var yuklenen = UserDefaults.standard.dictionary(forKey: anahtar) as? [String: String] ?? [:]
        var degisti = false
        let urller = (Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for url in urller {
            guard let veri = try? Data(contentsOf: url) else { continue }
            let ad = url.lastPathComponent
            let ozet = ozet(veri)
            guard yuklenen[ad] != ozet || depodaEski(veri, context) else { continue }
            _ = try? klasor.yaz(veri, ad: ad)
            _ = PaketIceAktarici.iceAktar(veri: veri, dosyaAdi: ad, context: context)
            yuklenen[ad] = ozet
            degisti = true
        }
        if degisti {
            UserDefaults.standard.set(yuklenen, forKey: anahtar)
            klasor.tara()
        }
    }

    /// Part 5 öncesi içe aktarılmış soruların önbellek alanları (ders, kalıp, sorulabilirlik) bir kez doldurulur.
    static func soruAlanlariniDoldur(_ context: ModelContext) {
        let eksik = ((try? context.fetch(FetchDescriptor<Soru>(predicate: #Predicate { $0.konuDers == nil }))) ?? [])
        guard !eksik.isEmpty else { return }
        for s in eksik {
            let konu = s.konuPaketi
            let k = s.kazanim.flatMap { kid in konu?.kazanimlar.first { $0.id == kid } }
            s.cozumle(ders: konu?.ders, kazanimKalibi: k?.kalip, kazanimSorulabilirligi: k?.sorulabilirlik)
        }
        try? context.save()
    }

    /// Paket depoda yoksa ya da depodaki şema sürümü dosyadakinden eskiyse (ör. depo yeni yere taşındı) true.
    private static func depodaEski(_ veri: Data, _ context: ModelContext) -> Bool {
        guard let p = try? JSONDecoder().decode(PaketJSON.self, from: veri) else { return false }
        let pid = p.paket_id
        guard let mevcut = try? context.fetch(FetchDescriptor<Paket>(predicate: #Predicate { $0.paket_id == pid })).first else { return true }
        return mevcut.sema_surumu < p.sema_surumu
    }

    private static func ozet(_ veri: Data) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for bayt in veri {
            h ^= UInt64(bayt)
            h = h &* 0x100000001b3
        }
        return String(h, radix: 16)
    }
}
