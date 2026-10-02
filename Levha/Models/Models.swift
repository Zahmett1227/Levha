import Foundation
import SwiftData

// SwiftData modelleri. JSON'dan gelen alanlar JSON'daki adlarıyla tutulur;
// yalnız uygulamaya ait alanlar (duzenImzasi, sonCalisma, sira...) camelCase.
// Relationship dizileri sırasızdır; sıralama `sira` alanıyla yapılır.

@Model
final class Paket {
    @Attribute(.unique) var paket_id: String
    var sema_surumu: Int
    var ders: String
    var bolum: String
    var alt_konu: String
    var dosyaAdi: String
    var iceAktarilma: Date
    @Relationship(deleteRule: .cascade, inverse: \Levha.paket) var levhalar: [Levha] = []
    @Relationship(deleteRule: .cascade, inverse: \Soru.paket) var sorular: [Soru] = []
    @Relationship(deleteRule: .cascade, inverse: \Kazanim.paket) var kazanimlar: [Kazanim] = []
    @Relationship(deleteRule: .cascade, inverse: \Aile.paket) var aileler: [Aile] = []

    init(paket_id: String) {
        self.paket_id = paket_id
        sema_surumu = 1
        ders = ""
        bolum = ""
        alt_konu = ""
        dosyaAdi = ""
        iceAktarilma = .now
    }

    var siraliLevhalar: [Levha] { levhalar.sorted { $0.sira < $1.sira } }
    var sonCalisma: Date? { levhalar.compactMap(\.sonCalisma).max() }

    /// Levhanın kazanımları: düğümleri levhada olanlar + levhanın sorularının kazanımları.
    func kazanimlar(_ levha: Levha) -> [Kazanim] {
        let idler = Set(levha.dugumler.map(\.id))
        let sorudan = Set(sorular.filter { $0.levha == levha.id }.compactMap(\.kazanim))
        return kazanimlar.filter { k in sorudan.contains(k.id) || k.dugumler.contains(where: idler.contains) }
    }
}

@Model
final class Kazanim {
    var id: String
    var metin: String
    var kalip: String
    var dugumler: [String]
    var sorulabilirlik: Int
    var aile: String?
    var anahtar_ipucu: String?
    var sira: Int
    var paket: Paket?

    init(_ j: KazanimJSON, sira: Int) {
        id = j.id
        metin = j.metin
        kalip = j.kalip
        dugumler = j.dugumler ?? []
        sorulabilirlik = j.sorulabilirlik
        aile = j.aile
        anahtar_ipucu = j.anahtar_ipucu
        self.sira = sira
    }

    var kalipTipi: KalipTipi? { KalipTipi(rawValue: kalip) }
}

@Model
final class Aile {
    var id: String
    var ad: String
    var uyeler: [String]
    /// "A|B" → ipucu, JSON.
    var ayirici: Data?
    var sira: Int
    var paket: Paket?

    init(_ j: AileJSON, sira: Int) {
        id = j.id
        ad = j.ad
        uyeler = j.uyeler
        ayirici = try? JSONEncoder().encode(j.ayirici ?? [:])
        self.sira = sira
    }

    func ayiriciIpucu(_ a: String, _ b: String) -> String? {
        let sozluk = ayirici.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        return sozluk["\(a)|\(b)"] ?? sozluk["\(b)|\(a)"]
    }
}

@Model
final class Levha {
    @Attribute(.unique) var id: String
    var tip: String
    var baslik: String
    var akilda_kalan: String
    var sira: Int
    /// [sütun, satır]
    var izgara: [Int]
    /// Konumların hash'i. Aynı id tekrar içe aktarılınca eski düzen korunur.
    var duzenImzasi: String
    var ortme_sirasi: [String]
    var satirlar: [String]
    var sutunlar: [String]
    var eksenMin: Double
    var eksenMax: Double
    var eksenBirim: String
    /// Zaman çizelgesi şeritleri (sıralı).
    var seritIdleri: [String]?
    var seritAdlari: [String]?
    /// Yazılmış sabotajlar, `[SabotajJSON]` olarak JSON.
    var sabotajlar: Data?
    /// İnşa'da boş bırakılacak düğümler (yoksa ortme_sirasi).
    var insa_sirasi: [String]?
    /// `KaynakJSON` (Part 4'te kullanılacak).
    var kaynak: Data?
    /// Levhanın içe aktarılan ham JSON'u (Part 2 tiplerinin ek alanları dahil).
    var hamJSON: Data
    var sonCalisma: Date?
    var paket: Paket?
    @Relationship(deleteRule: .cascade, inverse: \Dugum.levha) var dugumler: [Dugum] = []
    @Relationship(deleteRule: .cascade, inverse: \Baglanti.levha) var baglantilar: [Baglanti] = []

    init(id: String) {
        self.id = id
        tip = LevhaTipi.algoritma.rawValue
        baslik = ""
        akilda_kalan = ""
        sira = 0
        izgara = [3, 4]
        duzenImzasi = ""
        ortme_sirasi = []
        satirlar = []
        sutunlar = []
        eksenMin = 0
        eksenMax = 1
        eksenBirim = ""
        hamJSON = Data()
    }

    var levhaTipi: LevhaTipi? { LevhaTipi(rawValue: tip) }
    var tipAdi: String { levhaTipi?.ad ?? tip }
    var siraliDugumler: [Dugum] { dugumler.sorted { $0.sira < $1.sira } }
    var siraliBaglantilar: [Baglanti] { baglantilar.sorted { $0.sira < $1.sira } }
    var yazilmisSabotajlar: [SabotajJSON] {
        sabotajlar.flatMap { try? JSONDecoder().decode([SabotajJSON].self, from: $0) } ?? []
    }
}

@Model
final class Dugum {
    /// Levha içinde tekil. Matris hücreleri `r{satır}c{sütun}`.
    var id: String
    var etiket: String
    var sekil: String
    var renk: String
    /// [sütun, satır]; sayı cetveli işaretlerinde boş.
    var konum: [Int]
    var tus: Bool
    var not: String
    /// Sayı cetveli işaret değeri (nil ise "sabit sayı yok"); zaman çizelgesinde olayın başlangıcı.
    var deger: Double?
    /// Zaman çizelgesi: aralığın sonu (nil → nokta), şerit id'si.
    var bit: Double?
    var serit: String?
    /// Vücut haritası bölgesi (`VucutBolgesi` ham değeri).
    var bolge: String?
    var sira: Int
    var levha: Levha?

    init(id: String, etiket: String, sekil: String, renk: String, konum: [Int], tus: Bool, not: String, deger: Double?, sira: Int) {
        self.id = id
        self.etiket = etiket
        self.sekil = sekil
        self.renk = renk
        self.konum = konum
        self.tus = tus
        self.not = not
        self.deger = deger
        self.sira = sira
    }
}

@Model
final class Baglanti {
    var from: String
    var to: String
    var etiket: String
    /// `BaglantiTipi` ham değeri; nil → normal.
    var tip: String?
    var sira: Int
    var levha: Levha?

    init(from: String, to: String, etiket: String, tip: String?, sira: Int) {
        self.from = from
        self.to = to
        self.etiket = etiket
        self.tip = tip
        self.sira = sira
    }
}

@Model
final class Soru {
    var id: String
    /// paket_id + "." + id — paketler arası tekil.
    var globalId: String?
    /// Sorunun bağlı olduğu levhanın id'si.
    var levha: String
    var dugumler: [String]
    var kok: String
    var secenekler: [String]
    var dogru: Int
    var aciklama: String
    var aciklama_yolu: [String]
    /// {"seçenek indeksi": "düğüm id"} — JSON olarak.
    var celdirici_dugum: Data?
    var sira: Int
    var paket: Paket?
    // v3
    var kazanim: String?
    var kalip: String?
    var zorluk: Int?
    /// {"şık": "aile üyesi"} — JSON.
    var secenek_aile: Data?

    init(_ j: SoruJSON, paketId: String, sira: Int) {
        id = j.id
        globalId = "\(paketId).\(j.id)"
        levha = j.levha
        dugumler = j.dugumler ?? []
        kok = j.kok
        secenekler = j.secenekler
        dogru = j.dogru
        aciklama = j.aciklama
        aciklama_yolu = j.aciklama_yolu ?? []
        celdirici_dugum = try? JSONEncoder().encode(j.celdirici_dugum ?? [:])
        self.sira = sira
        kazanim = j.kazanim
        kalip = j.kalip
        zorluk = j.zorluk
        secenek_aile = j.secenek_aile.flatMap { try? JSONEncoder().encode($0) }
    }

    /// Kazanımın sorulabilirliği (1–5); kazanımı yoksa nil.
    var sorulabilirlik: Int? {
        guard let kid = kazanim else { return nil }
        return paket?.kazanimlar.first { $0.id == kid }?.sorulabilirlik
    }

    var secenekAileleri: [Int: String] {
        let ham = secenek_aile.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        return Dictionary(uniqueKeysWithValues: ham.compactMap { k, v in Int(k).map { ($0, v) } })
    }

    var kimlik: String { globalId ?? "\(paket?.paket_id ?? "").\(id)" }
    var celdiriciler: [Int: String] {
        let ham = celdirici_dugum.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        return Dictionary(uniqueKeysWithValues: ham.compactMap { k, v in Int(k).map { ($0, v) } })
    }
}

/// Örtme modunda her gizlenen düğüm için bir kayıt.
@Model
final class OrtmeOlayi {
    var levhaId: String
    var dugumId: String
    var tarih: Date
    var bildim: Bool

    init(levhaId: String, dugumId: String, tarih: Date, bildim: Bool) {
        self.levhaId = levhaId
        self.dugumId = dugumId
        self.tarih = tarih
        self.bildim = bildim
    }
}

@Model
final class SabotajOlayi {
    var levhaId: String
    var sabotajTipi: String
    var bulundu: Bool
    var denemeSayisi: Int
    var tarih: Date

    init(levhaId: String, sabotajTipi: String, bulundu: Bool, denemeSayisi: Int, tarih: Date) {
        self.levhaId = levhaId
        self.sabotajTipi = sabotajTipi
        self.bulundu = bulundu
        self.denemeSayisi = denemeSayisi
        self.tarih = tarih
    }
}

@Model
final class SoruOlayi {
    var soruGlobalId: String
    var levhaId: String
    var secilen: Int
    var dogruMu: Bool
    var sureSaniye: Double
    var tarih: Date
    /// 1 Eminim · 2 Sanırım · 3 Tahmin (Part 2 kayıtlarında boş).
    var guven: Int?

    init(soruGlobalId: String, levhaId: String, secilen: Int, dogruMu: Bool, sureSaniye: Double, tarih: Date, guven: Int) {
        self.soruGlobalId = soruGlobalId
        self.levhaId = levhaId
        self.secilen = secilen
        self.dogruMu = dogruMu
        self.sureSaniye = sureSaniye
        self.tarih = tarih
        self.guven = guven
    }
}

@Model
final class InsaOlayi {
    var levhaId: String
    var hataSayisi: Int
    /// Boş bırakılan düğüm sayısı.
    var toplam: Int
    var sureSaniye: Double
    var tarih: Date

    init(levhaId: String, hataSayisi: Int, toplam: Int, sureSaniye: Double, tarih: Date) {
        self.levhaId = levhaId
        self.hataSayisi = hataSayisi
        self.toplam = toplam
        self.sureSaniye = sureSaniye
        self.tarih = tarih
    }

    /// İlk denemede doğru yerleştirilen oranı (0–1).
    var oran: Double { toplam > 0 ? Double(max(0, toplam - hataSayisi)) / Double(toplam) : 0 }
}

/// Uygulamanın ön planda geçirdiği süre (günlük).
@Model
final class KullanimKaydi {
    @Attribute(.unique) var gun: String
    var saniye: Double

    init(gun: String, saniye: Double) {
        self.gun = gun
        self.saniye = saniye
    }
}

/// Soru yanlışlarının düğüm başına sayacı; Örtme maske sırasını belirler.
@Model
final class DugumZayiflik {
    var levhaId: String
    var dugumId: String
    var sayac: Int

    init(levhaId: String, dugumId: String, sayac: Int) {
        self.levhaId = levhaId
        self.dugumId = dugumId
        self.sayac = sayac
    }
}

/// Zamanlayıcı durumunun kalıcı karşılığı (`ZamanDurumu`).
@Model
final class LevhaDurumu {
    @Attribute(.unique) var levhaId: String
    var kutu: Int
    var sonrakiTarih: Date?
    var saglamlik: Double
    var sonGorulme: Date?

    init(levhaId: String) {
        self.levhaId = levhaId
        kutu = 0
        saglamlik = 0
    }

    var deger: ZamanDurumu {
        get { ZamanDurumu(levhaId: levhaId, kutu: kutu, sonrakiTarih: sonrakiTarih, saglamlik: saglamlik, sonGorulme: sonGorulme) }
        set {
            kutu = newValue.kutu
            sonrakiTarih = newValue.sonrakiTarih
            saglamlik = newValue.saglamlik
            sonGorulme = newValue.sonGorulme
        }
    }
}

/// Günlük turun o güne ait kaydı (gün 04:00'te döner).
@Model
final class TurDurumu {
    @Attribute(.unique) var gun: String
    var calismaYeri: String
    var altKonuPaketId: String?
    var kisa: Bool
    var tamamlananlar: [String]
    /// `TurKuyrugu` JSON'u.
    var kuyruk: Data?

    init(gun: String, calismaYeri: String) {
        self.gun = gun
        self.calismaYeri = calismaYeri
        kisa = false
        tamamlananlar = []
    }
}

enum Depo {
    static let modeller: [any PersistentModel.Type] = [
        Paket.self, Levha.self, Dugum.self, Baglanti.self, Soru.self, OrtmeOlayi.self,
        SabotajOlayi.self, SoruOlayi.self, DugumZayiflik.self, LevhaDurumu.self, TurDurumu.self,
        Kazanim.self, Aile.self, InsaOlayi.self, KullanimKaydi.self,
    ]

    /// Depo App Group container'ında durur (widget ve Part 4+ eklentileri erişebilsin). App Group yoksa
    /// (ör. ücretsiz geliştirici hesabı) uygulama container'ında kalır. Part 1–2'den kalan depo ilk açılışta
    /// grup container'ına kopyalanır; eski dosya silinmez.
    static func depoURL() -> URL {
        let fm = FileManager.default
        let eski = URL.applicationSupportDirectory.appending(path: "default.store")
        guard let grup = fm.containerURL(forSecurityApplicationGroupIdentifier: WidgetDeposu.grup) else { return eski }
        let klasor = grup.appending(path: "Library/Application Support", directoryHint: .isDirectory)
        let yeni = klasor.appending(path: "default.store")
        if !fm.fileExists(atPath: yeni.path), fm.fileExists(atPath: eski.path) {
            try? fm.createDirectory(at: klasor, withIntermediateDirectories: true)
            for ek in ["", "-wal", "-shm"] {
                let kaynak = URL(fileURLWithPath: eski.path + ek)
                if fm.fileExists(atPath: kaynak.path) { try? fm.copyItem(at: kaynak, to: URL(fileURLWithPath: yeni.path + ek)) }
            }
        }
        return yeni
    }

    /// Disk deposu açılamadıysa dolu; İçerik ekranında kırmızı uyarı olarak görünür.
    private(set) static var hata: String?

    /// iCloud entitlement'ı varken SwiftData kendiliğinden CloudKit senkronu açmaya çalışır
    /// (unique kısıtlarıyla uyumsuz). Senkron yok: depo yerel, paketler iCloud Drive'dan gelir.
    static let container: ModelContainer = {
        let sema = Schema(modeller)
        do {
            let ayar = ModelConfiguration(schema: sema, url: depoURL(), cloudKitDatabase: .none)
            return try ModelContainer(for: sema, configurations: ayar)
        } catch {
            hata = "Depo açılamadı, kayıtlar bu oturumla sınırlı: \(error.localizedDescription)"
            let gecici = ModelConfiguration(schema: sema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return try! ModelContainer(for: sema, configurations: gecici)
        }
    }()
}
