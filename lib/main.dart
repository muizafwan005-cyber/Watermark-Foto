import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Watermark Foto',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.amber, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

/// Semua pengaturan tampilan watermark.
class WmData {
  String title = '';
  String time = '';
  String date = '';
  String address = '';
  String coords = '';
  String badge = '';
  File? logo;
  double logoScale = 1.0;
  bool showTitle = true;
  bool showTime = true;
  bool showDate = true;
  bool showAddress = true;
  bool showCoords = false;
  bool showLogo = true;
  bool showBadge = false;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _picker = ImagePicker();
  final _boundaryKey = GlobalKey();
  final _titleCtrl = TextEditingController(text: 'Perjalanan Dinas');
  final _addressCtrl = TextEditingController();
  final _badgeCtrl = TextEditingController(text: 'Dokumentasi Kegiatan');
  final _wm = WmData();

  List<File> _photos = [];
  int _index = 0;
  int _progress = 0;
  File? get _photo => _photos.isEmpty ? null : _photos[_index];
  double? _lat;
  double? _lng;

  bool _autoTime = true;
  DateTime _now = DateTime.now();
  DateTime _manualTime = DateTime.now();
  Timer? _ticker;

  bool _loadingLoc = false;
  bool _saving = false;

  DateTime get _shownTime => _autoTime ? _now : _manualTime;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_autoTime && !_saving && mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _titleCtrl.dispose();
    _addressCtrl.dispose();
    _badgeCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickPhoto() async {
    final xs = await _picker.pickMultiImage();
    if (xs.isEmpty) return;
    setState(() {
      _photos = xs.map((x) => File(x.path)).toList();
      _index = 0;
    });
    if (_addressCtrl.text.trim().isEmpty) _fetchLocation();
  }

  Future<void> _pickLogo() async {
    final x = await _picker.pickImage(source: ImageSource.gallery);
    if (x == null) return;
    setState(() {
      _wm.logo = File(x.path);
      _wm.showLogo = true;
    });
  }

  /// Alamat dari koordinat lewat OpenStreetMap Nominatim (butuh internet).
  Future<String?> _reverseGeocode(double lat, double lng) async {
    final client = HttpClient()..userAgent = 'WatermarkFotoApp/1.0';
    try {
      final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?format=jsonv2'
          '&addressdetails=1&accept-language=id&lat=$lat&lon=$lng');
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 10));
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final a = (json['address'] as Map?)?.cast<String, dynamic>() ?? {};
      String? pick(List<String> keys) {
        for (final k in keys) {
          final v = a[k];
          if (v is String && v.trim().isNotEmpty) return v;
        }
        return null;
      }

      final parts = <String?>[
        pick(['village', 'suburb', 'neighbourhood', 'hamlet']),
        pick(['municipality', 'city_district', 'town']),
        pick(['county', 'city', 'regency']),
        pick(['state']),
        pick(['postcode']),
      ].whereType<String>().toList();
      if (parts.isNotEmpty) return parts.join(', ');
      final dn = json['display_name'];
      return dn is String ? dn : null;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  Future<void> _fetchLocation() async {
    setState(() => _loadingLoc = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw 'GPS HP belum aktif';
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        throw 'Izin lokasi ditolak';
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      _lat = pos.latitude;
      _lng = pos.longitude;
      var text =
          '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}';
      final addr = await _reverseGeocode(pos.latitude, pos.longitude);
      if (addr != null) text = addr; // tanpa internet: tetap koordinat
      _addressCtrl.text = text;
    } catch (e) {
      _toast('Gagal ambil lokasi: $e');
    } finally {
      if (mounted) setState(() => _loadingLoc = false);
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _manualTime,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    setState(() => _manualTime = DateTime(
        d.year, d.month, d.day, _manualTime.hour, _manualTime.minute));
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_manualTime),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (t == null) return;
    setState(() => _manualTime = DateTime(_manualTime.year, _manualTime.month,
        _manualTime.day, t.hour, t.minute));
  }

  /// Render semua foto jadi PNG sementara (dan simpan ke galeri bila diminta).
  Future<List<String>> _renderAll({required bool toGallery}) async {
    final startIndex = _index;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final dir = await getTemporaryDirectory();
    final paths = <String>[];
    setState(() {
      _now = DateTime.now(); // jam sama untuk semua foto
      _saving = true;
      _progress = 0;
    });
    try {
      if (toGallery && !await Gal.hasAccess()) await Gal.requestAccess();
      for (var i = 0; i < _photos.length; i++) {
        await precacheImage(FileImage(_photos[i]), context);
        setState(() {
          _index = i;
          _progress = i + 1;
        });
        await WidgetsBinding.instance.endOfFrame;
        await Future.delayed(const Duration(milliseconds: 80));
        final boundary = _boundaryKey.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
        final decoded =
            await decodeImageFromList(await _photos[i].readAsBytes());
        final widthPx = decoded.width.toDouble();
        decoded.dispose();
        final ratio = (widthPx / boundary.size.width).clamp(1.0, 4.0);
        final image = await boundary.toImage(pixelRatio: ratio);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        final bytes = data!.buffer.asUint8List();
        final f = File('${dir.path}/wm_${stamp}_${i + 1}.png');
        await f.writeAsBytes(bytes);
        paths.add(f.path);
        if (toGallery) {
          await Gal.putImageBytes(bytes,
              album: 'Watermark Foto', name: 'wm_${stamp}_${i + 1}');
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _index = startIndex;
        });
      }
    }
    return paths;
  }

  Future<void> _save() async {
    if (_photos.isEmpty) return;
    try {
      final p = await _renderAll(toGallery: true);
      _toast('${p.length} foto tersimpan di galeri (album Watermark Foto)');
    } catch (e) {
      _toast('Gagal menyimpan: $e');
    }
  }

  Future<void> _share() async {
    if (_photos.isEmpty) return;
    try {
      final p = await _renderAll(toGallery: false);
      await SharePlus.instance.share(
        ShareParams(
          files: p.map((e) => XFile(e, mimeType: 'image/png')).toList(),
        ),
      );
    } catch (e) {
      _toast('Gagal membagikan: $e');
    }
  }

  Future<void> _openGallery() async {
    // Cara 1: buka daftar gambar lewat intent VIEW (paling kompatibel).
    if (Platform.isAndroid) {
      try {
        final intent = AndroidIntent(
          action: 'action_view',
          data: 'content://media/external/images/media',
          type: 'image/*',
          flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
        );
        await intent.launch();
        return;
      } catch (_) {
        // lanjut ke cara 2
      }
    }
    // Cara 2: bawaan paket gal.
    try {
      await Gal.open();
    } catch (e) {
      _toast('Tidak bisa membuka galeri: $e');
    }
  }

  void _syncData() {
    final t = _shownTime;
    _wm
      ..title = _titleCtrl.text
      ..time = DateFormat('HH:mm').format(t)
      ..date = DateFormat('EEEE, dd MMMM yyyy', 'id_ID').format(t)
      ..address = _addressCtrl.text
      ..badge = _badgeCtrl.text
      ..coords = (_lat != null && _lng != null)
          ? 'Lat ${_lat!.toStringAsFixed(6)}  Long ${_lng!.toStringAsFixed(6)}'
          : '';
  }

  Widget _chip(String label, bool value, void Function(bool) onChanged) {
    return FilterChip(
      label: Text(label),
      selected: value,
      onSelected: (v) => setState(() => onChanged(v)),
    );
  }

  @override
  Widget build(BuildContext context) {
    _syncData();
    return Scaffold(
      appBar: AppBar(title: const Text('Watermark Foto  v1.5')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            onPressed: _saving ? null : _pickPhoto,
            icon: const Icon(Icons.photo_library),
            label: Text(_photos.isEmpty
                ? 'Pilih foto (bisa banyak sekaligus)'
                : 'Ganti foto (${_photos.length} dipilih)'),
          ),
          if (_photos.length > 1) ...[
            const SizedBox(height: 8),
            Text(
              'Foto ${_index + 1} dari ${_photos.length} - pengaturan berlaku untuk semua foto',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _photos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) => GestureDetector(
                  onTap: _saving ? null : () => setState(() => _index = i),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: i == _index
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                        width: 3,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.file(_photos[i],
                          width: 64, height: 58, fit: BoxFit.cover,
                          cacheWidth: 160),
                    ),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (_photo != null)
            RepaintBoundary(
              key: _boundaryKey,
              child: LayoutBuilder(
                builder: (context, c) => Stack(
                  children: [
                    Image.file(_photo!, key: ValueKey(_photo!.path),
                        width: c.maxWidth, fit: BoxFit.fitWidth),
                    Positioned.fill(
                      child: WatermarkOverlay(width: c.maxWidth, d: _wm),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text('Tampilkan / sembunyikan', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _chip('Judul', _wm.showTitle, (v) => _wm.showTitle = v),
              _chip('Jam', _wm.showTime, (v) => _wm.showTime = v),
              _chip('Tanggal', _wm.showDate, (v) => _wm.showDate = v),
              _chip('Alamat', _wm.showAddress, (v) => _wm.showAddress = v),
              _chip('Koordinat', _wm.showCoords, (v) => _wm.showCoords = v),
              _chip('Logo', _wm.showLogo, (v) => _wm.showLogo = v),
              _chip('Teks pojok', _wm.showBadge, (v) => _wm.showBadge = v),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
                labelText: 'Judul (mis. Perjalanan Dinas)',
                border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
          if (_wm.showBadge) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _badgeCtrl,
              decoration: const InputDecoration(
                  labelText: 'Teks pojok kiri atas',
                  border: OutlineInputBorder()),
              onChanged: (_) => setState(() {}),
            ),
          ],
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Pakai jam & tanggal HP saat ini'),
            subtitle: const Text('Matikan untuk mengisi sendiri'),
            value: _autoTime,
            onChanged: (v) => setState(() {
              _autoTime = v;
              if (!v) _manualTime = DateTime.now();
            }),
          ),
          if (!_autoTime)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today),
                    label: Text(DateFormat('dd MMM yyyy', 'id_ID')
                        .format(_manualTime)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.access_time),
                    label: Text(DateFormat('HH:mm').format(_manualTime)),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _addressCtrl,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'Lokasi / alamat (bisa diedit)',
              border: const OutlineInputBorder(),
              suffixIcon: _loadingLoc
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : IconButton(
                      tooltip: 'Ambil lokasi HP sekarang',
                      icon: const Icon(Icons.my_location),
                      onPressed: _fetchLocation,
                    ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Text('Logo', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickLogo,
                  icon: const Icon(Icons.add_photo_alternate),
                  label: Text(_wm.logo == null ? 'Pilih logo' : 'Ganti logo'),
                ),
              ),
              if (_wm.logo != null) ...[
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: 'Hapus logo',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => setState(() => _wm.logo = null),
                ),
              ],
            ],
          ),
          if (_wm.logo != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Ukuran'),
                Expanded(
                  child: Slider(
                    min: 0.6,
                    max: 2.0,
                    value: _wm.logoScale,
                    onChanged: (v) => setState(() => _wm.logoScale = v),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: (_photo == null || _saving) ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_alt),
            label: Text(_saving
                ? 'Menyimpan $_progress/${_photos.length}...'
                : (_photos.length > 1
                    ? 'Simpan semua (${_photos.length}) ke galeri'
                    : 'Simpan ke galeri')),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _openGallery,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Lihat galeri'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: (_photos.isEmpty || _saving) ? null : _share,
                  icon: const Icon(Icons.share),
                  label: const Text('Bagikan'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Tampilan watermark ala Timemark. Ukuran font ikut lebar foto.
/// Logo ada di sebelah kiri kotak judul + jam.
class WatermarkOverlay extends StatelessWidget {
  const WatermarkOverlay({super.key, required this.width, required this.d});

  final double width;
  final WmData d;

  @override
  Widget build(BuildContext context) {
    final s = width / 400;
    const shadow = [Shadow(blurRadius: 4, color: Colors.black87)];
    TextStyle txt(double size, {bool bold = false}) => TextStyle(
          color: Colors.white,
          fontSize: size * s,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          shadows: shadow,
          height: 1.25,
        );

    final hasLogo = d.logo != null && d.showLogo;
    final showTitle = d.showTitle && d.title.trim().isNotEmpty;
    final showTimeBox = showTitle || d.showTime;
    final showTopRow = showTimeBox || hasLogo;
    final showAddr = d.showAddress && d.address.trim().isNotEmpty;
    final showCoords = d.showCoords && d.coords.isNotEmpty;
    final showTextBlock = d.showDate || showAddr || showCoords;

    final timeBox = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(5 * s),
      ),
      padding: EdgeInsets.all(3 * s),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showTitle)
            Container(
              color: const Color(0xFFFFC107),
              padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 4 * s),
              child: Text(d.title,
                  style: TextStyle(
                      color: Colors.black,
                      fontSize: 15 * s,
                      fontWeight: FontWeight.bold)),
            ),
          if (d.showTime)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 8 * s),
              child: Text(d.time,
                  style: TextStyle(
                      color: const Color(0xFF0D2B5E),
                      fontSize: 26 * s,
                      fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );

    final info = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showTopRow)
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (hasLogo)
                Padding(
                  padding: EdgeInsets.only(right: showTimeBox ? 8 * s : 0),
                  child: Image.file(d.logo!,
                      height: 42 * s * d.logoScale, fit: BoxFit.contain),
                ),
              if (showTimeBox) Flexible(child: timeBox),
            ],
          ),
        if (showTopRow && showTextBlock) SizedBox(height: 8 * s),
        if (showTextBlock)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 3 * s, color: const Color(0xFFFFC107)),
                SizedBox(width: 8 * s),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (d.showDate) Text(d.date, style: txt(15, bold: true)),
                      if (showAddr) Text(d.address, style: txt(13)),
                      if (showCoords) Text(d.coords, style: txt(12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        if (d.showBadge && d.badge.trim().isNotEmpty)
          Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: EdgeInsets.all(12 * s),
              child: Text(d.badge, style: txt(13, bold: true)),
            ),
          ),
        Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: EdgeInsets.fromLTRB(12 * s, 0, 12 * s, 12 * s),
            child: info,
          ),
        ),
      ],
    );
  }
}
