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

    init(soruGlobalId: String, levhaId: String, secilen: Int, dogruMu: Bool, sureSaniye: Double, tarih: Date) {
        self.soruGlobalId = soruGlobalId
        self.levhaId = levhaId
        self.secilen = secilen
        self.dogruMu = dogruMu
        self.sureSaniye = sureSaniye
        self.tarih = tarih
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
    ]

    /// Disk deposu açılamadıysa dolu; İçerik ekranında kırmızı uyarı olarak görünür.
    private(set) static var hata: String?

    /// iCloud entitlement'ı varken SwiftData kendiliğinden CloudKit senkronu açmaya çalışır
    /// (unique kısıtlarıyla uyumsuz). Senkron yok: depo yerel, paketler iCloud Drive'dan gelir.
    static let container: ModelContainer = {
        let sema = Schema(modeller)
        do {
            return try ModelContainer(for: sema, configurations: ModelConfiguration(schema: sema, cloudKitDatabase: .none))
        } catch {
            hata = "Depo açılamadı, kayıtlar bu oturumla sınırlı: \(error.localizedDescription)"
            let gecici = ModelConfiguration(schema: sema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return try! ModelContainer(for: sema, configurations: gecici)
        }
    }()
}
