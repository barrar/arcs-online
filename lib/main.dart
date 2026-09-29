import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';

import 'firebase_options.dart';
import 'game_page.dart';
import 'services.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) usePathUrlStrategy();
  try {
    await Firebase.initializeApp(options: ArcsFirebaseOptions.current);
    if (const bool.fromEnvironment('USE_EMULATORS')) {
      final host = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? '10.0.2.2'
          : 'localhost';
      await FirebaseAuth.instance.useAuthEmulator(host, 9099);
      FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
      FirebaseFunctions.instanceFor(region: 'us-west1')
          .useFunctionsEmulator(host, 5001);
    }
    if (kIsWeb && const String.fromEnvironment('FCM_VAPID_KEY').isNotEmpty) {
      FirebaseMessaging.onMessage.listen((message) {
        messengerKey.currentState?.showSnackBar(SnackBar(
          content: Text(message.notification?.body ?? 'Your ARCS table has an update.'),
        ));
      });
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        final gameId = message.data['gameId'];
        if (gameId != null) router.go('/game/$gameId');
      });
    }
    runApp(const ArcsApp());
  } catch (error) {
    runApp(
      MaterialApp(
        theme: arcsTheme(),
        home: Scaffold(
          body: Center(
            child: Text('ARCS could not initialize Firebase: $error'),
          ),
        ),
      ),
    );
  }
}

final service = ArcsService();
final messengerKey = GlobalKey<ScaffoldMessengerState>();
final router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, _) => const HomePage()),
    GoRoute(
      path: '/lobby/:id',
      builder: (_, state) => LobbyPage(lobbyId: state.pathParameters['id']!),
    ),
    GoRoute(path: '/game/:id', builder: (_, state) =>
      GamePage(key: ValueKey(state.pathParameters['id']!),
        gameId: state.pathParameters['id']!, service: service)),
    GoRoute(
      path: '/join/:code',
      builder: (_, state) => JoinLinkPage(code: state.pathParameters['code']!),
    ),
  ],
);

class ArcsApp extends StatelessWidget {
  const ArcsApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'ARCS Online',
    debugShowCheckedModeBanner: false,
    theme: arcsTheme(),
    routerConfig: router,
    scaffoldMessengerKey: messengerKey,
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<User> _guest = service.ensureGuest();
  bool _enablingTurnAlerts = false;
  @override
  Widget build(BuildContext context) => FutureBuilder<User>(
    future: _guest,
    builder: (context, snapshot) => Scaffold(
      body: SpaceBackdrop(
        child: SafeArea(
          child: snapshot.hasError
              ? _guestUnavailable(context)
              : !snapshot.hasData
              ? const Center(child: CircularProgressIndicator())
              : _home(context, snapshot.data!),
        ),
      ),
    ),
  );

  Widget _guestUnavailable(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 900),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const _Logo(),
          const SizedBox(height: 72),
          const Text(
            'THE REACH AWAITS',
            style: TextStyle(
              color: cyan,
              letterSpacing: 3,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Explore the edge\nof the galaxy.',
            style: Theme.of(context).textTheme.displayLarge
                ?.copyWith(fontSize: 46, height: 1.05),
          ),
          const SizedBox(height: 26),
          const GlassPanel(
            child: Row(
              children: [
                Icon(Icons.cloud_off, color: gold),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Online lobbies are temporarily unavailable. Check your connection and retry.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              TextButton.icon(
                onPressed: () => setState(() => _guest = service.ensureGuest()),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry online play'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _home(BuildContext context, User user) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1220),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 42),
        children: [
          Row(
            children: [
              const _Logo(),
              const Spacer(),
              if (const String.fromEnvironment('FCM_VAPID_KEY').isNotEmpty)
                TextButton.icon(
                  onPressed: _enablingTurnAlerts ? null : () async {
                    setState(() => _enablingTurnAlerts = true);
                    try {
                      await service.enableTurnAlerts();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Turn alerts enabled on this browser.')));
                      }
                    } catch (error) {
                      if (context.mounted) await _showError(context, error);
                    } finally {
                      if (mounted) setState(() => _enablingTurnAlerts = false);
                    }
                  },
                  icon: _enablingTurnAlerts ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.notifications_active_outlined),
                  label: const Text('Enable turn alerts'),
                ),
              TextButton.icon(
                onPressed: () async {
                  await _accountDialog(context);
                  if (mounted) setState(() => _guest = service.ensureGuest());
                },
                icon: const Icon(Icons.person_outline),
                label: Text(
                  user.isAnonymous ? 'Guest account' : service.defaultName,
                ),
              ),
            ],
          ),
          const SizedBox(height: 38),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 760;
              final heading = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'THE REACH AWAITS',
                    style: TextStyle(
                      color: cyan,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Rule the edge\nof the galaxy.',
                    style: Theme.of(context).textTheme.displayLarge
                        ?.copyWith(fontSize: wide ? 55 : 41, height: 1.04),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'A shared tabletop for the ARCS base game. Create a private table or meet players in a public lobby.',
                    style: TextStyle(color: muted, fontSize: 17, height: 1.5),
                  ),
                  const SizedBox(height: 26),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _createDialog(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Create lobby'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _joinDialog(context),
                        icon: const Icon(Icons.link),
                        label: const Text('Join by code'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
              );
              return Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: heading,
                ),
              );
            },
          ),
          const SizedBox(height: 38),
          Text('OPEN TABLES', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: service.publicLobbies(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return GlassPanel(
                  child: Text(
                    'Could not load public lobbies: ${snapshot.error}',
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(36),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final lobbies = snapshot.data!.docs;
              if (lobbies.isEmpty) {
                return const GlassPanel(
                  child: Row(
                    children: [
                      Icon(Icons.radar, color: cyan),
                      SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'No public tables are waiting. Create one to open the Reach.',
                        ),
                      ),
                    ],
                  ),
                );
              }
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: lobbies.map((doc) {
                  final data = doc.data();
                  final seats = (data['seats'] as List?)?.length ?? 0;
                  final timer = (data['timer'] as Map?) ?? {};
                  return SizedBox(
                    width: 345,
                    child: GlassPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${data['name'] ?? 'Untitled table'}',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '$seats / ${data['maxPlayers']} players   •   ${_timerLabel(timer)}',
                            style: const TextStyle(color: muted),
                          ),
                          const SizedBox(height: 18),
                          OutlinedButton(
                            onPressed: () =>
                                _joinCode(context, '${data['code']}'),
                            child: const Text('Join table'),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 30),
          Text('YOUR GAMES', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: service.myGames(user.uid),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return GlassPanel(
                  child: Text('Could not load games: ${snapshot.error}'),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.data!.docs.isEmpty) {
                return const GlassPanel(
                  child: Text(
                    'Your active and completed games will appear here.',
                    style: TextStyle(color: muted),
                  ),
                );
              }
              return Column(
                children: snapshot.data!.docs
                    .map(
                      (doc) => ListTile(
                        title: Text(doc.data()['name'] ?? 'ARCS game'),
                        subtitle: Text(doc.data()['status'] ?? ''),
                        onTap: () => context.go('/game/${doc.id}'),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    ),
  );
}

String _timerLabel(Map timer) => timer['mode'] == 'live'
    ? '${timer['minutes']} min live'
    : '${timer['hours']} hr async';

class _Logo extends StatelessWidget {
  const _Logo();
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: gold, width: 2),
        ),
        child: const Icon(Icons.auto_awesome, color: gold, size: 16),
      ),
      const SizedBox(width: 9),
      const Text(
        'ARCS',
        style: TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w900,
          letterSpacing: 4,
        ),
      ),
      const Text(
        ' / ONLINE',
        style: TextStyle(
          color: muted,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
        ),
      ),
    ],
  );
}

Future<void> _showError(BuildContext context, Object error) async {
  if (!context.mounted) return;
  final message = error is FirebaseFunctionsException
      ? error.message ?? error.code
      : error.toString();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<void> _createDialog(BuildContext context) async {
  final name = TextEditingController(text: 'A new chapter');
  final displayName = TextEditingController(text: service.defaultName);
  var visibility = 'public';
  var players = 4;
  var mode = 'live';
  var minutes = 5;
  var hours = 48;
  var isCreating = false;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('Create a table'),
        content: SizedBox(
          width: 430,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Table name'),
                  maxLength: 60,
                ),
                TextField(
                  controller: displayName,
                  decoration: const InputDecoration(labelText: 'Your name'),
                  maxLength: 32,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: visibility,
                  decoration: const InputDecoration(labelText: 'Visibility'),
                  items: const [
                    DropdownMenuItem(
                      value: 'public',
                      child: Text('Public lobby'),
                    ),
                    DropdownMenuItem(
                      value: 'private',
                      child: Text('Private invite'),
                    ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => visibility = value!),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: players,
                  decoration: const InputDecoration(labelText: 'Seats'),
                  items: [2, 3, 4]
                      .map(
                        (n) => DropdownMenuItem(
                          value: n,
                          child: Text('$n players'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setDialogState(() => players = value!),
                ),
                const SizedBox(height: 16),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'live', label: Text('Live')),
                    ButtonSegment(value: 'async', label: Text('Async')),
                  ],
                  selected: {mode},
                  onSelectionChanged: (values) =>
                      setDialogState(() => mode = values.first),
                ),
                const SizedBox(height: 16),
                if (mode == 'live')
                  DropdownButtonFormField<int>(
                    initialValue: minutes,
                    decoration: const InputDecoration(labelText: 'Turn timer'),
                    items: [
                      for (var i = 2; i <= 10; i++)
                        DropdownMenuItem(value: i, child: Text('$i minutes')),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => minutes = value!),
                  )
                else
                  DropdownButtonFormField<int>(
                    initialValue: hours,
                    decoration: const InputDecoration(labelText: 'Turn timer'),
                    items: const [
                      DropdownMenuItem(value: 24, child: Text('24 hours')),
                      DropdownMenuItem(value: 48, child: Text('48 hours')),
                    ],
                    onChanged: (value) => setDialogState(() => hours = value!),
                  ),
                const SizedBox(height: 10),
                const Text(
                  'An overdue player can be kicked if every other player agrees. Kicking ends the match.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: isCreating ? null : () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: isCreating
                ? null
                : () async {
                    setDialogState(() => isCreating = true);
                    try {
                      final id = await service.createLobby(
                        name: name.text,
                        displayName: displayName.text,
                        visibility: visibility,
                        maxPlayers: players,
                        timer: mode == 'live'
                            ? {'mode': 'live', 'minutes': minutes}
                            : {'mode': 'async', 'hours': hours},
                      );
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                      if (context.mounted) context.go('/lobby/$id');
                    } catch (error) {
                      if (dialogContext.mounted) {
                        await _showError(dialogContext, error);
                      }
                    } finally {
                      if (dialogContext.mounted) {
                        setDialogState(() => isCreating = false);
                      }
                    }
                  },
            child: isCreating
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Creating...'),
                    ],
                  )
                : const Text('Create'),
          ),
        ],
      ),
    ),
  );
  name.dispose();
  displayName.dispose();
}

Future<void> _joinDialog(BuildContext context) async {
  final code = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Join a table'),
      content: SizedBox(
        width: 340,
        child: TextField(
          controller: code,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Eight-character invite code',
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            final value = code.text;
            Navigator.pop(dialogContext);
            if (context.mounted) await _joinCode(context, value);
          },
          child: const Text('Join'),
        ),
      ],
    ),
  );
  code.dispose();
}

Future<void> _joinCode(BuildContext context, String code) async {
  try {
    final id = await service.joinLobby(code, service.defaultName);
    if (context.mounted) context.go('/lobby/$id');
  } catch (error) {
    if (context.mounted) await _showError(context, error);
  }
}

class JoinLinkPage extends StatefulWidget {
  const JoinLinkPage({required this.code, super.key});
  final String code;
  @override
  State<JoinLinkPage> createState() => _JoinLinkPageState();
}

class _JoinLinkPageState extends State<JoinLinkPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await service.ensureGuest();
        if (mounted) await _joinCode(context, widget.code);
      } catch (error) {
        if (mounted) await _showError(context, error);
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SpaceBackdrop(
      child: Center(
        child: GlassPanel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text('Joining ${widget.code}...'),
              TextButton(
                onPressed: () => context.go('/'),
                child: const Text('Back to lobby list'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class LobbyPage extends StatefulWidget {
  const LobbyPage({required this.lobbyId, super.key});
  final String lobbyId;

  @override
  State<LobbyPage> createState() => _LobbyPageState();
}

class _LobbyPageState extends State<LobbyPage> {
  bool _updatingReady = false;
  bool _starting = false;
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _lobbyStream;

  @override
  void initState() {
    super.initState();
    _lobbyStream = service.lobby(widget.lobbyId);
  }

  @override
  void didUpdateWidget(covariant LobbyPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lobbyId != widget.lobbyId) {
      _lobbyStream = service.lobby(widget.lobbyId);
      _updatingReady = false;
      _starting = false;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SpaceBackdrop(
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 850),
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _lobbyStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Could not load lobby: ${snapshot.error}'),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.data!.exists) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Lobby not found'),
                        TextButton(
                          onPressed: () => context.go('/'),
                          child: const Text('Back'),
                        ),
                      ],
                    ),
                  );
                }
                final data = snapshot.data!.data()!;
                final seats = (data['seats'] as List).cast<Map>();
                final uid = service.auth.currentUser?.uid;
                final me = seats
                    .where((seat) => seat['uid'] == uid)
                    .firstOrNull;
                final host = data['hostId'] == uid;
                final canStart = host && seats.length >= 2 &&
                    seats.every((seat) => seat['ready'] == true) && data['status'] == 'waiting';
                return ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => context.go('/'),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('All tables'),
                      ),
                    ),
                    const SizedBox(height: 15),
                    GlassPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'GATHER YOUR CREW',
                            style: TextStyle(
                              color: cyan,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 3,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${data['name']}',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${data['visibility'] == 'private' ? 'Private' : 'Public'} • ${_timerLabel((data['timer'] as Map))} • ${seats.length}/${data['maxPlayers']} seats',
                            style: const TextStyle(color: muted),
                          ),
                          const SizedBox(height: 22),
                          Row(
                            children: [
                              const Icon(Icons.link, color: gold),
                              const SizedBox(width: 10),
                              SelectableText(
                                '${data['code']}',
                                style: const TextStyle(
                                  color: gold,
                                  fontSize: 25,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 4,
                                ),
                              ),
                              const SizedBox(width: 12),
                              IconButton(
                                tooltip: 'Copy invitation link',
                                onPressed: () async {
                                  await Clipboard.setData(
                                    ClipboardData(
                                      text:
                                          '${Uri.base.origin}/join/${data['code']}',
                                    ),
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Invite link copied'),
                                      ),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.copy),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          for (final seat in seats)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 7),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 15,
                                    backgroundColor: _seatColor(
                                      '${seat['color']}',
                                    ),
                                    child: const Icon(
                                      Icons.star,
                                      size: 15,
                                      color: voidBlack,
                                    ),
                                  ),
                                  const SizedBox(width: 13),
                                  Expanded(
                                    child: Text(
                                      '${seat['name']}',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  if (seat['uid'] == data['hostId'])
                                    const Padding(
                                      padding: EdgeInsets.only(right: 12),
                                      child: Text(
                                        'HOST',
                                        style: TextStyle(
                                          color: gold,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  Text(
                                    seat['ready'] == true ? 'READY' : 'WAITING',
                                    style: TextStyle(
                                      color: seat['ready'] == true
                                          ? cyan
                                          : muted,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const Divider(height: 30),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              if (me != null)
                                ElevatedButton(
                                  onPressed: _updatingReady
                                      ? null
                                      : () async {
                                          setState(() => _updatingReady = true);
                                          try {
                                            await service.setReady(
                                              widget.lobbyId,
                                              me['ready'] != true,
                                            );
                                          } catch (error) {
                                            if (context.mounted) {
                                              await _showError(context, error);
                                            }
                                          } finally {
                                            if (mounted) {
                                              setState(
                                                () => _updatingReady = false,
                                              );
                                            }
                                          }
                                        },
                                  child: _updatingReady
                                      ? const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            ),
                                            SizedBox(width: 8),
                                            Text('Updating...'),
                                          ],
                                        )
                                      : Text(
                                          me['ready'] == true
                                              ? 'Cancel ready'
                                              : 'Ready up',
                                        ),
                                ),
                              if (host && data['status'] == 'waiting')
                                OutlinedButton(
                                  onPressed: !canStart || _starting || _updatingReady ? null : () async {
                                    setState(() => _starting = true);
                                    try {
                                      await service.startGame(widget.lobbyId);
                                      if (context.mounted) context.go('/game/${widget.lobbyId}');
                                    } catch (error) {
                                      if (context.mounted) await _showError(context, error);
                                    } finally {
                                      if (mounted) setState(() => _starting = false);
                                    }
                                  },
                                  child: _starting ? const Row(mainAxisSize: MainAxisSize.min, children: [
                                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                                    SizedBox(width: 8), Text('Starting...'),
                                  ]) : const Text('Start match'),
                                ),
                              if (me != null && data['status'] == 'playing')
                                OutlinedButton.icon(onPressed: () => context.go('/game/${widget.lobbyId}'),
                                  icon: const Icon(Icons.play_arrow), label: const Text('Enter match')),
                              if (me != null && data['status'] == 'waiting')
                                TextButton(
                                  onPressed: _updatingReady
                                      ? null
                                      : () async {
                                          try {
                                            await service.leaveLobby(
                                              widget.lobbyId,
                                            );
                                            if (context.mounted) {
                                              context.go('/');
                                            }
                                          } catch (error) {
                                            if (context.mounted) {
                                              await _showError(context, error);
                                            }
                                          }
                                        },
                                  child: const Text('Leave'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
}

Color _seatColor(String color) => switch (color) {
  'ember' => const Color(0xFFE86E66),
  'azure' => cyan,
  'gold' => gold,
  'violet' => const Color(0xFFB7A0E9),
  _ => muted,
};

Future<void> _accountDialog(BuildContext context) async {
  final email = TextEditingController();
  final password = TextEditingController();
  final user = service.auth.currentUser;
  final linkedProviders = user?.providerData.map((provider) => provider.providerId).toSet() ?? <String>{};
  var busy = false;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(builder: (dialogContext, update) {
      Future<void> run(Future<void> Function() action) async {
        if (busy) return;
        update(() => busy = true);
        try {
          await action();
          if (dialogContext.mounted) Navigator.pop(dialogContext);
        } catch (error) {
          if (dialogContext.mounted) await _showError(dialogContext, error);
        } finally {
          if (dialogContext.mounted) update(() => busy = false);
        }
      }
      return AlertDialog(
      title: const Text('Keep your games'),
      content: SizedBox(
        width: 370,
        child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              user?.isAnonymous == true
                ? 'Link this guest to keep its games. To return to an existing account, sign in below; that replaces this guest session.'
                : 'Your games are saved to this account. You can link another sign-in method or sign out.',
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 17),
            TextField(
              controller: email,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: password,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: busy || linkedProviders.contains('password')
                  ? null : () => run(() => service.linkEmail(email.text, password.text)),
                child: const Text('Link email account'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: busy || linkedProviders.contains('google.com')
                  ? null : () => run(service.linkGoogle),
                child: const Text('Link Google account'),
              ),
            ),
            const SizedBox(height: 18),
            const Divider(),
            const SizedBox(height: 8),
            const Text('Already have an account?', style: TextStyle(color: muted)),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: OutlinedButton(
              onPressed: busy ? null : () => run(service.signInGoogle),
              child: const Text('Sign in with Google'),
            )),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: OutlinedButton(
              onPressed: busy ? null : () => run(() => service.signInEmail(email.text, password.text)),
              child: const Text('Sign in with email'),
            )),
            if (user?.isAnonymous == false) ...[
              const SizedBox(height: 12),
              TextButton(onPressed: busy ? null : () => run(service.auth.signOut),
                child: const Text('Sign out')),
            ],
            if (busy) const Padding(padding: EdgeInsets.only(top: 12),
              child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        )),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(dialogContext),
          child: const Text('Close'),
        ),
      ],
    ); }),
  );
  email.dispose();
  password.dispose();
}
