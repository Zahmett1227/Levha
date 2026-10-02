import SwiftUI

/// Ağaç: kök satır 0'da; kenarlar bağlantılardan ya da düğümlerin `ebeveyn` alanından gelir
/// (içe aktarıcı ebeveynleri bağlantıya çevirir).
/// Keşif katmanları: 1 kök + 1. seviye, 2 alt seviyeler, 3 TUS, 4 notlar.
struct AgacCanvas: View {
    let cizim: LevhaCizim
    let durum: LevhaGorunumDurumu
    let boyut: CGSize
    let dokun: (String) -> Void

    var body: some View {
        IzgaraCanvas(cizim: cizim, durum: durum, boyut: boyut, stil: .agac, dokun: dokun)
    }
}
