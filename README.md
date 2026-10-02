# Levha

Kişisel TUS çalışma uygulaması (iOS 17+, SwiftUI + SwiftData, yalnız iPhone).

## Kurulum

1. `Levha.xcodeproj`'u Xcode 16+ ile aç.
2. *Signing & Capabilities* → Team: kendi Apple ID'n. Bundle id gerekirse değiştir (`tr.kisisel.levha`).
3. iPhone'u bağla, **Run**.

**iCloud:** Proje iCloud Drive (iCloud Documents) yetkisiyle gelir; bu, ücretli geliştirici hesabı ister.
Ücretsiz Apple ID ile kuruyorsan *Signing & Capabilities*'ten **iCloud**'u kaldır. Uygulama
o zaman yerel klasöre düşer; başka bir şey değişmez.
Bundle id'yi değiştirirsen `project.yml`'deki `iCloud.tr.kisisel.levha` geçen iki yeri de güncelle.

Projeye dosya eklersen: `xcodegen generate` (proje `project.yml`'den üretilir).

## Paketler nereye konur

- iCloud açıksa: **Dosyalar › iCloud Drive › Levha › Paketler**
- iCloud kapalıysa: **Dosyalar › Bu iPhone'da › Levha › Paketler**

Uygulamada **İçerik** sekmesi klasördeki tüm `.json` dosyalarını listeler (hatalı olanlar kırmızı, hangi
levha/hangi alan olduğu yazar). **Hepsini içe aktar** ya da **Dosya seç…**. `SamplePackages/` içindeki örnek
paketler uygulamayla gelir; yeni ya da değişmiş olanlar açılışta otomatik yüklenir.

Şema sürümü 2'dir (`Levha/Schema/levha.schema.json`); sürüm 1 paketler okunmaya devam eder.

Aynı `id`'li levha yeniden içe aktarılınca **düzen korunur** (konumlar değişmez); etiket, not ve sorular güncellenir.
Düzeni sıfırlamak için paketi İçerik'te sola kaydırıp sil, sonra yeniden içe aktar.

## Lint

```bash
swift run levha-lint SamplePackages/ped.neo.sarilik.json
```

Birden fazla dosya verilebilir (`swift run levha-lint SamplePackages/*.json`). Çıktı satır satır hata,
sonda `OK` ya da `N hata`; yazılmış sabotajı olmayan levhalar "uyarı" olarak listelenir ama hata sayılmaz.
Lint ve zamanlayıcı testleri: `cd Tools/levha-lint && swift test`.
Şema: `Levha/Schema/levha.schema.json`.
