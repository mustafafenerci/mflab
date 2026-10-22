# Güvenlik Politikası (Security Policy)

## Desteklenen Sürümler

MF Lab projesinde aktif güvenlik güncellemeleri yalnızca en güncel ana sürüm için sağlanmaktadır.

| Sürüm | Destek Durumu |
| :--- | :--- |
| v1.2.x | :white_check_mark: Destekleniyor |
| < v1.2 | :x: Desteklenmiyor |

## Güvenlik Açığı Bildirme

MF Lab açık kaynaklı bir eğitim yazılımıdır. Bir güvenlik açığı keşfederseniz lütfen bunu genel bir GitHub Issue olarak açmak yerine doğrudan proje geliştiricisi **Mustafa Fenerci** ile iletişime geçerek özel olarak bildirin.

### Bildirirken Lütfen Belirtin:
1. Sorunun kısa bir özeti ve etki alanı.
2. Açığı yeniden üretmek için gereken adımlar veya kavram kanıtı (PoC).
3. Etkilenen bileşenler (Docker imajı, Inno Setup kurulumcusu, Flutter Windows uygulaması vb.).

Bildiriminiz incelendikten sonra en kısa sürede bir düzeltme yayımlanacak ve sürüm notlarında katkınız belirtilecektir.

## Bilinen Tasarım Kararları

- Ders servisleri (MariaDB, PostgreSQL, phpMyAdmin, pgAdmin) eğitim amacıyla basit şifrelerle (root/root, postgres/postgres) gelir ve yalnızca `127.0.0.1` üzerinden erişilebilir; ağdan erişime açılmamalıdır.
- Güncelleme dosyası HTTPS ile GitHub Releases'tan indirilir ve aynı sürümün `.sha256` dosyasıyla doğrulanır. Windows kurulum dosyası henüz kod imzalı değildir.
- Güvenlik bildirimleri: mustafa.fenerci@kapadokya.edu.tr
