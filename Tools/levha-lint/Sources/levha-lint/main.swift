import Foundation
import LevhaSema

let dosyalar = CommandLine.arguments.dropFirst()
guard !dosyalar.isEmpty else {
    print("Kullanım: swift run levha-lint <paket.json> [<paket.json> ...]")
    exit(2)
}

var hataSayisi = 0
var uyariSayisi = 0
for yol in dosyalar {
    let url = URL(fileURLWithPath: yol)
    guard let veri = try? Data(contentsOf: url) else {
        print("\(yol): dosya okunamadı")
        hataSayisi += 1
        continue
    }
    let sonuc = LevhaLint.denetle(veri: veri)
    for bulgu in sonuc.hatalar { print("\(url.lastPathComponent): \(bulgu)") }
    for bulgu in sonuc.uyarilar { print("\(url.lastPathComponent): uyarı: \(bulgu)") }
    hataSayisi += sonuc.hatalar.count
    uyariSayisi += sonuc.uyarilar.count
}

let uyariEki = uyariSayisi > 0 ? " · \(uyariSayisi) uyarı" : ""
print(hataSayisi == 0 ? "OK\(uyariEki)" : "\(hataSayisi) hata\(uyariEki)")
exit(hataSayisi == 0 ? 0 : 1)
