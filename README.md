# Housekeeping

Kumpulan script automation untuk kebutuhan housekeeping, cleansing data, dan berbagai keperluan operasional lain untuk mengurangi toil (manual/repetitive work).

## Daftar Script

### `cleansing-folder.sh`

Membersihkan file `.png` di dalam sebuah folder (termasuk subfolder) berdasarkan umur file, dengan konfirmasi sebelum menghapus.

**Fitur:**
- Input lokasi folder, divalidasi keberadaannya.
- Dua mode pemilihan file:
  1. **Rentang waktu** — hapus file dengan tanggal modifikasi di antara `dd-mm-yyyy` s/d `dd-mm-yyyy`.
  2. **Lebih lama dari** — hapus file dari bulan tertentu dan sebelumnya (`mm-yyyy`).
- Menampilkan jumlah file dan estimasi total ukuran sebelum eksekusi.
- Konfirmasi `yes/no` sebelum menghapus (default aman, bisa dibatalkan).
- Progress `current/total` saat proses hapus, dioptimasi untuk folder dengan ratusan ribu file (batch delete, single-pass scan).

**Requirement:** Linux dengan GNU coreutils (`date`, `find`, `stat` versi GNU — bukan macOS/BSD).

**Cara pakai:**
```bash
chmod +x cleansing-folder.sh
./cleansing-folder.sh
```

⚠️ **Peringatan:** Script ini melakukan penghapusan file secara permanen (`rm -f`). Pastikan folder target sudah benar dan ada backup/snapshot jika data penting, sebelum menjawab `yes` pada konfirmasi.

## Konvensi

- Setiap script bersifat interaktif dan selalu menampilkan konfirmasi sebelum melakukan aksi yang bersifat merusak/tidak bisa dibatalkan (delete, overwrite, dll).
- Script ditulis untuk dijalankan di lingkungan Linux (server), menggunakan GNU coreutils.
- Tidak ada kredensial atau path spesifik environment yang di-hardcode di dalam script — semua input environment-specific diminta secara interaktif saat runtime.
