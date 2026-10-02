import XCTest
@testable import LevhaCekirdek

final class IpucuPuaniTests: XCTestCase {
    // Kök sırasında ağırlıklar: 3, 2, 0 (yanıltıcı), 1 → toplam 6.
    let w = [3, 2, 0, 1]

    func testErkenBilenYuksekAlir() {
        XCTAssertEqual(IpucuPuani.temel(agirliklar: w, acilan: 1, dogru: true), 50)   // kalan 2+0+1 = 3/6
        XCTAssertEqual(IpucuPuani.temel(agirliklar: w, acilan: 2, dogru: true), 17)   // kalan 1/6
        XCTAssertEqual(IpucuPuani.temel(agirliklar: w, acilan: 3, dogru: true), 17)   // yanıltıcı açmak puan düşürmez
        XCTAssertEqual(IpucuPuani.temel(agirliklar: w, acilan: 4, dogru: true), 0)    // hepsi açık
        XCTAssertEqual(IpucuPuani.temel(agirliklar: w, acilan: 0, dogru: true), 100)
    }

    func testYanlisEksi25() {
        XCTAssertEqual(IpucuPuani.temel(agirliklar: w, acilan: 1, dogru: false), -25)
        XCTAssertEqual(IpucuPuani.temel(agirliklar: w, acilan: 4, dogru: false), -25)
    }

    func testYanilticiIsaretleme() {
        XCTAssertEqual(IpucuPuani.yanilticiPuani(isaretlenen: [2], yanilticilar: [2]), 10)
        XCTAssertEqual(IpucuPuani.yanilticiPuani(isaretlenen: [0], yanilticilar: [2]), -10)
        XCTAssertEqual(IpucuPuani.yanilticiPuani(isaretlenen: [0, 2], yanilticilar: [2]), 0)
        XCTAssertEqual(IpucuPuani.toplam(agirliklar: w, acilan: 1, dogru: true, isaretlenen: [2], yanilticilar: [2]), 60)
        XCTAssertEqual(IpucuPuani.toplam(agirliklar: w, acilan: 1, dogru: false, isaretlenen: [1], yanilticilar: [2]), -35)
    }

    func testAgirliksizIpuclarindaKartSayisi() {
        XCTAssertEqual(IpucuPuani.temel(agirliklar: [0, 0, 0, 0], acilan: 1, dogru: true), 75)
        XCTAssertEqual(IpucuPuani.temel(agirliklar: [], acilan: 0, dogru: true), 0)
        XCTAssertEqual(IpucuPuani.temel(agirliklar: w, acilan: 9, dogru: true), 0, "taşan indeks sıkıştırılır")
    }

    func testKokSirasiVeSoruCumlesi() {
        let kok = "Doğumdan 12 saat sonra sarılık fark edilen, annesi O Rh(+) olan term bebekte ilk istenmesi gereken tetkik aşağıdakilerden hangisidir?"
        XCTAssertEqual(IpucuPuani.kokSirasi(kok: kok, metinler: ["annesi O Rh(+)", "Doğumdan 12 saat sonra", "yok"]), [1, 0, 2])
        XCTAssertEqual(IpucuPuani.soruCumlesi("Bebek sarı. Kan grubu A. En olası tanı aşağıdakilerden hangisidir?"),
                       "En olası tanı aşağıdakilerden hangisidir?")
    }
}

final class SayfaEslemeTests: XCTestCase {
    let adaylar = [
        EslemeAdayi(id: "kvs", anahtarKelimeler: ["siyanoz", "Fallot", "transpozisyon", "trunkus"],
                    baslik: "Siyanotik KKH sınıflaması", etiketler: ["Fallot tetralojisi", "Trikuspit atrezisi", "TAPVD"]),
        EslemeAdayi(id: "sarilik", anahtarKelimeler: ["sarılık", "bilirubin", "fototerapi", "Coombs"],
                    baslik: "Yenidoğan sarılığına yaklaşım", etiketler: ["İlk 24 saatte sarılık", "Direkt Coombs", "Fototerapi"]),
        EslemeAdayi(id: "gelisim", anahtarKelimeler: ["gelişim", "motor", "refleks", "Moro"],
                    baslik: "Gelişim basamakları", etiketler: ["Sosyal gülümseme", "Desteksiz oturma", "Moro refleksi"]),
    ]

    func testKelimeler() {
        XCTAssertEqual(SayfaEsleme.kelimeler("SARILIK, Bilirubin ve İnce-barsak 12 mg"), ["sarilik", "bilirubin", "ince", "barsak"])
        XCTAssertEqual(SayfaEsleme.kelimeler("sarılığı sarılık"), ["sariligi", "sarilik"], "ek kırpması yok")
        XCTAssertEqual(SayfaEsleme.kelimeler("ile için gibi Coombs"), ["coombs"], "durak kelimeler elenir")
    }

    func testSkorFormulu() {
        // anahtar 4 kelime ×3 = 12, başlık 3 ×2 = 6, etiket (ilk, saatte, sarilik, direkt, coombs, fototerapi) 6 ×1 → payda 24.
        let s = SayfaEsleme.skor(adaylar[1], sayfa: ["sarilik", "bilirubin", "yenidogan"])
        // anahtar: sarilik, bilirubin → 6; başlık: yenidogan → 2; etiket: sarilik → 1 → 9/24
        XCTAssertEqual(s, 9.0 / 24.0, accuracy: 1e-9)
        XCTAssertEqual(SayfaEsleme.skor(adaylar[1], sayfa: []), 0)
    }

    func testKitapSayfasiDogruLevhayiBulur() {
        let ocr = """
        YENİDOĞAN SARILIĞINA YAKLAŞIM
        Sarılık yenidoğanda sık görülür. İlk 24 saatte ortaya çıkan sarılık her zaman patolojiktir;
        direkt Coombs testi istenir. Bilirubin düzeyi saatlik nomograma göre değerlendirilir ve
        fototerapi kararı verilir. Kernikterus riskine dikkat.
        """
        let sonuc = SayfaEsleme.sirala(adaylar, ocr: ocr)
        XCTAssertEqual(sonuc.first?.id, "sarilik")
        XCTAssertGreaterThan(sonuc.first?.skor ?? 0, SayfaEsleme.esik)
        XCTAssertFalse(SayfaEsleme.eslesmeYok(sonuc))
        XCTAssertLessThanOrEqual(sonuc.count, 5)
    }

    func testEslesmeYok() {
        let sonuc = SayfaEsleme.sirala(adaylar, ocr: "Akut apandisitte McBurney noktasında hassasiyet olur; motor bulgu yok.")
        XCTAssertTrue(SayfaEsleme.eslesmeYok(sonuc))
    }
}
