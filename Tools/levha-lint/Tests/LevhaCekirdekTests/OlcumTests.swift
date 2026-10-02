import XCTest
@testable import LevhaCekirdek

final class OncelikTests: XCTestCase {
    private var takvim: Calendar = {
        var t = Calendar(identifier: .gregorian)
        t.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return t
    }()

    private func gun(_ g: Int, _ saat: Int = 0) -> Date {
        takvim.date(from: DateComponents(year: 2026, month: 10, day: g, hour: saat))!
    }

    func testDersAgirligiSinirlari() {
        XCTAssertEqual(Oncelik.dersAgirligi(soruSayisi: 30), 1.0)
        XCTAssertEqual(Oncelik.dersAgirligi(soruSayisi: 45), 1.0)
        XCTAssertEqual(Oncelik.dersAgirligi(soruSayisi: 15), 0.5)
        XCTAssertEqual(Oncelik.dersAgirligi(soruSayisi: 3), 0.3)
    }

    func testPuanFormulu() {
        // 20/30 · (4+5)/2/5 · (1 − 0,4) · 0,9 = 0,6667 · 0,9 · 0,6 · 0,9
        let p = Oncelik.puan(dersSoruSayisi: 20, sorulabilirlikler: [4, 5], saglamlik: 40, vade: .bugun)
        XCTAssertEqual(p, (20.0 / 30) * 0.9 * 0.6 * 0.9, accuracy: 1e-9)
        // Kazanımsız levha 0,6 sayılır; tam sağlam levhanın önceliği 0.
        XCTAssertEqual(Oncelik.puan(dersSoruSayisi: 30, sorulabilirlikler: [], saglamlik: 0, vade: .gecmis), 0.6, accuracy: 1e-9)
        XCTAssertEqual(Oncelik.puan(dersSoruSayisi: 30, sorulabilirlikler: [5], saglamlik: 100, vade: .gecmis), 0)
    }

    func testVadeCarpani() {
        let simdi = gun(10, 12)
        XCTAssertEqual(VadeDurumu.hesapla(nil, simdi: simdi, takvim: takvim), .hicCalisilmamis)
        XCTAssertEqual(VadeDurumu.hesapla(ZamanDurumu(levhaId: "a", sonrakiTarih: gun(9)), simdi: simdi, takvim: takvim), .gecmis)
        XCTAssertEqual(VadeDurumu.hesapla(ZamanDurumu(levhaId: "a", sonrakiTarih: gun(10)), simdi: simdi, takvim: takvim), .bugun)
        XCTAssertEqual(VadeDurumu.hesapla(ZamanDurumu(levhaId: "a", sonrakiTarih: gun(11)), simdi: simdi, takvim: takvim), .gelecek)
        // 11 Ekim 02:00 hâlâ 10 Ekim çalışma günüdür.
        XCTAssertEqual(VadeDurumu.hesapla(ZamanDurumu(levhaId: "a", sonrakiTarih: gun(10)), simdi: gun(11, 2), takvim: takvim), .bugun)
        XCTAssertEqual([VadeDurumu.hicCalisilmamis, .gecmis, .bugun, .gelecek].map(\.carpan), [1.0, 1.0, 0.9, 0.3])
    }

    func testVadesiGecmisGelecektenOnce() {
        let gecmis = Oncelik.puan(dersSoruSayisi: 20, sorulabilirlikler: [3], saglamlik: 50, vade: .gecmis)
        let gelecek = Oncelik.puan(dersSoruSayisi: 30, sorulabilirlikler: [5], saglamlik: 50, vade: .gelecek)
        XCTAssertGreaterThan(gecmis, gelecek)
    }
}

final class NetHesabiTests: XCTestCase {
    private func cevaplar(_ s: Int, dogru: Int, yanlis: Int) -> [(sorulabilirlik: Int, dogru: Bool)] {
        Array(repeating: (s, true), count: dogru) + Array(repeating: (s, false), count: yanlis)
    }

    func testTumTabakalarDolu() {
        // Her tabakada %80 → p = 0,8; net = 30·(0,8 − 0,2·0,25) = 22,5
        var c: [(sorulabilirlik: Int, dogru: Bool)] = []
        for s in 1...5 { c += cevaplar(s, dogru: 8, yanlis: 2) }
        let t = NetHesabi.tahmin(cevaplar: c, N: 30, ceza: 0.25)
        XCTAssertEqual(t.beklenen, 22.5, accuracy: 1e-9)
        XCTAssertEqual(t.n, 50)
        XCTAssertFalse(t.yetersiz)
        // SS = 30 · 1,25 · √(0,16/50) ≈ 2,121
        XCTAssertEqual(t.ust - t.beklenen, 30 * 1.25 * (0.16 / 50).squareRoot(), accuracy: 1e-9)
        XCTAssertEqual(t.beklenen - t.alt, t.ust - t.beklenen, accuracy: 1e-9)
    }

    func testEksikTabakaKomsudanAlinir() {
        // Yalnız 5 (%100) ve 1 (%0) dolu. 4 → 5'ten; 3 → 5 ve 1 eşit uzakta, üstteki (5) seçilir; 2 → 1'den.
        // p = 0,35·1 + 0,30·1 + 0,20·1 + 0,10·0 + 0,05·0 = 0,85
        let c = cevaplar(5, dogru: 20, yanlis: 0) + cevaplar(1, dogru: 0, yanlis: 20)
        let t = NetHesabi.tahmin(cevaplar: c, N: 20, ceza: 0)
        XCTAssertEqual(t.beklenen, 17, accuracy: 1e-9)
    }

    func testYetersizVeriVeSinirlar() {
        let az = NetHesabi.tahmin(cevaplar: cevaplar(3, dogru: 10, yanlis: 5), N: 30, ceza: 0.25)
        XCTAssertTrue(az.yetersiz)
        XCTAssertTrue(NetHesabi.tahmin(cevaplar: [], N: 30, ceza: 0.25).yetersiz)
        // Hepsi yanlış: alt sınır −N·ceza'nın altına inmez.
        let kotu = NetHesabi.tahmin(cevaplar: cevaplar(4, dogru: 0, yanlis: 40), N: 20, ceza: 0.25)
        XCTAssertEqual(kotu.beklenen, -5, accuracy: 1e-9)
        XCTAssertEqual(kotu.alt, -5, accuracy: 1e-9)
    }

    func testTahminEsigi() {
        XCTAssertEqual(NetHesabi.tahminEsigi(ceza: 0.25), 0.2, accuracy: 1e-9)
        XCTAssertEqual(NetHesabi.tahminEsigi(ceza: 0), 0)
    }
}
