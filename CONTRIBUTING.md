# MF Lab Katkı Rehberi (Contributing Guide)

MF Lab, öğrencilerin karmaşık yerel sunucu kurulumlarıyla vakit kaybetmeden derslerine odaklanmalarını sağlamak amacıyla geliştirilmiş açık kaynaklı bir projedir. Projeye katkıda bulunmak isteyen tüm eğitmenler, geliştiriciler ve öğrencilerin katkılarını (Pull Request) memnuniyetle karşılıyoruz!

---

## 🚀 Hızlı Katkı Adımları (Pull Request Süreci)

1. **Projeyi Fork'layın:**
   GitHub sayfasının sağ üst köşesindeki **Fork** butonuna basarak depoyu kendi hesabınıza kopyalayın.

2. **Kendi Bilgisayarınıza Klonlayın:**
   ```bash
   git clone https://github.com/<kullanici-adiniz>/mflab.git
   cd mflab
   ```

3. **Yeni Bir Çalışma Dalı (Branch) Açın:**
   ```bash
   git checkout -b feature/yeni-ozellik
   # veya hata düzeltmesi için:
   git checkout -b fix/hata-duzeltmesi
   ```

4. **Geliştirme Ortamını Hazırlayın:**
   * Flutter SDK (3.x+ / Windows Desktop desteği aktif olmalı)
   * Docker Desktop
   * Inno Setup 6 (Setup derleyecekseniz)
   ```bash
   flutter pub get
   flutter run -d windows
   ```

5. **Testleri ve Kod Analizini Çalıştırın:**
   Herhangi bir değişiklik sonrasında tüm testlerin geçtiğinden emin olun:
   ```bash
   flutter analyze
   flutter test
   ```

6. **Değişikliklerinizi Commit Edin ve Push'layın:**
   ```bash
   git add .
   git commit -m "feat: yeni ders/özellik açıklaması"
   git push origin feature/yeni-ozellik
   ```

7. **Pull Request Açın:**
   GitHub üzerindeki deponuza gidin ve **"Compare & pull request"** butonuna tıklayın. Açılan PR şablonundaki maddeleri doldurarak gönderin.

---

## 🧩 Kod Yazmadan Katkı Vermek (JSON ile Yeni Ders/Paket)

MF Lab modüler bir mimariye sahiptir; pek çok yeni ders veya araç eklemek için Dart kodu yazmanız gerekmez:

1. **Yeni Paket Tanımı (`assets/packages/<paket_id>.json`):**
   * `id`: Benzersiz paket kimliği.
   * `name`: Paketin ekranda görünen adı.
   * `type`: `"tool"` (yerel araç/VS Code eklentisi) veya `"docker"` (konteyner servisi).
   * `why`: Öğrenciye gösterilen "Bu yazılım neden kuruluyor?" pedagojik açıklaması.
   * `ports`: Servisin dinlediği portlar (Çakışmaları önlemek için mutlaka **63xx** aralığından seçiniz).

2. **Yeni Compose Şablonu (`assets/compose/<paket_id>.yml`):**
   * Çalışma dizini olarak `${WORKSPACE}` değişkenini kullanın.
   * Öğrenci verilerinin kaybolmaması için veritabanı dosyalarını kalıcı Docker volume olarak tanımlayın.

3. **Ders Listesine Ekleme (`assets/courses/courses.json`):**
   * Dersin adını, açıklamasını, ilişkili paket kimliklerini ve masaüstü çalışma klasör adını ekleyin.

4. **Hata Rehberine Katkı (`assets/help/errors.json`):**
   * Öğrencilerin sık karşılaştığı hata metinlerini (örn. sanallaştırma kapalı, port dolu vb.) ve çözüm adımlarını ekleyin.

---

## 📌 Mimari İlkeler ve Kurallar

* **Port Standardı:** Yerel Windows servisleriyle (ör. yerel MySQL, IIS, PostgreSQL) çakışmaları önlemek için tüm harici servis portları **63xx** aralığında tanımlanmalıdır (Ör: Apache `6380`, phpMyAdmin `6381`, MariaDB `6306`, PostgreSQL `6332`, pgAdmin `6350`).
* **Öğrenci Güvenliği:** Öğrencinin yazdığı kodlar ve veritabanı verileri (`C:\MFLab\...`) kurulum kaldırılsa dahi asla izinsiz silinmemelidir.
* **Dil ve Anlatım:** Arayüzde öğrenciye gösterilen tüm mesajlar, hata açıklamaları ve rehberler anlaşılır, yapıcı ve Türkçe olmalıdır.
* **Gizlilik:** Kod tabanına hiçbir şekilde kişisel şifre, gizli anahtar veya token eklenmemelidir.

---

## 🛠️ Yerel Kurulumcu (Setup) Derleme

Inno Setup yüklü ise yerel setup dosyasını tek tıkla derleyip masaüstünüze kopyalamak için:
```powershell
.\build_installer.ps1
# veya
.\build_installer.bat
```

Sorularınız ve önerileriniz için [GitHub Issues](https://github.com/mustafafenerci/mflab/issues) üzerinden iletişime geçebilirsiniz.
