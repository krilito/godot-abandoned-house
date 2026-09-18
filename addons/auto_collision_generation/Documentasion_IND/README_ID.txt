=====================================
 AUTO COLLISION GENERATOR (Free 1.0)
=====================================

Pembuat: RaykitsID

Plugin ini membuat collision (bentuk tabrakan) secara otomatis 
untuk mesh 3D di Godot Engine. Dirancang khusus supaya mudah 
dipakai lewat HP / Godot Mobile, tanpa perlu klik kanan menu 
editor yang ribet.


CARA PASANG & AKTIFASI
-----------------------
1. Salin folder plugin ke dalam folder "addons" di project kamu.

2. Buka Project > Pengaturan Proyek > tab Globals.
   Klik "Select Script/Scene", pilih file collision_map.gd 
   dari folder plugin, lalu centang kotak "Aktifkan".

3. Setelah aktif, akan muncul tab baru "Auto Collision" 
   di bagian bawah layar editor Godot.

4. PENTING - kalau model kamu berformat GLB/GLTF/FBX yang 
   diinstansiasi ke scene:
   Tekan lama (long press) pada node model itu di panel Scene,
   lalu aktifkan opsi "Anakan yang Dapat Disunting".
   Tanpa ini, collision yang dibuat bisa hilang saat scene 
   ditutup dan dibuka lagi.

5. Buka scene yang mau diproses, tap tab "Auto Collision", 
   lalu tekan tombol "Generate Collision".

6. Cek hasilnya di panel Scene: akan muncul node baru 
   StaticBody3D dan CollisionShape3D di bawah tiap mesh.

Panduan bergambar step-by-step ada di folder:
"Cara Pemakaian & Aktifasi"


CATATAN PEMAKAIAN
-------------------
- Plugin ini bekerja untuk semua node bertipe MeshInstance3D.
- Cocok untuk map/level statis (dinding, lantai, properti),
  bukan untuk karakter atau objek yang bergerak.
- Kalau mesh tidak ditemukan pada node, node tersebut akan 
  dilewati begitu saja (bukan error).
- Selalu backup project sebelum memakai plugin apapun,
  termasuk plugin ini.

Untuk info lisensi dan batasan tanggung jawab, baca License.txt.
