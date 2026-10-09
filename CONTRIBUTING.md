# Katkı rehberi

MF Lab MIT lisanslıdır; indirip kendi ihtiyacına göre geliştirebilir, fork edip kendi sürümünü yayınlayabilirsin.

Ana depoya değişiklik **Pull Request** ile gelir ve depo sahibi (Mustafa Fenerci) tarafından incelenip onaylanırsa birleştirilir.

## Nasıl katkı verilir?

1. Depoyu fork et, yeni bir dal aç.
2. Değişikliğini yap, `flutter analyze` ve `flutter test` komutlarının geçtiğinden emin ol.
3. Pull Request aç: ne eklediğini ve hangi derste kullanıldığını yaz.

## Yeni ders / paket eklemek

Çoğu katkı sadece JSON gerektirir:

- `assets/packages/*.json`: `id`, `name`, `type` (`tool` | `docker`), `why` (öğrenciye "neden kuruyoruz?" açıklaması), `steps`, `info`. Docker paketlerinde `compose`, `links`, `ports`. Araçlarda `check` ve `downloadUrl`.
- `assets/compose/*.yml`: çalışma klasörü için `${WORKSPACE}` kullan; veritabanı verisi için isimli volume tanımla.
- `assets/courses/courses.json`: ders adı, açıklaması, paketleri, VS Code eklentileri, `workspaceName`.
- `assets/help/errors.json`: yeni hata kalıpları için açıklama ve resmi kaynak bağlantısı.

## Kurallar

- Öğrenciyi yormayan, açıklayıcı ve Türkçe metinler yaz.
- Şifre/token gibi gizli bilgi ekleme (compose'taki yerel eğitim şifreleri hariç).
- Port çakışmalarında sessizce çözüm uygulama; hatayı açıkla ve kaynağa yönlendir.
