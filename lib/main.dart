import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';

import 'firebase_options.dart';
import 'card_catalog.dart';
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
final router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, _) => const HomePage()),
    GoRoute(
      path: '/lobby/:id',
      builder: (_, state) => LobbyPage(lobbyId: state.pathParameters['id']!),
    ),
    GoRoute(path: '/preview', builder: (_, _) => const BoardPreviewPage()),
    GoRoute(path: '/cards', builder: (_, _) => const CardCatalogPage()),
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
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<User> _guest = service.ensureGuest();
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
          const Text('THE REACH AWAITS', style: TextStyle(color: cyan, letterSpacing: 3,
              fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          Text('Explore the edge\nof the galaxy.', style: Theme.of(context).textTheme.displayLarge
              ?.copyWith(fontSize: 46, height: 1.05)),
          const SizedBox(height: 26),
          const GlassPanel(child: Row(children: [
            Icon(Icons.cloud_off, color: gold), SizedBox(width: 14),
            Expanded(child: Text('Online lobbies are temporarily unavailable. You can still browse the base cards and board preview.')),
          ])),
          const SizedBox(height: 22),
          Wrap(spacing: 12, runSpacing: 12, children: [
            ElevatedButton.icon(onPressed: () => context.go('/cards'), icon: const Icon(Icons.style),
                label: const Text('Browse Court cards')),
            OutlinedButton.icon(onPressed: () => context.go('/preview'), icon: const Icon(Icons.grid_view),
                label: const Text('Board preview')),
            TextButton.icon(onPressed: () => setState(() => _guest = service.ensureGuest()),
                icon: const Icon(Icons.refresh), label: const Text('Retry online play')),
          ]),
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
              TextButton.icon(
                onPressed: () => _accountDialog(context),
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
                  const Text(
                    'The full rules engine is in development. Match start is currently disabled.',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              );
              return wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: heading),
                        const SizedBox(width: 30),
                        const Expanded(
                          child: SizedBox(height: 330, child: BoardTeaser()),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        heading,
                        const SizedBox(height: 28),
                        const SizedBox(height: 250, child: BoardTeaser()),
                      ],
                    );
            },
          ),
          const SizedBox(height: 38),
          Row(
            children: [
              Text(
                'OPEN TABLES',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(onPressed: () => context.go('/cards'), child: const Text('Browse cards')),
                  TextButton(onPressed: () => context.go('/preview'), child: const Text('Board preview →')),
                ],
              ),
            ],
          ),
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
                        onTap: () => context.go('/lobby/${doc.id}'),
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
  await showDialog<void>(
    context: context,
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
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
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
              }
            },
            child: const Text('Create'),
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

class LobbyPage extends StatelessWidget {
  const LobbyPage({required this.lobbyId, super.key});
  final String lobbyId;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SpaceBackdrop(
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 850),
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: service.lobby(lobbyId),
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
                                          'https://arcs-online-jeremiah-2026.web.app/join/${data['code']}',
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
                                  onPressed: () async {
                                    try {
                                      await service.setReady(
                                        lobbyId,
                                        me['ready'] != true,
                                      );
                                    } catch (error) {
                                      if (context.mounted) {
                                        await _showError(context, error);
                                      }
                                    }
                                  },
                                  child: Text(
                                    me['ready'] == true
                                        ? 'Cancel ready'
                                        : 'Ready up',
                                  ),
                                ),
                              if (host)
                                OutlinedButton(
                                  onPressed: null,
                                  child: const Text('Start match'),
                                ),
                              if (me != null)
                                TextButton(
                                  onPressed: () async {
                                    try {
                                      await service.leaveLobby(lobbyId);
                                      if (context.mounted) context.go('/');
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
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Keep your games'),
      content: SizedBox(
        width: 370,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Link this guest to an account so you can return on another device.',
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
                onPressed: () async {
                  try {
                    await service.linkEmail(email.text, password.text);
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  } catch (error) {
                    if (dialogContext.mounted) {
                      await _showError(dialogContext, error);
                    }
                  }
                },
                child: const Text('Link email account'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () async {
                  try {
                    await service.linkGoogle();
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  } catch (error) {
                    if (dialogContext.mounted) {
                      await _showError(dialogContext, error);
                    }
                  }
                },
                child: const Text('Continue with Google'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Close'),
        ),
      ],
    ),
  );
  email.dispose();
  password.dispose();
}

class BoardPreviewPage extends StatelessWidget {
  const BoardPreviewPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SpaceBackdrop(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => context.go('/'),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back'),
                  ),
                  const Spacer(),
                  const Text(
                    'BOARD PREVIEW',
                    style: TextStyle(color: muted, letterSpacing: 2),
                  ),
                ],
              ),
            ),
            Expanded(
              child: InteractiveViewer(
                minScale: .6,
                maxScale: 4,
                child: SizedBox.expand(
                  child: CustomPaint(painter: ReachPreviewPainter()),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Visual direction preview • Map and setup data still require rulebook verification.',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class BoardTeaser extends StatelessWidget {
  const BoardTeaser({super.key});
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(22),
    child: GestureDetector(
      onTap: () => context.go('/preview'),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0C1829),
          border: Border.all(color: const Color(0xFF344862)),
          borderRadius: BorderRadius.circular(22),
        ),
        child: const CustomPaint(painter: ReachPreviewPainter()),
      ),
    ),
  );
}

class ReachPreviewPainter extends CustomPainter {
  const ReachPreviewPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final span = math.min(size.width, size.height);
    final outer = span * .41;
    final inner = span * .19;
    final ring = Paint()
      ..color = cyan.withValues(alpha: .34)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final glow = Paint()
      ..color = cyan.withValues(alpha: .08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22);
    canvas.drawCircle(center, inner, glow);
    canvas.drawCircle(center, inner, ring);
    canvas.drawCircle(center, outer, ring..color = gold.withValues(alpha: .17));
    for (var cluster = 0; cluster < 6; cluster++) {
      final angle = cluster * math.pi / 3 - math.pi / 2;
      final gate = Offset(
        center.dx + math.cos(angle) * inner,
        center.dy + math.sin(angle) * inner,
      );
      final nextGate = Offset(
        center.dx + math.cos(angle + math.pi / 3) * inner,
        center.dy + math.sin(angle + math.pi / 3) * inner,
      );
      canvas.drawLine(
        gate,
        nextGate,
        Paint()
          ..color = cyan.withValues(alpha: .24)
          ..strokeWidth = 1,
      );
      canvas.drawCircle(gate, span * .018, Paint()..color = cyan);
      for (var p = 0; p < 3; p++) {
        final a = angle + (p - 1) * .22;
        final dist = outer * (p == 1 ? .94 : .77);
        final planet = Offset(
          center.dx + math.cos(a) * dist,
          center.dy + math.sin(a) * dist,
        );
        canvas.drawLine(
          gate,
          planet,
          Paint()
            ..color = cyan.withValues(alpha: .13)
            ..strokeWidth = 1,
        );
        canvas.drawCircle(
          planet,
          span * .038,
          Paint()
            ..color = [
              gold,
              const Color(0xFFE28069),
              const Color(0xFF6ED0C5),
              const Color(0xFFC29FEA),
              const Color(0xFF89B7EF),
            ][(cluster + p) % 5].withValues(alpha: .25),
        );
        canvas.drawCircle(
          planet,
          span * .028,
          Paint()
            ..color = [
              gold,
              const Color(0xFFE28069),
              const Color(0xFF6ED0C5),
              const Color(0xFFC29FEA),
              const Color(0xFF89B7EF),
            ][(cluster + p) % 5],
        );
      }
    }
    final title = TextPainter(
      text: const TextSpan(
        text: 'THE REACH',
        style: TextStyle(
          color: gold,
          fontSize: 18,
          fontWeight: FontWeight.w900,
          letterSpacing: 2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    title.paint(canvas, center - Offset(title.width / 2, title.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
