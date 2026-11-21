import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const String defaultRelayUrl = 'wss://vanish-relay-sawaira.bonto.page/ws';
const int vanishProtocolVersion = 1;
const double messageLifetimeSeconds = 30;

final ValueNotifier<int> vanishTheme = ValueNotifier<int>(0);

Future<void> changeVanishTheme() async {
  vanishTheme.value = (vanishTheme.value + 1) % 3;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt('vanish_theme', vanishTheme.value);
}

ThemeData buildVanishTheme(int index) {
  final light = index == 1;
  final seed = index == 2 ? const Color(0xFF39C99A) : const Color(0xFF9278F5);
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: light ? Brightness.light : Brightness.dark,
    surface: light ? const Color(0xFFF8F6FC) : const Color(0xFF191827),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: light ? Brightness.light : Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: light ? const Color(0xFFF8F6FC) : const Color(0xFF10101A),
    appBarTheme: AppBarTheme(
      backgroundColor: light ? const Color(0xFFF8F6FC) : const Color(0xFF10101A),
      foregroundColor: scheme.onSurface,
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: light ? Colors.white : const Color(0xFF201F30),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: scheme.outlineVariant.withOpacity(.45)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  vanishTheme.value = prefs.getInt('vanish_theme') ?? 0;
  final store = MessageStore();
  await store.open();
  runApp(VanishApp(store: store));
}

class VanishApp extends StatelessWidget {
  final MessageStore store;
  const VanishApp({super.key, required this.store});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: vanishTheme,
        builder: (context, index, _) => MaterialApp(
          title: 'Vanish',
          debugShowCheckedModeBanner: false,
          theme: buildVanishTheme(index),
          home: JoinPage(store: store),
        ),
      );
}

class ChatMessage {
  final String id, sender, text, deviceId;
  // These values are stored internally as Unix seconds. Protocol v1 uses ms
  // on the wire; conversion happens when a packet is received.
  final double sentAt, expiresAt;
  final bool mine;

  ChatMessage({
    required this.id,
    required this.sender,
    required this.text,
    required this.deviceId,
    required this.sentAt,
    required this.expiresAt,
    required this.mine,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'sender': sender,
        'text': text,
        'device_id': deviceId,
        'sent_at': sentAt,
        'expires_at': expiresAt,
        'mine': mine ? 1 : 0,
      };

  factory ChatMessage.fromMap(Map<String, Object?> m) => ChatMessage(
        id: m['id'] as String,
        sender: m['sender'] as String,
        text: m['text'] as String,
        deviceId: m['device_id'] as String,
        sentAt: (m['sent_at'] as num).toDouble(),
        expiresAt: (m['expires_at'] as num).toDouble(),
        mine: (m['mine'] as num) == 1,
      );
}

class PendingMessage {
  final String id, sender, text, deviceId;
  final double createdAt, expiresAt;

  PendingMessage(
    this.id,
    this.sender,
    this.text,
    this.deviceId,
    this.createdAt,
    this.expiresAt,
  );

  Map<String, Object?> toMap() => {
        'id': id,
        'sender': sender,
        'text': text,
        'device_id': deviceId,
        'created_at': createdAt,
        'expires_at': expiresAt,
      };
}

class MessageStore {
  Database? db;

  Future<void> open() async {
    final file = p.join(await getDatabasesPath(), 'vanish_messages.db');
    db = await openDatabase(
      file,
      version: 1,
      onCreate: (d, v) async {
        await d.execute(
          'CREATE TABLE messages(id TEXT PRIMARY KEY,sender TEXT NOT NULL,text TEXT NOT NULL,device_id TEXT NOT NULL,sent_at REAL NOT NULL,expires_at REAL NOT NULL,mine INTEGER NOT NULL)',
        );
        await d.execute(
          'CREATE TABLE pending(id TEXT PRIMARY KEY,sender TEXT NOT NULL,text TEXT NOT NULL,device_id TEXT NOT NULL,created_at REAL NOT NULL,expires_at REAL NOT NULL)',
        );
        await d.execute('CREATE TABLE processed_ids(id TEXT PRIMARY KEY)');
      },
    );
    // Expiry cleanup waits until the relay's welcome packet synchronizes the
    // phone clock offset; the phone's unsynchronized clock is not authoritative.
  }

  Future<void> deleteExpired(double serverNow, double localNow) async {
    await db!.delete('messages', where: 'expires_at <= ?', whereArgs: [serverNow]);
    // Pending messages have not reached the relay yet, so their 30-second
    // queue deadline is measured locally until they can be sent.
    await db!.delete('pending', where: 'expires_at <= ?', whereArgs: [localNow]);
  }

  Future<void> deleteMessage(String id) async {
    await db!.delete('messages', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<ChatMessage>> load(double serverNow, double localNow, {bool cleanExpired = true}) async {
    if (cleanExpired) await deleteExpired(serverNow, localNow);
    final rows = await db!.query('messages', orderBy: 'sent_at ASC');
    return rows.map(ChatMessage.fromMap).toList();
  }

  Future<Set<String>> ownMessageIds() async {
    final sent = await db!.query('messages', columns: ['id'], where: 'mine = 1');
    final queued = await db!.query('pending', columns: ['id']);
    return {
      ...sent.map((row) => row['id'] as String),
      ...queued.map((row) => row['id'] as String),
    };
  }

  Future<bool> processed(String id) async =>
      (await db!.query('processed_ids', where: 'id = ?', whereArgs: [id], limit: 1)).isNotEmpty;

  Future<void> markProcessed(String id) async => db!.insert(
        'processed_ids',
        {'id': id},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

  Future<void> save(ChatMessage message) async => db!.insert(
        'messages',
        message.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

  Future<void> queue(PendingMessage message) async => db!.insert(
        'pending',
        message.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

  Future<List<PendingMessage>> queued() async {
    final rows = await db!.query('pending', orderBy: 'created_at ASC');
    return rows
        .map((m) => PendingMessage(
              m['id'] as String,
              m['sender'] as String,
              m['text'] as String,
              m['device_id'] as String,
              (m['created_at'] as num).toDouble(),
              (m['expires_at'] as num).toDouble(),
            ))
        .toList();
  }

  Future<void> removePending(String id) async {
    await db!.delete('pending', where: 'id = ?', whereArgs: [id]);
  }
}

class JoinPage extends StatefulWidget {
  final MessageStore store;
  const JoinPage({super.key, required this.store});

  @override
  State<JoinPage> createState() => _JoinPageState();
}

class _JoinPageState extends State<JoinPage> {
  final name = TextEditingController();
  final relay = TextEditingController(text: defaultRelayUrl);
  bool busy = false;

  Future<void> join() async {
    final displayName = name.text.trim();
    final relayAddress = relay.text.trim();
    if (displayName.isEmpty || displayName.length > 30 || relayAddress.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a name (1–30 characters) and relay address.')),
      );
      return;
    }
    final uri = Uri.tryParse(relayAddress);
    if (uri == null || (uri.scheme != 'wss' && uri.scheme != 'ws') || uri.host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid ws:// or wss:// relay address.')),
      );
      return;
    }

    setState(() => busy = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final device = prefs.getString('device_id') ?? const Uuid().v4();
      await prefs.setString('device_id', device);
      await prefs.setString('display_name', displayName);
      await prefs.setString('relay_url', relayAddress);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatPage(
            store: widget.store,
            name: displayName,
            deviceId: device,
            relayUrl: relayAddress,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    name.dispose();
    relay.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      body: Stack(children: [
        Positioned(
          top: -90, right: -90,
          child: Container(width: 270, height: 270,
            decoration: BoxDecoration(shape: BoxShape.circle, color: t.colorScheme.primary.withOpacity(.12))),
        ),
        SafeArea(child: Center(child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Align(alignment: Alignment.centerRight,
                child: IconButton(tooltip: 'Change theme', onPressed: changeVanishTheme, icon: const Icon(Icons.palette_outlined))),
              const SizedBox(height: 10),
              Center(child: Container(width: 88, height: 88,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: LinearGradient(colors: [t.colorScheme.primary, t.colorScheme.tertiary]),
                  boxShadow: [BoxShadow(color: t.colorScheme.primary.withOpacity(.28), blurRadius: 28, offset: const Offset(0, 12))],
                ),
                child: const Icon(Icons.hourglass_bottom_rounded, size: 44, color: Colors.white))),
              const SizedBox(height: 22),
              Text('VANISH', textAlign: TextAlign.center,
                style: t.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: 5)),
              const SizedBox(height: 8),
              Text('Say it. Share it. Let it disappear.', textAlign: TextAlign.center,
                style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurface.withOpacity(.62))),
              const SizedBox(height: 34),
              Container(padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: t.colorScheme.surface, borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: t.colorScheme.outlineVariant.withOpacity(.35)),
                  boxShadow: [if (t.brightness == Brightness.light) BoxShadow(color: Colors.black.withOpacity(.05), blurRadius: 24, offset: const Offset(0, 10))],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Join your class', style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text('Connect to the shared class network.', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurface.withOpacity(.6))),
                  const SizedBox(height: 22),
                  TextField(controller: name, maxLength: 30, textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Your display name', prefixIcon: Icon(Icons.person_outline_rounded), counterText: '')),
                  const SizedBox(height: 14),
                  TextField(controller: relay, keyboardType: TextInputType.url,
                    decoration: const InputDecoration(labelText: 'Relay address', prefixIcon: Icon(Icons.hub_outlined))),
                  const SizedBox(height: 16),
                  Row(children: [
                    Icon(Icons.verified_user_outlined, size: 16, color: t.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text('Class-approved Protocol v1', style: t.textTheme.labelMedium?.copyWith(color: t.colorScheme.onSurface.withOpacity(.65))),
                  ]),
                  const SizedBox(height: 22),
                  SizedBox(height: 54, child: FilledButton(
                    onPressed: busy ? null : join,
                    style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17))),
                    child: busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text('Enter Vanish', style: TextStyle(fontWeight: FontWeight.w700)),
                          SizedBox(width: 10), Icon(Icons.arrow_forward_rounded, size: 19),
                        ]),
                  )),
                ])),
              const SizedBox(height: 22),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.timer_outlined, size: 15, color: t.colorScheme.primary),
                const SizedBox(width: 7),
                Text('Every message disappears after 30 seconds', style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurface.withOpacity(.58))),
              ]),
            ]),
          ),
        ))),
      ]),
    );
  }
}

class ChatPage extends StatefulWidget {
  final MessageStore store;
  final String name, deviceId, relayUrl;

  const ChatPage({
    super.key,
    required this.store,
    required this.name,
    required this.deviceId,
    required this.relayUrl,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  final input = TextEditingController();
  final scroll = ScrollController();
  final uuid = const Uuid();
  final List<ChatMessage> messages = [];
  final Set<String> ownIds = <String>{};

  WebSocketChannel? channel;
  StreamSubscription? subscription;
  Timer? ticker, heartbeat, retry;
  bool connected = false, connecting = false;
  bool retryScheduled = false;
  bool clockSynced = false;
  String status = 'Connecting…';
  double clockOffsetSeconds = 0;
  DateTime? lastPongAt;
  int retryAttempt = 0;
  int connectionGeneration = 0;

  // This is estimated server time in Unix seconds, based on the offset from
  // the welcome packet. Protocol timestamps arrive in milliseconds.
  double get localNowSeconds => DateTime.now().millisecondsSinceEpoch / 1000.0;
  double get serverNowSeconds => localNowSeconds + clockOffsetSeconds;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load(cleanExpired: false).then((_) {
      if (mounted) connect();
    });
    ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => tick());
  }

  Future<void> load({bool cleanExpired = true}) async {
    ownIds.addAll(await widget.store.ownMessageIds());
    final data = await widget.store.load(serverNowSeconds, localNowSeconds, cleanExpired: cleanExpired);
    if (mounted) setState(() => messages..clear()..addAll(data));
  }

  Future<void> tick() async {
    if (clockSynced) {
      await widget.store.deleteExpired(serverNowSeconds, localNowSeconds);
      if (mounted) {
        setState(() => messages.removeWhere((m) => m.expiresAt <= serverNowSeconds));
      }
    }
    final pong = lastPongAt;
    if (connected && pong != null && DateTime.now().difference(pong) >= const Duration(seconds: 30)) {
      _handleDisconnect(connectionGeneration);
    }
  }

  void connect() {
    if (connecting || connected || !mounted) return;
    connecting = true;
    final generation = ++connectionGeneration;
    try {
      final newChannel = WebSocketChannel.connect(Uri.parse(widget.relayUrl));
      channel = newChannel;
      subscription = newChannel.stream.listen(
        (packet) => onPacket(packet, generation),
        onError: (_) => _handleDisconnect(generation),
        onDone: () => _handleDisconnect(generation),
        cancelOnError: true,
      );
      newChannel.ready.then((_) {
        if (!mounted || generation != connectionGeneration) return;
        newChannel.sink.add(jsonEncode({
          'type': 'join',
          'protocol': vanishProtocolVersion,
          'device_id': widget.deviceId,
          'name': widget.name,
        }));
      }).catchError((_) => _handleDisconnect(generation));
    } catch (_) {
      _handleDisconnect(generation);
    }
  }

  void _handleDisconnect(int generation) {
    if (!mounted || generation != connectionGeneration || retryScheduled) return;
    connected = false;
    connecting = false;
    lastPongAt = null;
    heartbeat?.cancel();
    subscription?.cancel();
    channel?.sink.close();
    channel = null;
    setState(() => status = 'Disconnected • retrying');
    retryScheduled = true;
    const delays = [1, 2, 4, 8];
    final delayIndex = retryAttempt < delays.length ? retryAttempt : delays.length - 1;
    final seconds = delays[delayIndex];
    if (retryAttempt < delays.length - 1) retryAttempt++;
    retry = Timer(Duration(seconds: seconds), () {
      retry = null;
      retryScheduled = false;
      connect();
    });
  }

  Future<void> onPacket(dynamic raw, int generation) async {
    if (generation != connectionGeneration) return;
    try {
      final packet = jsonDecode(raw as String) as Map<String, dynamic>;
      switch (packet['type']) {
        case 'welcome':
          if (packet['protocol'] != vanishProtocolVersion || packet['server_time'] is! num) {
            show('The relay returned an unsupported protocol response.');
            _handleDisconnect(generation);
            return;
          }
          final phoneTimeMs = DateTime.now().millisecondsSinceEpoch;
          final serverTimeMs = (packet['server_time'] as num).toDouble();
          clockOffsetSeconds = (serverTimeMs - phoneTimeMs) / 1000.0;
          clockSynced = true;
          await load();
          connected = true;
          connecting = false;
          retryAttempt = 0;
          retry?.cancel();
          retry = null;
          retryScheduled = false;
          lastPongAt = DateTime.now();
          if (mounted) setState(() => status = 'Connected to class relay');
          heartbeat?.cancel();
          heartbeat = Timer.periodic(const Duration(seconds: 15), (_) {
            if (connected && generation == connectionGeneration) {
              channel?.sink.add(jsonEncode({'type': 'ping'}));
            }
          });
          await flushQueue();
          break;

        case 'pong':
          lastPongAt = DateTime.now();
          break;

        case 'message':
          final id = packet['id'];
          final sender = packet['sender'];
          final text = packet['text'];
          final sentAtMs = packet['sent_at'];
          final expiresAtMs = packet['expires_at'];
          if (id is! String || sender is! String || text is! String ||
              sentAtMs is! num || expiresAtMs is! num) {
            return;
          }
          // Convert protocol milliseconds to internal Unix seconds.
          final sentAt = sentAtMs.toDouble() / 1000.0;
          final expiresAt = expiresAtMs.toDouble() / 1000.0;
          if (expiresAt <= serverNowSeconds || await widget.store.processed(id)) return;
          await widget.store.markProcessed(id);
          final mine = ownIds.contains(id);
          final message = ChatMessage(
            id: id,
            sender: sender,
            text: text,
            deviceId: mine ? widget.deviceId : '',
            sentAt: sentAt,
            expiresAt: expiresAt,
            mine: mine,
          );
          await widget.store.save(message);
          if (mounted) {
            setState(() => messages.add(message));
            jumpBottom();
          }
          // Protocol v1 does not define a client-to-relay delivered packet.
          // The relay sends `delivered` to the sender itself.
          break;

        case 'delivered':
          final count = packet['count'];
          if (count is num) show('Delivered to ${count.toInt()} joined app(s).');
          break;

        case 'expired':
          final id = packet['id'];
          if (id is String) {
            await widget.store.deleteMessage(id);
            if (mounted) setState(() => messages.removeWhere((m) => m.id == id));
          }
          break;

        case 'error':
          final code = packet['code']?.toString() ?? 'unknown';
          final message = packet['message']?.toString() ?? 'Relay error';
          show('$code: $message');
          break;
      }
    } catch (_) {
      // Ignore malformed packets; the relay connection remains available.
    }
  }

  Future<void> flushQueue() async {
    for (final item in await widget.store.queued()) {
      if (item.expiresAt <= localNowSeconds) {
        await widget.store.removePending(item.id);
        ownIds.remove(item.id);
      } else {
        _sendMessagePacket(item.id, item.text);
        await widget.store.removePending(item.id);
      }
    }
  }

  void _sendMessagePacket(String id, String text) {
    // Protocol v1 message packets are flat. Include the joined display name;
    // the relay treats the name from JOIN as authoritative and assigns times.
    channel?.sink.add(jsonEncode({
      'type': 'message',
      'id': id,
      'sender': widget.name,
      'text': text,
    }));
  }

  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty) return;
    if (text.runes.length > 500) {
      show('Messages can contain at most 500 characters.');
      return;
    }
    input.clear();
    final id = uuid.v4();
    ownIds.add(id);
    final created = localNowSeconds;
    if (connected) {
      _sendMessagePacket(id, text);
    } else {
      await widget.store.queue(PendingMessage(
        id,
        widget.name,
        text,
        widget.deviceId,
        created,
        created + messageLifetimeSeconds,
      ));
      show('Offline: queued for up to 30 seconds.');
    }
  }

  void show(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
      );
    }
  }

  void jumpBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) {
          scroll.animateTo(
            scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });

  void manualReconnect() {
    retry?.cancel();
    retry = null;
    retryScheduled = false;
    retryAttempt = 0;
    connectionGeneration++;
    heartbeat?.cancel();
    subscription?.cancel();
    channel?.sink.close();
    channel = null;
    connected = false;
    connecting = false;
    lastPongAt = null;
    clockSynced = false;
    if (mounted) setState(() => status = 'Connecting…');
    connect();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) load(cleanExpired: clockSynced);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ticker?.cancel();
    heartbeat?.cancel();
    retry?.cancel();
    subscription?.cancel();
    channel?.sink.close();
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    final light = t.brightness == Brightness.light;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 4,
        title: Row(children: [
          Container(width: 42, height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(colors: [scheme.primary, scheme.tertiary]),
            ),
            child: const Icon(Icons.hourglass_bottom_rounded, color: Colors.white, size: 23)),
          const SizedBox(width: 11),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Vanish class chat', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            Row(children: [
              Container(width: 7, height: 7, decoration: BoxDecoration(
                shape: BoxShape.circle, color: connected ? const Color(0xFF35C98A) : Colors.orange)),
              const SizedBox(width: 6),
              Flexible(child: Text(status, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurface.withOpacity(.62)))),
            ]),
          ])),
        ]),
        actions: [
          IconButton(tooltip: 'Change appearance', onPressed: changeVanishTheme, icon: const Icon(Icons.palette_outlined)),
          PopupMenuButton<String>(
            tooltip: 'Chat options',
            onSelected: (v) {
              if (v == 'reconnect') manualReconnect();
              if (v == 'theme') changeVanishTheme();
              if (v == 'info') show('Relay: ${widget.relayUrl}\\nProtocol v1 • 30-second expiry');
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'reconnect', child: ListTile(leading: Icon(Icons.refresh), title: Text('Reconnect'))),
              PopupMenuItem(value: 'theme', child: ListTile(leading: Icon(Icons.palette_outlined), title: Text('Change theme'))),
              PopupMenuItem(value: 'info', child: ListTile(leading: Icon(Icons.info_outline), title: Text('Network information'))),
            ],
          ),
        ],
      ),
      body: Column(children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: scheme.primary.withOpacity(light ? .08 : .12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.primary.withOpacity(.16)),
          ),
          child: Row(children: [
            Icon(Icons.auto_delete_outlined, color: scheme.primary, size: 19),
            const SizedBox(width: 10),
            Expanded(child: Text('Ephemeral chat · Messages vanish after 30 seconds',
              style: t.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600))),
            Icon(Icons.lock_outline_rounded, size: 16, color: scheme.primary.withOpacity(.8)),
          ]),
        ),
        Expanded(child: messages.isEmpty
          ? Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(
              mainAxisSize: MainAxisSize.min, children: [
                Container(width: 88, height: 88,
                  decoration: BoxDecoration(color: scheme.primary.withOpacity(.10), shape: BoxShape.circle),
                  child: Icon(Icons.forum_outlined, size: 40, color: scheme.primary)),
                const SizedBox(height: 18),
                Text('The conversation starts here', textAlign: TextAlign.center,
                  style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 7),
                Text('Send a message to everyone connected to your class relay.',
                  textAlign: TextAlign.center,
                  style: t.textTheme.bodySmall?.copyWith(color: scheme.onSurface.withOpacity(.58))),
                const SizedBox(height: 18),
                Container(padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                  decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(30)),
                  child: Text(connected ? 'You are connected' : 'Waiting for connection',
                    style: t.textTheme.labelSmall?.copyWith(color: connected ? const Color(0xFF35B982) : scheme.onSurface.withOpacity(.6)))),
              ],
            )))
          : ListView.builder(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
              itemCount: messages.length,
              itemBuilder: (_, i) {
                final m = messages[i];
                final remaining = (m.expiresAt - serverNowSeconds).clamp(0, 30).ceil();
                final progress = (remaining / 30).clamp(0.0, 1.0);
                return Align(
                  alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 330),
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.fromLTRB(15, 12, 15, 11),
                    decoration: BoxDecoration(
                      gradient: m.mine ? LinearGradient(
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [scheme.primary, Color.lerp(scheme.primary, scheme.tertiary, .45)!],
                      ) : null,
                      color: m.mine ? null : scheme.surface,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(21), topRight: const Radius.circular(21),
                        bottomLeft: Radius.circular(m.mine ? 21 : 6),
                        bottomRight: Radius.circular(m.mine ? 6 : 21),
                      ),
                      border: m.mine ? null : Border.all(color: scheme.outlineVariant.withOpacity(.35)),
                      boxShadow: [if (light) BoxShadow(color: Colors.black.withOpacity(.035), blurRadius: 12, offset: const Offset(0, 4))],
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (!m.mine) Padding(padding: const EdgeInsets.only(bottom: 5),
                        child: Text(m.sender, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: scheme.primary))),
                      Text(m.text, style: TextStyle(fontSize: 15, height: 1.35, color: m.mine ? Colors.white : scheme.onSurface)),
                      const SizedBox(height: 11),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.hourglass_bottom_rounded, size: 13,
                          color: m.mine ? Colors.white70 : scheme.onSurface.withOpacity(.55)),
                        const SizedBox(width: 5),
                        Text('${remaining}s left', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                          color: remaining <= 5 ? Colors.orange : (m.mine ? Colors.white70 : scheme.onSurface.withOpacity(.55)))),
                        const SizedBox(width: 9),
                        SizedBox(width: 48, child: ClipRRect(borderRadius: BorderRadius.circular(5),
                          child: LinearProgressIndicator(value: progress, minHeight: 3,
                            backgroundColor: m.mine ? Colors.white24 : scheme.onSurface.withOpacity(.10),
                            valueColor: AlwaysStoppedAnimation<Color>(remaining <= 5 ? Colors.orange : (m.mine ? Colors.white : scheme.primary))))),
                      ]),
                    ]),
                  ),
                );
              },
            )),
        SafeArea(top: false, child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          decoration: BoxDecoration(
            color: t.scaffoldBackgroundColor,
            border: Border(top: BorderSide(color: scheme.outlineVariant.withOpacity(.28))),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(child: TextField(
              controller: input, minLines: 1, maxLines: 4, maxLength: 500,
              textInputAction: TextInputAction.send, onSubmitted: (_) => send(),
              decoration: InputDecoration(
                hintText: 'Write something…', counterText: '',
                prefixIcon: Icon(Icons.edit_outlined, color: scheme.primary),
                filled: true, fillColor: scheme.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: scheme.outlineVariant.withOpacity(.3))),
              ),
            )),
            const SizedBox(width: 9),
            SizedBox(width: 52, height: 52, child: FilledButton(
              onPressed: send, style: FilledButton.styleFrom(
                padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
              child: const Icon(Icons.send_rounded, size: 21),
            )),
          ]),
        )),
      ]),
    );
  }
}
