# Levha

Kişisel TUS çalışma uygulaması (iOS 17+, SwiftUI + SwiftData, yalnız iPhone).

## Kurulum

1. `Levha.xcodeproj`'u Xcode 16+ ile aç.
2. *Signing & Capabilities* → Team: kendi Apple ID'n. Bundle id gerekirse değiştir (`tr.kisisel.levha`).
3. iPhone'u bağla, **Run**.

**iCloud ve App Group:** Proje iCloud Drive (iCloud Documents) ve App Group (`group.tr.kisisel.levha`,
widget için) yetkileriyle gelir; ikisi de ücretli geliştirici hesabı ister. Ücretsiz Apple ID ile kuruyorsan
*Signing & Capabilities*'ten **iCloud** ve **App Groups**'u (uygulama ve LevhaWidget hedeflerinde) kaldır.
Uygulama o zaman yerel klasöre ve yerel depoya düşer; widget boş görünür, başka bir şey değişmez.
Bundle id'yi değiştirirsen `project.yml`'deki `iCloud.tr.kisisel.levha` ve `group.tr.kisisel.levha` geçen
yerleri ve `Ortak/WidgetAnligi.swift`'teki grup adını da güncelle.

**Widget:** Ana ekranda uzun bas › + › "Levha": orta boy (maskeli levha, dokununca Örtme'de açar) ve
küçük boy (bugünün turu). Kısayollar uygulamasında "Levha turu" eylemi uygulamayı Bugün'de açar.

**Model:** Bu sürümde ağ çağrısı yok. "Modele sor", levha genişletme, Editör değerlendirmesi ve kitap sayfası
önerisi sahte (çevrimdışı) istemciyle çalışır; Ölçüm › ⚙︎ Ayarlar'daki API alanları yalnız saklanır (anahtar Keychain'de).

**Kitap sayfası (Bugün):** Kamera izni ilk kullanımda sorulur; metin cihazda okunur. Simülatörde kamera yoktur:
`xcrun simctl addmedia booted SamplePackages/test-sayfa.jpg` ile test sayfasını galeriye ekle ya da ekrandaki
**Örnek sayfayla dene**'ye dokun.

Projeye dosya eklersen: `xcodegen generate` (proje `project.yml`'den üretilir).

## Paketler nereye konur

- iCloud açıksa: **Dosyalar › iCloud Drive › Levha › Paketler**
- iCloud kapalıysa: **Dosyalar › Bu iPhone'da › Levha › Paketler**

Uygulamada **İçerik** sekmesi klasördeki tüm `.json` dosyalarını listeler (hatalı olanlar kırmızı, hangi
levha/hangi alan olduğu yazar). **Hepsini içe aktar** ya da **Dosya seç…**. `SamplePackages/` içindeki örnek
paketler uygulamayla gelir; yeni ya da değişmiş olanlar açılışta otomatik yüklenir.

Şema sürümü 4'tür (`Levha/Schema/levha.schema.json`); sürüm 1–3 paketler okunmaya devam eder.
Ders ağırlıkları ve yanlış cezası paketten değil, Ölçüm › ⚙︎ Ayarlar'dan gelir.

Aynı `id`'li levha yeniden içe aktarılınca **düzen korunur** (konumlar ve taslaktan eklenen düğümler değişmez);
etiket, not ve sorular güncellenir. Paketteki levhanın `revizyon`'u depodakinden büyükse **paket kazanır**:
konumlar JSON'dan gelir, yerel eklemeler silinir. Kendi notların (Notum) hiçbir durumda silinmez.

## Lint

```bash
swift run levha-lint SamplePackages/ped.neo.sarilik.json
```

Birden fazla dosya verilebilir (`swift run levha-lint SamplePackages/*.json`). Çıktı satır satır hata,
sonda `OK` ya da `N hata`; uyarılar (sorusuz kazanım, ipucu sırası olmayan vaka sorusu, anahtar kelimesi olmayan
levha...) listelenir ama hata sayılmaz. Lint, zamanlayıcı, öncelik, tahmini net, ipucu puanı ve sayfa eşleme
testleri: `cd Tools/levha-lint && swift test`.
Şema: `Levha/Schema/levha.schema.json`.
