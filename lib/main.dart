import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
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

  File? _photo;
  double _photoWidthPx = 1080;
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
      if (_autoTime && mounted) setState(() => _now = DateTime.now());
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
    final x = await _picker.pickImage(source: ImageSource.gallery);
    if (x == null) return;
    final file = File(x.path);
    final img = await decodeImageFromList(await file.readAsBytes());
    setState(() {
      _photo = file;
      _photoWidthPx = img.width.toDouble();
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
      try {
        final marks =
            await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (marks.isNotEmpty) {
          final p = marks.first;
          final parts = <String?>[
            p.subLocality,
            p.locality,
            p.subAdministrativeArea,
            p.administrativeArea,
            p.postalCode,
          ].where((e) => e != null && e.trim().isNotEmpty).cast<String>();
          if (parts.isNotEmpty) text = parts.join(', ');
        }
      } catch (_) {
        // Tanpa internet: pakai koordinat saja.
      }
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

  Future<void> _save() async {
    if (_photo == null) return;
    setState(() => _saving = true);
    try {
      final boundary = _boundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final ratio = (_photoWidthPx / boundary.size.width).clamp(1.0, 4.0);
      final image = await boundary.toImage(pixelRatio: ratio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (!await Gal.hasAccess()) await Gal.requestAccess();
      await Gal.putImageBytes(
        data!.buffer.asUint8List(),
        album: 'Watermark Foto',
        name: 'wm_${DateTime.now().millisecondsSinceEpoch}',
      );
      _toast('Tersimpan di galeri (album Watermark Foto)');
    } catch (e) {
      _toast('Gagal menyimpan: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
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
      appBar: AppBar(title: const Text('Watermark Foto')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            onPressed: _pickPhoto,
            icon: const Icon(Icons.photo_library),
            label:
                Text(_photo == null ? 'Pilih foto dari galeri' : 'Ganti foto'),
          ),
          const SizedBox(height: 12),
          if (_photo != null)
            RepaintBoundary(
              key: _boundaryKey,
              child: LayoutBuilder(
                builder: (context, c) => Stack(
                  children: [
                    Image.file(_photo!,
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
            label: const Text('Simpan ke galeri'),
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
