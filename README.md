# MF Lab

<p align="center"><img src="assets/images/logo.png" width="140" alt="MF Lab logosu"></p>

**MF Lab**, öğrencilerin ders için gereken yazılımları (Apache, PHP, MariaDB, PostgreSQL, Composer, Git, VS Code ve eklentileri) **tek yerden, ne yaptığını anlayarak** kurmasını sağlayan bir Windows uygulamasıdır.

- Dersini seç, kurulacak yazılımları ve **neden kurulduğunu** oku.
- Sunucu yazılımları **Docker** konteynerlerinde çalışır: herkeste aynı ortam, bilgisayar temiz kalır.
- Çalışma klasörün (`htdocs` gibi) Windows'ta durur, konteynere bağlıdır.
- Masaüstüne kısayollar eklenir (klasör, VS Code, phpMyAdmin, pgAdmin, siteni aç).
- Hata olursa nedeni ve resmi kaynak bağlantısı gösterilir.
- Uygulama kapansa da servisler çalışmaya devam eder. Başlat/durdur "Yönetim" sayfasındadır.

## Dersler (v1.0)

| Ders | Kurulanlar |
|---|---|
| Web Tasarımı | VS Code + HTML/CSS/JS eklentileri (Docker gerekmez) |
| Web Programlama II | Docker, VS Code, Git, Apache + PHP 8.3 + Composer + Node.js, MariaDB, phpMyAdmin, Laravel desteği |
| Veritabanı Yönetim Sistemleri | Docker, VS Code, PostgreSQL + pgAdmin, MariaDB + phpMyAdmin |

## Öğrenci için kurulum

1. [Releases](https://github.com/mustafafenerci/mflab/releases/latest) sayfasından `MFLab-Setup.exe` dosyasını indir ve çalıştır.
2. MF Lab'i aç, dersini seç, **Kur**'a bas.
3. Docker yoksa uygulama indirme sayfasını açar. Docker Desktop'ı kurup tekrar **Kur**'a bas.

> Docker için bilgisayarda sanallaştırma açık olmalı (WSL2). Önerilen: en az 8 GB RAM.

## Geliştirme

Gereksinimler: Flutter (Windows desktop), Docker.

```bash
flutter pub get
flutter run -d windows
flutter test
flutter build windows --release
```

Yapı:

```
assets/packages/   yazılım paketi tanımları (JSON)
assets/courses/    ders tanımları (JSON)
assets/compose/    docker compose şablonları
assets/help/       hata -> açıklama + kaynak eşlemeleri
docker/php-web/    özel PHP imajı (GHCR'a yayınlanır)
installer/         Inno Setup betiği (MFLab-Setup.exe)
lib/               Flutter uygulaması
version.json       güncelleme denetimi için sürüm bilgisi
```

### Yeni ders ekleme

Kod yazmadan, JSON ile:

1. Gerekirse `assets/packages/<paket>.json` ekle (`type: "tool"` ya da `"docker"`, `why` alanını doldur).
2. Docker paketiyse `assets/compose/<ad>.yml` ekle (çalışma klasörü `${WORKSPACE}` değişkeniyle bağlanır).
3. `assets/courses/courses.json` içine dersi ekle (paketler, VS Code eklentileri, çalışma klasörü adı).

Ayrıntılar için [CONTRIBUTING.md](CONTRIBUTING.md).

### Kendi sürümün (fork)

[`lib/config.dart`](lib/config.dart) içindeki GitHub kullanıcı/depo adını ve `docker/php-web` imaj adını (compose dosyalarında) kendi hesabınla değiştir.

## Sürüm yayınlama

1. `lib/config.dart` ve `pubspec.yaml` içindeki sürümü ve `version.json`'u güncelle.
2. `git tag v1.0.1 && git push --tags`
3. GitHub Actions uygulamayı derler, `MFLab-Setup.exe`'yi Release'e yükler. `docker/php-web` değiştiyse imaj da GHCR'a gönderilir.

Öğrenciler uygulamayı açtıklarında `version.json` kontrol edilir ve yeni sürüm varsa bildirim görürler.

## Lisans

[MIT](LICENSE) © 2026 Mustafa Fenerci
