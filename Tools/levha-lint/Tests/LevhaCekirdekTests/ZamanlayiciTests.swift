import XCTest
@testable import LevhaCekirdek

final class ZamanlayiciTests: XCTestCase {
    private var takvim: Calendar = {
        var t = Calendar(identifier: .gregorian)
        t.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return t
    }()

    private func tarih(_ gun: Int, _ saat: Int = 12, _ dakika: Int = 0) -> Date {
        takvim.date(from: DateComponents(year: 2026, month: 10, day: gun, hour: saat, minute: dakika))!
    }

    private func gun(_ g: Int) -> Date { tarih(g, 0) }

    func testIlkBasariKutuyuArtirir() {
        let y = Zamanlayici.ortmeSonucu(ZamanDurumu(levhaId: "a"), bildim: 3, toplam: 3, simdi: tarih(2), takvim: takvim)
        XCTAssertEqual(y.kutu, 1)
        XCTAssertEqual(y.sonrakiTarih, gun(5))   // 3 gün sonra
        XCTAssertEqual(y.sonGorulme, tarih(2))
    }

    func testBasarisizlikKutuyuAzaltir() {
        let y = Zamanlayici.ortmeSonucu(ZamanDurumu(levhaId: "a", kutu: 2), bildim: 2, toplam: 3, simdi: tarih(2), takvim: takvim)
        XCTAssertEqual(y.kutu, 1)
        XCTAssertEqual(y.sonrakiTarih, gun(5))
    }

    func testAltSinirSifir() {
        let y = Zamanlayici.ortmeSonucu(ZamanDurumu(levhaId: "a", kutu: 0), bildim: 0, toplam: 3, simdi: tarih(2), takvim: takvim)
        XCTAssertEqual(y.kutu, 0)
        XCTAssertEqual(y.sonrakiTarih, gun(3))   // 1 gün sonra
    }

    func testUstSinirDort() {
        let y = Zamanlayici.ortmeSonucu(ZamanDurumu(levhaId: "a", kutu: 4), bildim: 3, toplam: 3, simdi: tarih(1), takvim: takvim)
        XCTAssertEqual(y.kutu, 4)
        XCTAssertEqual(y.sonrakiTarih, gun(31))  // 30 gün sonra
    }

    func testYuzdeSeksenEsikDahil() {
        let d = ZamanDurumu(levhaId: "a", kutu: 1)
        XCTAssertEqual(Zamanlayici.ortmeSonucu(d, bildim: 4, toplam: 5, simdi: tarih(2), takvim: takvim).kutu, 2)
        XCTAssertEqual(Zamanlayici.ortmeSonucu(d, bildim: 3, toplam: 4, simdi: tarih(2), takvim: takvim).kutu, 0)
        XCTAssertEqual(Zamanlayici.ortmeSonucu(d, bildim: 0, toplam: 0, simdi: tarih(2), takvim: takvim), d)
    }

    func testVadeHesabi() {
        XCTAssertTrue(Zamanlayici.vadeliMi(nil, simdi: tarih(2), takvim: takvim))
        XCTAssertTrue(Zamanlayici.vadeliMi(ZamanDurumu(levhaId: "a"), simdi: tarih(2), takvim: takvim))
        let yarin = ZamanDurumu(levhaId: "a", kutu: 0, sonrakiTarih: gun(3))
        XCTAssertFalse(Zamanlayici.vadeliMi(yarin, simdi: tarih(2, 23, 59), takvim: takvim))
        XCTAssertTrue(Zamanlayici.vadeliMi(yarin, simdi: tarih(3, 4, 0), takvim: takvim))
        XCTAssertTrue(Zamanlayici.vadeliMi(yarin, simdi: tarih(10), takvim: takvim))
    }

    func testGunDonumuSaat4() {
        // 3 Ekim 03:30 hâlâ 2 Ekim çalışma günüdür.
        XCTAssertEqual(Zamanlayici.calismaGunu(tarih(3, 3, 30), takvim: takvim), gun(2))
        XCTAssertEqual(Zamanlayici.calismaGunu(tarih(3, 4, 0), takvim: takvim), gun(3))
        XCTAssertEqual(Zamanlayici.gunAnahtari(tarih(3, 3, 30), takvim: takvim), "2026-10-02")
        let y = Zamanlayici.ortmeSonucu(ZamanDurumu(levhaId: "a"), bildim: 0, toplam: 3, simdi: tarih(3, 3, 30), takvim: takvim)
        XCTAssertEqual(y.sonrakiTarih, gun(3))
        // Vade 3 Ekim ama 03:59'da henüz gelmedi.
        XCTAssertFalse(Zamanlayici.vadeliMi(y, simdi: tarih(3, 3, 59), takvim: takvim))
    }

    func testSaglamlikFormulu() {
        XCTAssertEqual(Zamanlayici.saglamlik(ortmeOranlari: [], soruSonuclari: [], sabotajSonuclari: []), 0)
        // 0,5·100 + 0,3·50 + 0,2·0 = 65
        XCTAssertEqual(Zamanlayici.saglamlik(ortmeOranlari: [1, 1], soruSonuclari: [true, false], sabotajSonuclari: [false]), 65)
        // Yalnız örtme: ağırlık örtmeye kalır; son 3 oturum (ilk 0 dışarıda kalır).
        XCTAssertEqual(Zamanlayici.saglamlik(ortmeOranlari: [0, 1, 1, 1], soruSonuclari: [], sabotajSonuclari: []), 100)
        // Örtme yok: (0,3·100 + 0,2·0) / 0,5 = 60
        XCTAssertEqual(Zamanlayici.saglamlik(ortmeOranlari: [], soruSonuclari: [true], sabotajSonuclari: [false]), 60)
    }

    func testTohumluUretecTekrarlanabilir() {
        var a = TohumluUretec(tohum: "ped.neo.sarilik.algoritma|2026-10-02")
        var b = TohumluUretec(tohum: "ped.neo.sarilik.algoritma|2026-10-02")
        var c = TohumluUretec(tohum: "ped.neo.sarilik.algoritma|2026-10-03")
        let dizi = (0..<5).map { _ in a.next() }
        XCTAssertEqual(dizi, (0..<5).map { _ in b.next() })
        XCTAssertNotEqual(dizi, (0..<5).map { _ in c.next() })
    }
}
