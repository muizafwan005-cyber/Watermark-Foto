# Watermark Foto

Pilih foto dari galeri, tambahkan watermark jam, tanggal, dan lokasi (gaya Timemark), lalu simpan ke galeri.

- Jam & tanggal: otomatis dari HP, atau matikan saklar untuk mengisi sendiri.
- Lokasi: otomatis dari GPS HP (tombol target), atau ketik/edit sendiri.

## Cara membuat APK lewat GitHub
1. Buat repository baru di GitHub.
2. Upload **isi** folder ini (pubspec.yaml, lib/, .github/, dst.) ke root repository.
3. Buka tab **Actions** -> workflow **Build APK** (jalan otomatis saat push, atau klik *Run workflow*).
4. Setelah hijau, buka run tersebut -> bagian **Artifacts** -> unduh `watermark-foto-apk`.
5. Ekstrak zip, pindahkan `app-release.apk` ke HP, lalu instal (izinkan "instal dari sumber tidak dikenal").

## Fitur tampilan
Setiap elemen bisa dimunculkan/disembunyikan lewat chip: Judul, Jam, Tanggal, Alamat, Koordinat, Logo, Teks pojok.
Logo dipilih dari galeri (PNG transparan paling bagus), diletakkan di sebelah kiri kotak judul + jam, ukuran bisa diatur.
