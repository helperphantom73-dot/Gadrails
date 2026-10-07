import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kSvc = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
const kRx = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';
const kTx = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';
const kA = Color(0xFF6C5CE7), kB = Color(0xFF00CEC9), kC = Color(0xFFFD79A8);

void main() => runApp(const App());

class Ble {
  static BluetoothDevice? dev;
  static BluetoothCharacteristic? rx;
  static final data = ValueNotifier<List<String>>([]);
  static Future<void> connect(BluetoothDevice d) async {
    await d.connect(timeout: const Duration(seconds: 12));
    dev = d;
    try { await d.requestMtu(247); } catch (_) {}
    for (final s in await d.discoverServices()) {
      if (s.uuid.str128.toLowerCase() != kSvc) continue;
      for (final c in s.characteristics) {
        final u = c.uuid.str128.toLowerCase();
        if (u == kRx) rx = c;
        if (u == kTx) {
          await c.setNotifyValue(true);
          c.onValueReceived.listen((v) => data.value = utf8.decode(v, allowMalformed: true).split(','));
        }
      }
    }
  }
  static void send(String s) => rx?.write(utf8.encode(s), withoutResponse: true);
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext c) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'GadRail Project',
        theme: ThemeData.dark(useMaterial3: true).copyWith(scaffoldBackgroundColor: const Color(0xFF0B0D1C)),
        builder: (c, w) => Directionality(textDirection: TextDirection.rtl, child: w!),
        home: const Root(),
      );
}

class Root extends StatefulWidget {
  const Root({super.key});
  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  bool? seen;
  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) => setState(() => seen = p.getBool('seen') ?? false));
  }
  Future<void> done() async {
    (await SharedPreferences.getInstance()).setBool('seen', true);
    setState(() => seen = true);
  }
  @override
  Widget build(BuildContext c) => seen == null ? const Scaffold() : seen! ? const ConnectPage() : Intro(onDone: done);
}

class Pulse extends StatefulWidget {
  final Widget child;
  const Pulse({super.key, required this.child});
  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin {
  late final c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
  @override
  void dispose() { c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext x) => ScaleTransition(
      scale: Tween(begin: .92, end: 1.12).animate(CurvedAnimation(parent: c, curve: Curves.easeInOut)), child: widget.child);
}

class Intro extends StatefulWidget {
  final VoidCallback onDone;
  const Intro({super.key, required this.onDone});
  @override
  State<Intro> createState() => _IntroState();
}

class _IntroState extends State<Intro> with SingleTickerProviderStateMixin {
  final pc = PageController();
  int i = 0;
  late final ac = AnimationController(vsync: this, duration: const Duration(seconds: 4));
  @override
  void dispose() { ac.dispose(); pc.dispose(); super.dispose(); }

  Widget pg(String e, String t, String b, [Widget? x]) => Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Pulse(child: Text(e, style: const TextStyle(fontSize: 80))),
          const SizedBox(height: 16),
          Text(t, textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          Text(b, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, height: 1.9, color: Colors.white70)),
          if (x != null) ...[const SizedBox(height: 16), x],
        ]),
      );

  Widget dot(Color c) => Pulse(child: CircleAvatar(radius: 26, backgroundColor: c));

  Widget finale() => AnimatedBuilder(
        animation: ac,
        builder: (_, __) {
          Widget word(String t, int k, bool g) {
            final v = (ac.value * 9 - k).clamp(0.0, 1.0);
            Widget x = Text(t, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Colors.white));
            if (g) {
              x = ShaderMask(shaderCallback: (r) => const LinearGradient(colors: [kA, kB, kC]).createShader(r), child: x);
            }
            return Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 24 * (1 - v)), child: Transform.scale(scale: .6 + .4 * v, child: x)));
          }
          const w1 = ['ساخته', 'شده', 'با', '❤️'], w2 = ['برای', 'امیر', 'عباس'];
          return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Wrap(alignment: WrapAlignment.center, spacing: 10, children: [for (var k = 0; k < w1.length; k++) word(w1[k], k, false)]),
            const SizedBox(height: 12),
            Wrap(alignment: WrapAlignment.center, spacing: 10, children: [for (var k = 0; k < w2.length; k++) word(w2[k], k + 4, true)]),
          ]);
        },
      );

  @override
  Widget build(BuildContext c) {
    final pages = [
      pg('🚪', 'GadRail Project', 'یک پژوهش هوشمند با ESP32: سنسور فاصله را می‌خواند و دو در را باز می‌کند. این برنامه آن را از طریق بلوتوث کنترل می‌کند و بدون اینترنت کار می‌کند.'),
      pg('📡', 'چطور کار می‌کند؟', 'هرچه جسم نزدیک‌تر شود، چراغ سبز، زرد و قرمز (همراه بازر) روشن می‌شوند و در نهایت دو در باز می‌شوند. هر در با تاچ خودش می‌ایستد.',
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [dot(Colors.green), const SizedBox(width: 14), dot(Colors.amber), const SizedBox(width: 14), dot(Colors.redAccent)])),
      pg('🧭', 'راهنمای اتصال', '۱. ESP32 را روشن کنید\n۲. بلوتوث گوشی را روشن کنید\n۳. روی اندروید ۱۰ و ۱۱، «مکان» (Location) را هم روشن کنید\n۴. مجوزهای برنامه را تأیید کنید\n۵. در صفحه‌ی بعد دکمه‌ی «جستجو» را بزنید و GadRail را انتخاب کنید'),
      finale(),
    ];
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: PageView(
              controller: pc,
              onPageChanged: (n) { setState(() => i = n); if (n == 3) ac.forward(from: 0); },
              children: pages,
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var k = 0; k < 4; k++)
              AnimatedContainer(duration: const Duration(milliseconds: 300), margin: const EdgeInsets.all(4), width: k == i ? 26 : 8, height: 8,
                  decoration: BoxDecoration(color: k == i ? Colors.white : Colors.white24, borderRadius: BorderRadius.circular(8))),
          ]),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: kA, minimumSize: const Size.fromHeight(52)),
              onPressed: () => i < 3 ? pc.nextPage(duration: const Duration(milliseconds: 400), curve: Curves.easeOut) : widget.onDone(),
              child: Text(i < 3 ? 'بعدی' : 'ورود به برنامه', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ]),
      ),
    );
  }
}

class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key});
  @override
  State<ConnectPage> createState() => _ConnectState();
}

class _ConnectState extends State<ConnectPage> {
  List<ScanResult> res = [];
  String msg = '';
  bool busy = false;

  Future<void> scan() async {
    setState(() { busy = true; msg = 'در حال جستجو...'; res = []; });
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.locationWhenInUse].request();
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      setState(() { busy = false; msg = 'بلوتوث گوشی خاموش است. روشنش کنید.'; });
      return;
    }
    final sub = FlutterBluePlus.scanResults.listen((r) => setState(() => res = r));
    await FlutterBluePlus.startScan(withServices: [Guid(kSvc)], timeout: const Duration(seconds: 8));
    await FlutterBluePlus.isScanning.where((s) => !s).first;
    await sub.cancel();
    setState(() { busy = false; msg = res.isEmpty ? 'دستگاهی پیدا نشد. ESP32 روشن است؟ مجوزها و Location تأیید شده‌اند؟' : ''; });
  }

  Future<void> go(BluetoothDevice d) async {
    setState(() => msg = 'در حال اتصال...');
    try {
      await Ble.connect(d);
      if (!mounted) return;
      setState(() => msg = '');
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const Dash()));
    } catch (e) {
      msg = 'اتصال ناموفق بود. دوباره جستجو کنید.';
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(18), children: [
            const Text('GadRail Project', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            const Text('اتصال به دستگاه', style: TextStyle(color: Colors.white60)),
            const SizedBox(height: 16),
            Card(child: const Padding(padding: EdgeInsets.all(16), child: Text('قبل از جستجو:\n• ESP32 روشن باشد\n• بلوتوث گوشی روشن باشد\n• Location روشن باشد (اندروید ۱۰ و ۱۱)\n• مجوزها را تأیید کنید', style: TextStyle(height: 1.9)))),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: kA, minimumSize: const Size.fromHeight(52)),
              onPressed: busy ? null : scan, icon: const Icon(Icons.bluetooth_searching), label: const Text('جستجوی دستگاه')),
            if (msg.isNotEmpty) Padding(padding: const EdgeInsets.all(12), child: Text(msg, textAlign: TextAlign.center)),
            for (final r in res)
              Card(child: ListTile(leading: const Icon(Icons.memory, color: kB), title: Text(r.advertisementData.advName.isEmpty ? 'GadRail' : r.advertisementData.advName),
                  subtitle: Text('قدرت سیگنال: ${r.rssi}'), trailing: const Icon(Icons.chevron_left), onTap: () => go(r.device))),
            const SizedBox(height: 20),
            TextButton(onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => Intro(onDone: () => Navigator.pop(c)))), child: const Text('تماشای دوباره‌ی معرفی')),
            const Center(child: Text('ساخته شده با ❤️\nبرای امیر عباس', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54))),
          ]),
        ),
      );
}

class Dash extends StatefulWidget {
  const Dash({super.key});
  @override
  State<Dash> createState() => _DashState();
}

class _DashState extends State<Dash> {
  Timer? hb;
  StreamSubscription? cs;
  List<double>? cfg;
  bool snd = true;
  static const sn = ['در انتظار', 'سرووها در حال کار', 'پایان کار', 'در حال برگشت'];

  @override
  void initState() {
    super.initState();
    cs = Ble.dev!.connectionState.listen((s) { if (s == BluetoothConnectionState.disconnected && mounted) Navigator.pop(context); });
  }
  @override
  void dispose() { hb?.cancel(); cs?.cancel(); Ble.dev?.disconnect(); super.dispose(); }

  void rev(bool on) {
    hb?.cancel();
    Ble.send('REV ${on ? 1 : 0}');
    if (on) hb = Timer.periodic(const Duration(milliseconds: 300), (_) => Ble.send('REV 1'));
  }

  Widget sl(String t, int k, double mn, double mx) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$t: ${cfg![k].round()}'),
        Slider(value: cfg![k].clamp(mn, mx), min: mn, max: mx, onChanged: (x) => setState(() => cfg![k] = x)),
      ]);

  Widget servo(String t, String r, String d) => Expanded(
        child: Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
          Text(r == '1' ? '⚙️' : d == '1' ? '🛑' : '💤', style: const TextStyle(fontSize: 30)),
          Text(t), Text(r == '1' ? 'در حال چرخش' : d == '1' ? 'متوقف با تاچ' : 'آماده', style: const TextStyle(color: Colors.white60, fontSize: 12)),
        ]))),
      );

  @override
  Widget build(BuildContext c) => Scaffold(
        body: SafeArea(
          child: ValueListenableBuilder<List<String>>(
            valueListenable: Ble.data,
            builder: (c, v, _) {
              if (v.length < 13) return const Center(child: CircularProgressIndicator());
              final d = double.tryParse(v[0]) ?? 999;
              final n = [for (final x in v.sublist(7)) double.tryParse(x) ?? 0];
              cfg ??= [n[0], n[1], n[2], n[3], n[4], n[5]];
              final gx = n[0], gn = n[1], yn = n[2], rn = n[3];
              final z = d > gx ? ['بیرون محدوده', Colors.grey] : d >= gn ? ['منطقه سبز', Colors.green] : d >= yn ? ['منطقه زرد', Colors.amber] : d >= rn ? ['منطقه قرمز + بازر', Colors.redAccent] : ['درها باز می‌شوند', kA];
              final zc = z[1] as Color;
              return ListView(padding: const EdgeInsets.all(16), children: [
                const Text('GadRail Project', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                Text('🟢 متصل • ${sn[int.tryParse(v[1]) ?? 0]}', style: const TextStyle(color: Colors.white60)),
                const SizedBox(height: 16),
                Center(child: SizedBox(width: 220, height: 220, child: Stack(alignment: Alignment.center, children: [
                  SizedBox(width: 220, height: 220, child: CircularProgressIndicator(value: (1 - d / gx).clamp(0.0, 1.0), strokeWidth: 14, color: zc, backgroundColor: Colors.white12)),
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(d >= 900 ? '--' : d.toStringAsFixed(1), style: const TextStyle(fontSize: 46, fontWeight: FontWeight.bold)),
                    const Text('سانتی‌متر', style: TextStyle(color: Colors.white60)),
                    Text(z[0] as String, style: TextStyle(color: zc)),
                  ]),
                ]))),
                Row(children: [servo('سروو راست', v[2], v[4]), servo('سروو چپ', v[3], v[5])]),
                Row(children: [
                  Expanded(child: GestureDetector(onTapDown: (_) => rev(true), onTapUp: (_) => rev(false), onTapCancel: () => rev(false),
                      child: Container(height: 56, alignment: Alignment.center, decoration: BoxDecoration(gradient: const LinearGradient(colors: [kC, Color(0xFFE17055)]), borderRadius: BorderRadius.circular(16)),
                          child: const Text('⏪ برگشت (نگه دارید)', style: TextStyle(fontWeight: FontWeight.bold))))),
                  const SizedBox(width: 10),
                  Expanded(child: FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red[800], minimumSize: const Size.fromHeight(56)), onPressed: () => Ble.send('STOP'), child: const Text('⛔ توقف اضطراری'))),
                ]),
                const SizedBox(height: 8),
                Card(child: ExpansionTile(title: const Text('⚙️ تنظیمات'), childrenPadding: const EdgeInsets.all(16), children: [
                  sl('شروع سبز (cm)', 0, 10, 100), sl('شروع زرد (cm)', 1, 5, 90), sl('شروع قرمز و بازر (cm)', 2, 3, 80), sl('شروع سرووها (cm)', 3, 2, 60),
                  sl('تأخیر سروو چپ (ms)', 4, 500, 6000), sl('سرعت (%)', 5, 20, 100),
                  SwitchListTile(value: snd, title: const Text('بازر فعال باشد'), onChanged: (x) => setState(() => snd = x)),
                  FilledButton(style: FilledButton.styleFrom(backgroundColor: kA), onPressed: () {
                    final k = cfg!.map((e) => e.round()).toList();
                    if (!(k[0] > k[1] && k[1] > k[2] && k[2] > k[3])) {
                      ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('ترتیب باید سبز > زرد > قرمز > سرووها باشد')));
                      return;
                    }
                    Ble.send('SET ${k[0]} ${k[1]} ${k[2]} ${k[3]} ${k[4]} ${k[5]} ${snd ? 1 : 0}');
                    ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('✅ ذخیره شد')));
                  }, child: const Text('ذخیره روی دستگاه')),
                ])),
                const SizedBox(height: 16),
                const Center(child: Text('ساخته شده با ❤️\nبرای امیر عباس', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold))),
              ]);
            },
          ),
        ),
      );
}
