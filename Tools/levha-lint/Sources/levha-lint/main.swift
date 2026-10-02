import Foundation
import LevhaSema

let dosyalar = CommandLine.arguments.dropFirst()
guard !dosyalar.isEmpty else {
    print("Kullanım: swift run levha-lint <paket.json> [<paket.json> ...]")
    exit(2)
}

var toplam = 0
for yol in dosyalar {
    let url = URL(fileURLWithPath: yol)
    guard let veri = try? Data(contentsOf: url) else {
        print("\(yol): dosya okunamadı")
        toplam += 1
        continue
    }
    let sonuc = LevhaLint.denetle(veri: veri)
    for bulgu in sonuc.bulgular {
        print("\(url.lastPathComponent): \(bulgu)")
    }
    toplam += sonuc.bulgular.count
}

print(toplam == 0 ? "OK" : "\(toplam) hata")
exit(toplam == 0 ? 0 : 1)
