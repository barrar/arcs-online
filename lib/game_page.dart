import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import 'card_catalog.dart';
import 'reach_board_layout.dart';
import 'reach_names.dart';
import 'resource_icon.dart';
import 'services.dart';
import 'theme.dart';

class GamePage extends StatefulWidget {
  const GamePage({required this.gameId, required this.service, super.key});
  final String gameId;
  final ArcsService service;

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  late final Future<User> _guest = widget.service.ensureGuest();
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _game = widget.service.game(widget.gameId);
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _events = widget.service.events(widget.gameId);
  final Map<String, Stream<DocumentSnapshot<Map<String, dynamic>>>> _hands = {};
  final GlobalKey _decisionKey = GlobalKey();
  final GlobalKey _actionsKey = GlobalKey();
  late final Future<List<CourtCard>> _catalog = loadBaseCourt();
  late final Future<Map<String, CourtCard>> _courtCards = _catalog.then(
    (cards) => {for (final card in cards) card.id: card});
  String? _selectedSystem;
  String? _selectedCard;
  String _mode = 'lead';
  String? _ambition;
  String? _bardAmbition;
  String? _extraCard;
  bool _busy = false;
  bool _showAllEvents = false;
  bool _showActionInfo = true;
  int _boardPointers = 0;
  String? _failedCommandJson;
  String? _failedCommandId;
  Timer? _refreshClock;

  @override
  void initState() {
    super.initState();
    _refreshClock = Timer.periodic(const Duration(seconds: 5), (_) { if (mounted) setState(() {}); });
  }

  @override
  void dispose() {
    _refreshClock?.cancel();
    super.dispose();
  }

  Future<void> _send(Map<String, dynamic> command) async {
    if (_busy) return;
    final payload = jsonEncode(command);
    final commandId = payload == _failedCommandJson && _failedCommandId != null
      ? _failedCommandId! : const Uuid().v4();
    setState(() => _busy = true);
    try {
      await widget.service.command(widget.gameId, command, commandId: commandId);
      _failedCommandJson = null;
      _failedCommandId = null;
    } catch (error) {
      _failedCommandJson = payload;
      _failedCommandId = commandId;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SpaceBackdrop(
      child: SafeArea(
        child: FutureBuilder<User>(
          future: _guest,
          builder: (context, guest) {
            if (guest.hasError) return Center(child: Text('Could not sign in: ${guest.error}'));
            if (!guest.hasData) return const Center(child: CircularProgressIndicator());
            final uid = guest.data!.uid;
            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _game,
              builder: (context, gameSnapshot) {
                if (gameSnapshot.hasError) return Center(child: Text('Could not load match: ${gameSnapshot.error}'));
                if (!gameSnapshot.hasData) return const Center(child: CircularProgressIndicator());
                final game = gameSnapshot.data!.data();
                if (game == null) return const Center(child: Text('Match not found.'));
                if (!(game['memberIds'] as List).contains(uid)) return const Center(child: Text('You are not seated in this match.'));
                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: _hands.putIfAbsent(uid, () => widget.service.hand(widget.gameId, uid)),
                  builder: (context, handSnapshot) {
                    if (handSnapshot.hasError) return Center(child: Text('Could not load your hand: ${handSnapshot.error}'));
                    if (!handSnapshot.hasData) return const Center(child: CircularProgressIndicator());
                    final hand = handSnapshot.data!.data();
                    if (hand == null) return const Center(child: Text('Waiting for your hand.'));
                    return _content(game, hand, uid);
                  },
                );
              },
            );
          },
        ),
      ),
    ),
  );

  Widget _content(Map<String, dynamic> game, Map<String, dynamic> hand, String uid) {
    final players = (game['players'] as Map).cast<String, dynamic>();
    final actorUid = game['actorUid'] as String?;
    final isTurn = actorUid == uid && game['status'] == 'playing';
    final selected = _selectedSystem;
    final status = game['status'] as String;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 20, 10),
          child: Row(
            children: [
              IconButton(tooltip: 'All tables', onPressed: () => context.go('/'), icon: const Icon(Icons.arrow_back)),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${game['name']}', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge),
                Text('CHAPTER ${game['chapter']}  •  ${game['setupId']}  •  ${game['rulesVersion']}',
                  style: const TextStyle(color: muted, fontSize: 11, letterSpacing: 1)),
              ])),
              if (_busy) const Padding(padding: EdgeInsets.only(right: 12), child: SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))),
              _Deadline(deadlineMs: game['deadlineMs'] as int, active: status == 'playing'),
              if (status == 'playing') PopupMenuButton<String>(tooltip: 'Match options',
                onSelected: (value) { if (value == 'concede') _confirmConcede(); },
                itemBuilder: (_) => const [PopupMenuItem(value: 'concede', child: Text('Concede match'))]),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth >= 980;
            final board = _ReachBoard(game: game, selectedSystem: selected,
              onSelect: (systemId) => setState(() => _selectedSystem = systemId));
            final rail = _rail(game, hand, players, uid, isTurn, wide);
            return wide
                ? Row(children: [Expanded(flex: 3, child: board), SizedBox(width: 400, child: rail)])
                : ListView(
                      physics: _boardPointers > 0
                          ? const NeverScrollableScrollPhysics()
                          : null,children: [SizedBox(height: math.min(
                            math.max(constraints.maxWidth * 1.25,
                              constraints.maxHeight * .78,
                            ),
                            760.0,
                          ),
                          child: Listener(
                            behavior: HitTestBehavior.opaque,
                            onPointerDown: (_) {
                              _boardPointers++;
                              if (_boardPointers == 1) setState(() {});
                            },
                            onPointerUp: (_) => _releaseBoardPointer(),
                            onPointerCancel: (_) => _releaseBoardPointer(), child: board,
                          )),
                    rail]);
          }),
        ),
      ],
    );
  }

  void _scrollToDecision(bool isTurn) {
    final target = (isTurn ? _actionsKey : _decisionKey).currentContext;
    if (target != null) {
      Scrollable.ensureVisible(target,
        duration: const Duration(milliseconds: 300), alignment: .08,
        curve: Curves.easeOutCubic);
    }
  }

  void _releaseBoardPointer() {
    if (_boardPointers == 0) return;
    _boardPointers--;
    if (_boardPointers == 0 && mounted) setState(() {});
  }

  String _decisionPrompt(Map<String, dynamic> game, Map<String, dynamic> players,
      String uid, bool isTurn) {
    if (game['status'] != 'playing') return 'The match has ended. Review the result and event history.';
    if (!isTurn) {
      final actor = (players[game['actorUid']] as Map?)?['name'] ?? 'another player';
      return 'Waiting for $actor. Your hand and the board are ready to review.';
    }
    if (game['mulliganPendingUid'] == uid) return 'Choose whether to keep or redraw your opening hand.';
    if (game['pendingRecoveryUid'] == uid) return 'Place your recovery ships at a gate.';
    if ((game['pendingResourceChoices'] as List).isNotEmpty) return 'Choose which resources to keep.';
    if (game['farseersPendingUid'] == uid) return 'Finish the Farseers hand choice.';
    if ((game['pendingVox'] as List).isNotEmpty) return 'Resolve the secured Vox effect.';
    if (game['pendingBattle'] != null) return 'Resolve the battle before continuing.';
    final round = game['round'] as Map;
    if (round['playedThisTurn'] == true) {
      final pips = round['remainingPips'] as int;
      return '$pips action ${pips == 1 ? 'pip' : 'pips'} remaining. End your turn when ready.';
    }
    return round['lead'] == null
      ? 'Lead with a card or pass initiative.'
      : 'Play a card to copy, surpass, or pivot.';
  }

  Widget _rail(Map<String, dynamic> game, Map<String, dynamic> hand, Map<String, dynamic> players,
      String uid, bool isTurn, bool scrollable) {
    final actorUid = game['actorUid'] as String?;
    final actor = actorUid == null ? null : (players[actorUid] as Map?);
    final round = (game['round'] as Map).cast<String, dynamic>();
    final cards = (hand['cards'] as List).cast<String>();
    final me = (players[uid] as Map).cast<String, dynamic>();
    final needsChoice = game['mulliganPendingUid'] == uid || game['pendingRecoveryUid'] == uid ||
      game['farseersPendingUid'] == uid || game['pendingBattle'] != null ||
      (game['pendingVox'] as List).isNotEmpty ||
      (game['pendingResourceChoices'] as List).isNotEmpty || round['playedThisTurn'] == true;
    final handPanel = _hand(game, round, cards, uid, isTurn);
    final commandPanel = KeyedSubtree(key: _actionsKey,
      child: _turnControls(game, hand, round, me, uid, isTurn));
    final commandWithInfo = Column(
      children: [
        if (_showActionInfo) ...[
          _actionInfoPanel(_decisionPrompt(game, players, uid, isTurn), isTurn),
          const SizedBox(height: 12),
        ],
        commandPanel,
      ],
    );
    final decisionPanel = isTurn && needsChoice ? commandWithInfo : handPanel;
    final secondaryPanel = isTurn && needsChoice ? handPanel : commandWithInfo;
    final children = <Widget>[
        GlassPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(game['status'] == 'finished' ? 'MATCH COMPLETE' : game['status'] == 'terminated'
            ? 'MATCH ENDED' : isTurn ? 'YOUR TURN' : 'WAITING FOR ${actor?['name'] ?? 'PLAYER'}',
            style: const TextStyle(color: cyan, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 2)),
          const SizedBox(height: 10),
          for (final entry in players.entries) _PlayerLine(
            player: (entry.value as Map).cast<String, dynamic>(), active: entry.key == actorUid),
          if (game['status'] == 'finished') Padding(padding: const EdgeInsets.only(top: 12),
            child: Text('Winner: ${(players[game['winnerUid']] as Map?)?['name'] ?? 'Unknown'}',
              style: const TextStyle(color: gold, fontWeight: FontWeight.bold))),
          if (game['status'] == 'terminated') Padding(padding: const EdgeInsets.only(top: 12),
            child: Text((game['termination'] as Map?)?['reason'] == 'concession'
              ? 'A player conceded. The match ended without chapter scoring.'
              : 'An overdue player was removed. No official ARCS winner was awarded.')),
        ])),
        const SizedBox(height: 12),
        KeyedSubtree(key: _decisionKey, child: decisionPanel),
        const SizedBox(height: 12),
        secondaryPanel,
        const SizedBox(height: 12),
        _roundPanel(game),
        if (game['lastScoring'] != null) ...[const SizedBox(height: 12), _lastScoring(game)],
        const SizedBox(height: 12),
        _personalBoard(game, me),
        const SizedBox(height: 12),
        _court(game, uid, isTurn),
        const SizedBox(height: 12),
        _eventHistory(),
      ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 20, 24),
      shrinkWrap: !scrollable,
      physics: scrollable ? null : const NeverScrollableScrollPhysics(),
      children: children,
    );
  }

  Widget _actionInfoPanel(String decision, bool isTurn) => Semantics(
    liveRegion: true,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
      decoration: BoxDecoration(
        color: (isTurn ? gold : cyan).withValues(alpha: .12),
        border: Border.all(
          color: (isTurn ? gold : cyan).withValues(alpha: .45),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            isTurn ? Icons.bolt : Icons.hourglass_top,
            color: isTurn ? gold : cyan,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              decision,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(
            onPressed: () => _scrollToDecision(isTurn),
            child: Text(isTurn ? 'Go to action' : 'View hand'),
          ),
          IconButton(
            tooltip: 'Hide action info',
            onPressed: () => setState(() => _showActionInfo = false),
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    ),
  );

  Future<void> _confirmConcede() async {
    final confirm = await showDialog<bool>(context: context, builder: (dialog) => AlertDialog(
      title: const Text('Concede this match?'),
      content: const Text('The match will end for every seated player.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Keep playing')),
        ElevatedButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Concede')),
      ]));
    if (confirm == true) await _send({'kind': 'concede'});
  }

  Widget _roundPanel(Map<String, dynamic> game) {
    final round = (game['round'] as Map).cast<String, dynamic>();
    final lead = round['lead'] as Map?;
    final plays = (round['plays'] as List).cast<Map>();
    final players = (game['players'] as Map).cast<String, dynamic>();
    final markers = (game['markers'] as List).cast<Map>();
    return GlassPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('ROUND & AMBITIONS', style: TextStyle(color: gold, fontWeight: FontWeight.w800, letterSpacing: 2)),
      const SizedBox(height: 9),
      Text('Initiative: ${(players['${round['initiativeUid']}'] as Map)['name']}'),
      Text('Lead: ${lead == null ? 'Awaiting lead card' : _cardLabel('${(lead['card'] as Map)['id']}')}',
        style: const TextStyle(color: cyan)),
      if (plays.isNotEmpty) ...[
        const SizedBox(height: 7),
        for (final play in plays) Text('${(players['${play['uid']}'] as Map)['name']} · ${play['mode'] == 'copy' ? 'face-down copy' : '${play['mode']} ${_cardLabel('${(play['card'] as Map)['id']}')}'}',
          style: const TextStyle(fontSize: 12, color: muted)),
      ],
      if (markers.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: [for (final marker in markers)
          Chip(label: Text('${marker['ambition']} ${marker['first']}/${marker['second']}'))]),
      ],
      Text('${round['availableAmbitions']} markers available', style: const TextStyle(color: muted, fontSize: 11)),
    ]));
  }

  Widget _lastScoring(Map<String, dynamic> game) {
    final scoring = (game['lastScoring'] as Map).cast<String, dynamic>();
    final players = (game['players'] as Map).cast<String, dynamic>();
    final before = (scoring['powerBefore'] as Map).cast<String, dynamic>();
    final after = (scoring['powerAfter'] as Map).cast<String, dynamic>();
    return GlassPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('CHAPTER ${scoring['chapter']} SCORING',
        style: const TextStyle(color: gold, fontWeight: FontWeight.w800, letterSpacing: 2)),
      const SizedBox(height: 7),
      for (final uid in (game['order'] as List).cast<String>()) Text(
        '${(players[uid] as Map)['name']}: ${before[uid]} → ${after[uid]} Power',
        style: const TextStyle(fontSize: 12)),
    ]));
  }

  Widget _personalBoard(Map<String, dynamic> game, Map<String, dynamic> player) {
    final resources = (player['resources'] as List);
    final guilds = (player['guilds'] as List).cast<String>();
    final capacity = [2, 3, 4, 6, 6, 6][player['citiesOut'] as int];
    const costs = [3, 1, 1, 2, 1, 3];
    return GlassPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('YOUR PLAYER BOARD', style: TextStyle(color: gold, fontWeight: FontWeight.w800, letterSpacing: 2)),
      const SizedBox(height: 9),
      Wrap(spacing: 7, runSpacing: 7, children: [for (var i = 0; i < capacity; i++)
        Chip(
                  avatar: resources[i] == null
                      ? null
                      : ResourceIcon(
                          resource: '${resources[i]}',
                          size: 22,
                          excludeFromSemantics: true,
                        ),label: Text('${resources[i] ?? 'EMPTY'} · ${costs[i]} keys'))]),
      const SizedBox(height: 7),
      Text('${player['citiesOut']} cities · ${(player['trophies'] as List).length} trophies · ${(player['captiveOwners'] as List).length} captives',
        style: const TextStyle(color: muted, fontSize: 12)),
      if ((player['outrage'] as List).isNotEmpty) Text('Outrage: ${(player['outrage'] as List).join(', ')}',
        style: const TextStyle(color: Color(0xFFE86E66), fontSize: 12)),
      if (guilds.isNotEmpty) ...[
        const SizedBox(height: 9),
        FutureBuilder<List<CourtCard>>(future: _catalog, builder: (context, snapshot) {
          final cards = {for (final card in snapshot.data ?? <CourtCard>[]) card.id: card};
          return Wrap(spacing: 6, runSpacing: 6, children: [for (final id in guilds)
            Chip(
              avatar: cards[id] == null ? null : ClipOval(child: Image.asset(
                cards[id]!.artPath, width: 24, height: 24, fit: BoxFit.cover,
                excludeFromSemantics: true,
              )),
              label: Text(cards[id]?.name ?? id),
            )]);
        }),
      ],
    ]));
  }

  Widget _court(Map<String, dynamic> game, String uid, bool isTurn) {
    final slots = (game['courtRow'] as List).cast<Map>();
    return GlassPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('THE COURT', style: TextStyle(color: gold, fontWeight: FontWeight.w800, letterSpacing: 2)),
      const SizedBox(height: 10),
      FutureBuilder<List<CourtCard>>(future: _catalog, builder: (context, catalog) {
        final cards = {for (final card in catalog.data ?? <CourtCard>[]) card.id: card};
        return Column(children: [for (var index = 0; index < slots.length; index++)
          Padding(padding: const EdgeInsets.only(bottom: 7), child: OutlinedButton(
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(8)),
            onPressed: () => _showCourtCard(game, index,
              cards[slots[index]['cardId']], uid, isTurn),
            child: Row(children: [
              if (cards[slots[index]['cardId']] != null) ...[
                ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.asset(
                  cards[slots[index]['cardId']]!.artPath,
                  width: 64, height: 64, fit: BoxFit.cover,
                  semanticLabel: '${cards[slots[index]['cardId']]!.name} artwork',
                )),
                const SizedBox(width: 10),
              ],
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(cards[slots[index]['cardId']]?.name ?? '${slots[index]['cardId']}',
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(cards[slots[index]['cardId']]?.type == 'vox'
                  ? 'VOX' : 'GUILD · ${cards[slots[index]['cardId']]?.suit?.toUpperCase() ?? ''}',
                  style: const TextStyle(color: muted, fontSize: 10, letterSpacing: 1)),
              ])),
              const SizedBox(width: 8),
              Text('${(slots[index]['agents'] as Map)[uid] ?? 0} agents',
                style: const TextStyle(color: cyan, fontSize: 11)),
            ]),
          ))]);
      }),
    ]));
  }

  Widget _hand(Map<String, dynamic> game, Map<String, dynamic> round, List<String> cards, String uid, bool isTurn) {
    final card = cards.contains(_selectedCard) ? _selectedCard : null;
    final rank = card == null ? null : int.tryParse(card.split('-').last);
    final lead = round['lead'] as Map?;
    final leadCard = lead?['card'] as Map?;
    final leadRank = leadCard == null ? 0 : lead!['declared'] != null && lead['retainRank'] != true
      ? 0 : leadCard['rank'] as int;
    final modeOptions = lead == null ? ['lead'] : [
      if (card != null && card.split('-').first == leadCard!['suit'] && rank != null && rank > leadRank) 'surpass',
      'copy',
      if (card != null && card.split('-').first != leadCard!['suit']) 'pivot',
    ];
    final mode = modeOptions.contains(_mode) ? _mode : modeOptions.first;
    final printedAmbition = switch (rank) { 2 => 'tycoon', 3 => 'tyrant', 4 => 'warlord',
      5 => 'keeper', 6 => 'empath', _ => null };
    final choices = rank == 7 ? ['tycoon', 'tyrant', 'warlord', 'keeper', 'empath']
      : printedAmbition == null ? <String>[] : [printedAmbition];
    final me = ((game['players'] as Map)[uid] as Map);
    final canPlay = isTurn && game['mulliganPendingUid'] == null &&
      game['pendingBattle'] == null && game['pendingRecoveryUid'] == null &&
      (game['pendingResourceChoices'] as List).isEmpty &&
      (game['pendingVox'] as List).isEmpty && game['farseersPendingUid'] == null;
    final canSeize = mode != 'lead' && round['initiativeUid'] != uid && round['seizedUid'] == null;
    final canBard = ['surpass', 'pivot'].contains(mode) &&
      (me['guilds'] as List).contains('ARCS-BC25') && game['declaredThisRound'] != true &&
      (round['availableAmbitions'] as int) > 0 && choices.isNotEmpty;
    return GlassPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('YOUR ACTION CARDS', style: TextStyle(color: gold, fontWeight: FontWeight.w800, letterSpacing: 2)),
      const SizedBox(height: 10),
      if (cards.isEmpty) const Text('No cards in hand.', style: TextStyle(color: muted))
      else LayoutBuilder(builder: (context, constraints) {
        final width = (constraints.maxWidth - 8) / 2;
        return Wrap(spacing: 8, runSpacing: 8, children: [for (final id in cards)
          SizedBox(width: width, child: _ActionCardTile(
            id: id, selected: card == id,
            onTap: canPlay && round['playedThisTurn'] != true && !_busy
              ? () => setState(() { _selectedCard = id; _ambition = null; _bardAmbition = null; _extraCard = null; })
              : null,
          ))]);
      }),
      if (canPlay && round['playedThisTurn'] != true && card != null) ...[
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(initialValue: mode, decoration: const InputDecoration(labelText: 'Play as'),
          items: [for (final value in modeOptions) DropdownMenuItem(value: value, child: Text(value.toUpperCase()))],
          onChanged: _busy ? null : (value) => setState(() { _mode = value!; _ambition = null; _bardAmbition = null; _extraCard = null; })),
        if (mode == 'lead' && choices.isNotEmpty && (round['availableAmbitions'] as int) > 0) ...[
          const SizedBox(height: 9),
          DropdownButtonFormField<String>(initialValue: choices.contains(_ambition) ? _ambition : null,
            decoration: const InputDecoration(labelText: 'Declare an ambition (optional)'),
            items: [const DropdownMenuItem(value: 'none', child: Text('No declaration')),
              for (final value in choices) DropdownMenuItem(value: value, child: Text(value.toUpperCase()))],
            onChanged: (value) => setState(() => _ambition = value == 'none' ? null : value)),
        ],
        if (canSeize && cards.length > 1) ...[
          const SizedBox(height: 9),
          DropdownButtonFormField<String>(initialValue: cards.contains(_extraCard) ? _extraCard : 'none',
            decoration: const InputDecoration(labelText: 'Seize initiative with an extra face-down card'),
            items: [const DropdownMenuItem(value: 'none', child: Text('Do not seize')),
              for (final id in cards.where((id) => id != card)) DropdownMenuItem(value: id, child: Text(_cardLabel(id)))],
            onChanged: (value) => setState(() => _extraCard = value == 'none' ? null : value)),
        ],
        if (canBard) ...[
          const SizedBox(height: 9),
          DropdownButtonFormField<String>(initialValue: _bardAmbition ?? 'none',
            decoration: const InputDecoration(labelText: 'Galactic Bards declaration'),
            items: [const DropdownMenuItem(value: 'none', child: Text('Do not declare')),
              for (final value in choices) DropdownMenuItem(value: value, child: Text(value.toUpperCase()))],
            onChanged: (value) => setState(() => _bardAmbition = value == 'none' ? null : value)),
        ],
        const SizedBox(height: 10),
        ElevatedButton.icon(onPressed: _busy ? null : () => _send({
          'kind': 'play', 'cardId': card, 'mode': mode,
          if (_ambition != null && mode == 'lead') 'declare': _ambition,
          if (_extraCard != null && mode != 'lead') 'extraCardId': _extraCard,
          if (_bardAmbition != null && mode != 'lead') 'bardDeclare': _bardAmbition,
        }), icon: const Icon(Icons.play_arrow), label: const Text('Play card')),
      ],
    ]));
  }

  Widget _turnControls(Map<String, dynamic> game, Map<String, dynamic> hand, Map<String, dynamic> round,
      Map<String, dynamic> me, String uid, bool isTurn) {
    final pendingCleanup = (game['pendingResourceChoices'] as List?)?.cast<String>() ?? [];
    final pendingVox = (game['pendingVox'] as List?)?.cast<String>() ?? [];
    final battle = game['pendingBattle'] as Map?;
    final awaitingMulligan = game['mulliganPendingUid'] == uid;
    final awaitingRecovery = game['pendingRecoveryUid'] == uid;
    final deadline = game['deadlineMs'] as int;
    return GlassPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('YOUR OPTIONS', style: TextStyle(color: gold, fontWeight: FontWeight.w800, letterSpacing: 2)),
      const SizedBox(height: 10),
      if (awaitingRecovery) ...[
        const Text('No ships or starports remain on the map. Place up to three fresh ships at a gate.'),
        const SizedBox(height: 8),
        ElevatedButton(onPressed: _busy ? null : () async {
          final gate = await _pick('Recover at which gate?', {
            for (final cluster in (game['activeClusters'] as List).cast<int>())
              '$cluster:gate': _systemName(game, '$cluster:gate'),
          });
          if (gate != null) await _send({'kind': 'recover', 'gateId': gate});
        }, child: const Text('Choose recovery gate')),
      ] else if (awaitingMulligan) ...[
        const Text('You may replace your six-card hand once.'),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          OutlinedButton(onPressed: _busy ? null : () => _send({'kind': 'mulligan', 'replace': false}), child: const Text('Keep hand')),
          ElevatedButton(onPressed: _busy ? null : () => _send({'kind': 'mulligan', 'replace': true}), child: const Text('Draw six new cards')),
        ]),
      ] else if (pendingCleanup.isNotEmpty && pendingCleanup.first == uid) ...[
        Text('Your city slots now hold fewer resources. Choose which ${me['resources']} to keep.'),
        const SizedBox(height: 8),
        ElevatedButton(onPressed: _busy ? null : () => _showResourceChoice(game, uid), child: const Text('Choose resources')),
      ] else if (game['pendingFarseers'] != null || game['farseersPendingUid'] == uid) ...[
        ElevatedButton(onPressed: _busy ? null : () => _showFarseers(game, hand, uid), child: const Text('Resolve Farseers')),
      ] else if (pendingVox.isNotEmpty && isTurn) ...[
        ElevatedButton(onPressed: _busy ? null : () => _showVox(game, pendingVox.first, uid), child: const Text('Resolve Vox')),
      ] else if (battle != null && battle['attackerUid'] == uid) ...[
        Text('Battle in ${_systemName(game, '${battle['systemId']}')} — ${battle['phase']}',
          style: const TextStyle(color: cyan)),
        const SizedBox(height: 8),
        ElevatedButton(onPressed: _busy ? null : () => _showBattle(game, battle, uid), child: const Text('Resolve battle')),
      ] else if (isTurn && round['playedThisTurn'] == true) ...[
        Text('${round['remainingPips']} action pips remain', style: const TextStyle(color: cyan)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if ((game['turn'] as Map)['canRearrange'] == true)
            OutlinedButton(onPressed: _busy ? null : () => _arrangeResources(game, uid),
              child: const Text('Arrange resources')),
          ElevatedButton(onPressed: _busy || round['remainingPips'] == 0 ? null : () => _showActionPicker(game, uid),
            child: const Text('Take an action')),
          if ((game['turn'] as Map)['preludeOpen'] == true)
            OutlinedButton(onPressed: _busy ? null : () => _showPrelude(game, hand, uid), child: const Text('Prelude & resources')),
          OutlinedButton(onPressed: _busy ? null : () => _send({'kind': 'end-turn'}), child: const Text('End turn')),
        ]),
      ] else if (isTurn && round['playedThisTurn'] != true) ...[
        const Text('Play an action card, or pass the initiative.'),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: _busy ? null : () => _send({'kind': 'pass'}), child: const Text('Pass initiative')),
      ] else if (game['status'] == 'playing' && deadline < DateTime.now().millisecondsSinceEpoch) ...[
        const Text('The active player is overdue. Every other player must approve a kick.'),
        Text('${((game['vote'] as Map?)?['approvals'] as List?)?.length ?? 0} of ${(game['order'] as List).length - 1} approvals',
          style: const TextStyle(color: muted, fontSize: 12)),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: _busy || (((game['vote'] as Map?)?['approvals'] as List?)?.contains(uid) ?? false)
          ? null : () => _send({'kind': 'vote-kick', 'targetUid': game['actorUid']}),
          child: Text((((game['vote'] as Map?)?['approvals'] as List?)?.contains(uid) ?? false)
            ? 'Approval recorded' : 'Approve kick')),
      ],
    ]));
  }

  Widget _eventHistory() => GlassPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('RECENT MOVES', style: TextStyle(color: gold, fontWeight: FontWeight.w800, letterSpacing: 2)),
    const SizedBox(height: 10),
    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: _events, builder: (context, snapshot) {
      if (snapshot.hasError) return Text('${snapshot.error}');
      if (!snapshot.hasData) return const LinearProgressIndicator();
      final docs = snapshot.data!.docs;
      return FutureBuilder<Map<String, CourtCard>>(future: _courtCards, builder: (context, catalog) {
        final cardNames = {for (final entry in (catalog.data ?? <String, CourtCard>{}).entries)
          entry.key: entry.value.name};
        return Column(children: [for (final doc in docs.take(_showAllEvents ? docs.length : 6)) Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 36, padding: const EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(color: cyan.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(6)),
            child: Text('#${doc.data()['version']}', textAlign: TextAlign.center,
              style: const TextStyle(color: cyan, fontSize: 10, fontWeight: FontWeight.w800))),
          const SizedBox(width: 10),
          Expanded(child: Text(_readableEvent('${doc.data()['summary']}', cardNames),
            style: const TextStyle(fontSize: 12))),
        ])),
        if (docs.length > 6) TextButton.icon(
          onPressed: () => setState(() => _showAllEvents = !_showAllEvents),
          icon: Icon(_showAllEvents ? Icons.expand_less : Icons.history),
          label: Text(_showAllEvents ? 'Show recent moves' : 'Show all ${docs.length} moves')),
        ]);
      });
    }),
  ]));

  void _showCourtCard(Map<String, dynamic> game, int index,
      CourtCard? card, String uid, bool isTurn) {
    final round = game['round'] as Map;
    final plays = (round['plays'] as List).cast<Map>();
    final currentPlay = plays.isEmpty ? null : plays.last;
    final lead = round['lead'] as Map?;
    final leadCard = lead == null ? null : lead['card'] as Map?;
    final currentCard = currentPlay == null ? null : currentPlay['card'] as Map?;
    final String? suit;
    if (currentPlay == null) {
      suit = null;
    } else if (currentPlay['mode'] == 'copy') {
      suit = leadCard == null ? null : '${leadCard['suit']}';
    } else {
      suit = currentCard == null ? null : '${currentCard['suit']}';
    }
    final canPip = isTurn && round['playedThisTurn'] == true && (round['remainingPips'] as int) > 0 &&
      game['pendingBattle'] == null && (game['pendingVox'] as List).isEmpty &&
      (game['pendingResourceChoices'] as List).isEmpty && game['farseersPendingUid'] == null;
    showModalBottomSheet<void>(context: context, showDragHandle: true,
      isScrollControlled: true, useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (sheet) {
        final id = '${(game['courtRow'] as List)[index]['cardId']}';
        final viewport = MediaQuery.sizeOf(sheet);
        final artSize = math.min(math.min(viewport.width - 48, viewport.height * .36), 280.0);
        return SingleChildScrollView(child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
          child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (card != null) ...[
              Center(child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.asset(
                card.artPath, width: artSize, height: artSize,
                fit: BoxFit.cover, semanticLabel: '${card.name} artwork',
              ))),
              const SizedBox(height: 16),
            ],
            Text(card?.name ?? id, style: Theme.of(sheet).textTheme.titleLarge),
            if (card != null) Padding(padding: const EdgeInsets.only(top: 3),
              child: Text(card.type == 'vox' ? 'VOX' : 'GUILD · ${card.suit?.toUpperCase() ?? ''}',
                style: const TextStyle(color: gold, fontSize: 11, letterSpacing: 1.4))),
            const SizedBox(height: 12),
            Text(card?.plainText ?? id, style: const TextStyle(color: muted)),
            const SizedBox(height: 18),
            if (canPip) Wrap(spacing: 8, children: [
              OutlinedButton(onPressed: _busy || !['administration', 'mobilization'].contains(suit) ? null : () { Navigator.pop(sheet); _send({'kind': 'pip', 'action': {'kind': 'influence', 'courtIndex': index}}); },
                child: const Text('Influence')),
              ElevatedButton(onPressed: _busy || suit != 'aggression' ? null : () { Navigator.pop(sheet); _send({'kind': 'pip', 'action': {'kind': 'secure', 'courtIndex': index}}); },
                child: const Text('Secure')),
            ]),
          ]),
        ));
      },
    );
  }

  Future<Map<String, String>> _courtChoiceOptions(List<Map> slots) async {
    final cards = await _courtCards;
    final labels = <String, String>{};
    for (var index = 0; index < slots.length; index++) {
      final slot = slots[index];
      final card = cards['${slot['cardId']}'];
      final agents = (slot['agents'] as Map).values.fold<int>(0, (total, agentCount) => total + (agentCount as int));
      final description = card?.plainText.replaceAll(RegExp(r'\s+'), ' ') ?? '';
      labels['$index'] = '${card?.name ?? slot['cardId']} · $agents agent${agents == 1 ? '' : 's'}'
        '${description.isEmpty ? '' : '\n$description'}';
    }
    return labels;
  }

  Future<String?> _pick(String title, Map<String, String> options, {
    Map<String, String> resourceIcons = const {},
  }) => showDialog<String>(
    context: context,
    builder: (dialog) => SimpleDialog(title: Text(title), children: [
      for (final entry in options.entries) SimpleDialogOption(
        onPressed: () => Navigator.pop(dialog, entry.key),
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(
                children: [
                  if (resourceIcons[entry.key] != null) ...[
                    ResourceIcon(
                      resource: resourceIcons[entry.key]!,
                      size: 24,
                      excludeFromSemantics: true,
                    ),
                    const SizedBox(width: 9),
                  ],
                  Expanded(child: Text(entry.value)),
                ]))),
    ]),
  );

  Map<String, String> _systemLabels(Map<String, dynamic> game, Iterable<String> ids) {
    final players = (game['players'] as Map).cast<String, dynamic>();
    final systems = (game['systems'] as Map).cast<String, dynamic>();
    final labels = <String, String>{};
    for (final id in ids) {
      final pieces = (systems[id] as List).cast<Map>();
      final byOwner = <String, int>{};
      for (final piece in pieces) {
        byOwner['${piece['owner']}'] = (byOwner['${piece['owner']}'] ?? 0) + 1;
      }
      final occupants = byOwner.entries.map((entry) =>
        '${(players[entry.key] as Map)['name']}: ${entry.value}').join(', ');
      labels[id] = '${_systemName(game, id)}${occupants.isEmpty ? '' : '  •  $occupants'}';
    }
    return labels;
  }

  Future<Map<String, dynamic>?> _composeStandard(Map<String, dynamic> game, String uid, String kind) async {
    final systems = (game['systems'] as Map).cast<String, dynamic>();
    final players = (game['players'] as Map).cast<String, dynamic>();
    final pieces = <Map<String, dynamic>>[];
    for (final entry in systems.entries) {
      for (final raw in (entry.value as List)) {
        final piece = Map<String, dynamic>.from(raw as Map);
        pieces.add({...piece, 'systemId': entry.key});
      }
    }
    final priority = _selectedSystem;
    Iterable<String> sorted(Iterable<String> ids) => ids.toList()..sort((a, b) => a == priority ? -1 : b == priority ? 1 : a.compareTo(b));
    switch (kind) {
      case 'tax': {
        final taxed = (((game['turn'] as Map)['taxedCities']) as List).cast<String>();
        final cities = pieces.where((piece) => piece['kind'] == 'city' &&
          (piece['owner'] == uid || _controller(game, '${piece['systemId']}') == uid) &&
          !taxed.contains(piece['id']));
        final id = await _pick(
          'Tax a city',
          {for (final city in cities) '${city['id']}':
            '${_systemName(game, '${city['systemId']}')} · ${_planetResource('${city['systemId']}')}'},
          resourceIcons: {for (final city in cities) '${city['id']}':
            _planetResource('${city['systemId']}')},
        );
        if (id == null) return null;
        final slot = await _chooseGainSlot(game, uid, 'Place taxed resource');
        return slot == -2 ? null : {'kind': 'tax', 'cityId': id, 'slot': ?slot};
      }
      case 'build': {
        final piece = await _pick('Build', {'ship': 'Ship', 'city': 'City', 'starport': 'Starport'});
        if (piece == null) return null;
        final boardSlots = <String, int>{};
        for (var cluster = 1; cluster <= 6; cluster++) {
          for (final glyph in ['arrow', 'crescent', 'hex']) {
            final id = '$cluster:$glyph';
            if (!systems.containsKey(id)) continue;
            boardSlots[id] = switch (id) {
              '1:arrow' || '1:hex' || '2:hex' || '3:hex' || '4:arrow' || '4:crescent' ||
              '5:hex' || '6:crescent' => 2,
              _ => 1,
            };
          }
        }
        final candidates = piece == 'ship'
          ? pieces.where((item) => item['kind'] == 'starport' && item['owner'] == uid &&
              !(((game['turn'] as Map)['builtAtStarports'] as List).contains(item['id'])))
              .map((item) => '${item['systemId']}')
          : pieces.where((item) => item['owner'] == uid && !'${item['systemId']}'.endsWith(':gate'))
              .map((item) => '${item['systemId']}').where((id) =>
                (systems[id] as List).where((raw) => (raw as Map)['kind'] == 'city' || raw['kind'] == 'starport').length <
                  (boardSlots[id] ?? 0));
        final systemId = await _pick('Build $piece where?', _systemLabels(game, sorted(candidates.toSet())));
        if (systemId == null) return null;
        if (piece == 'ship') {
          final used = (((game['turn'] as Map)['builtAtStarports']) as List).cast<String>();
          final starports = pieces.where((item) => item['kind'] == 'starport' && item['owner'] == uid &&
            item['systemId'] == systemId && !used.contains(item['id'])).toList();
          final starportId = await _pick('Choose starport', {
            for (var index = 0; index < starports.length; index++)
              '${starports[index]['id']}': 'Starport ${index + 1} at ${_systemName(game, systemId)}',
          });
          if (starportId == null) return null;
          return {'kind': 'build', 'piece': piece, 'systemId': systemId, 'starportId': starportId};
        }
        return {'kind': 'build', 'piece': piece, 'systemId': systemId};
      }
      case 'move': {
        final origins = pieces.where((piece) => piece['owner'] == uid && piece['kind'] == 'ship')
          .map((piece) => '${piece['systemId']}').toSet();
        final from = await _pick('Move ships from', _systemLabels(game, sorted(origins)));
        if (from == null) return null;
        final ships = pieces.where((piece) => piece['owner'] == uid && piece['kind'] == 'ship' && piece['systemId'] == from).toList();
        final chosen = await _choosePieces(game, 'Ships to move', ships);
        if (chosen == null || chosen.isEmpty) return null;
        final catapult = pieces.any((piece) => piece['owner'] == uid && piece['kind'] == 'starport' && piece['systemId'] == from);
        var current = from;
        var moving = [...chosen];
        final route = <Map<String, dynamic>>[];
        while (route.length < 12) {
          final to = await _pick('Move from ${_systemName(game, current)} to',
            _systemLabels(game, sorted(_adjacentSystems(game, current))));
          if (to == null) return null;
          final step = <String, dynamic>{'to': to, 'dropShipIds': <String>[]};
          route.add(step);
          final control = _controller(game, to);
          final mustStop = !catapult || !to.endsWith(':gate') || (control != null && control != uid);
          if (mustStop) { step['dropShipIds'] = [...moving]; moving = []; break; }
          final continueMove = await _pick('Catapult at ${_systemName(game, to)}',
            {'continue': 'Continue moving', 'stop': 'Stop here'});
          if (continueMove == null) return null;
          if (continueMove == 'stop') { step['dropShipIds'] = [...moving]; moving = []; break; }
          if (moving.length > 1) {
            final drop = await _choosePieces(game, 'Drop ships at ${_systemName(game, to)} (optional)',
              ships.where((ship) => moving.contains(ship['id'])).toList(),
              allowEmpty: true, max: moving.length - 1);
            if (drop == null) return null;
            step['dropShipIds'] = drop;
            moving = moving.where((id) => !drop.contains(id)).toList();
          }
          current = to;
        }
        if (moving.isNotEmpty) {
          route.last['dropShipIds'] = [
            ...(route.last['dropShipIds'] as List).cast<String>(), ...moving,
          ];
        }
        return {'kind': 'move', 'from': from, 'shipIds': chosen, 'route': route};
      }
      case 'repair': {
        final damaged = pieces.where((piece) => piece['owner'] == uid && piece['damaged'] == true);
        final id = await _pick('Repair a Loyal piece', {for (final piece in damaged) '${piece['id']}':
          '${_systemName(game, '${piece['systemId']}')} · ${piece['kind']}'});
        return id == null ? null : {'kind': 'repair', 'pieceId': id};
      }
      case 'influence': case 'secure': {
        final court = (game['courtRow'] as List).cast<Map>();
        final index = await _pick('${kind == 'influence' ? 'Influence' : 'Secure'} Court card',
          await _courtChoiceOptions(court));
        return index == null ? null : {'kind': kind, 'courtIndex': int.parse(index)};
      }
      case 'battle': {
        final origins = pieces.where((piece) => piece['owner'] == uid && piece['kind'] == 'ship')
          .map((piece) => '${piece['systemId']}').toSet();
        final systemId = await _pick('Battle in', _systemLabels(game, sorted(origins)));
        if (systemId == null) return null;
        final rivals = pieces.where((piece) => piece['systemId'] == systemId && piece['owner'] != uid)
          .map((piece) => '${piece['owner']}').toSet();
        final defender = await _pick('Choose defender', {for (final rival in rivals) rival: '${(players[rival] as Map)['name']}'});
        if (defender == null) return null;
        final attackerShips = pieces.where((piece) => piece['systemId'] == systemId && piece['owner'] == uid && piece['kind'] == 'ship').length;
        final gatekeepers = systemId.endsWith(':gate') &&
          (((players[uid] as Map)['guilds'] as List).contains('ARCS-BC08'));
        final dice = await _chooseDice(attackerShips + (gatekeepers ? 2 : 0));
        if (dice == null) return null;
        return {'kind': 'battle', 'systemId': systemId, 'defenderUid': defender, 'dice': dice};
      }
      default: return null;
    }
  }

  Future<int?> _chooseGainSlot(Map<String, dynamic> game, String uid, String title) async {
    final player = ((game['players'] as Map)[uid] as Map);
    final capacity = [2, 3, 4, 6, 6, 6][player['citiesOut'] as int];
    final resources = player['resources'] as List;
    final chosen = await _pick(title, {
      'auto': 'First open slot (or discard if full)',
      for (var index = 0; index < capacity; index++) '$index':
        'Slot ${index + 1} · ${resources[index] ?? 'empty'} · ${[3, 1, 1, 2, 1, 3][index]} raid keys',
      },
      resourceIcons: {
        for (var index = 0; index < capacity; index++)
          if (resources[index] != null) '$index': '${resources[index]}',
    });
    if (chosen == null) return -2;
    return chosen == 'auto' ? null : int.parse(chosen);
  }

  String? _controller(Map<String, dynamic> game, String systemId) {
    final pieces = (((game['systems'] as Map)[systemId]) as List).cast<Map>();
    final fresh = <String, int>{};
    for (final piece in pieces) {
      if (piece['kind'] == 'ship' && piece['damaged'] != true) {
        final owner = '${piece['owner']}';
        fresh[owner] = (fresh[owner] ?? 0) + 1;
      }
    }
    if (fresh.isEmpty) return null;
    final highest = fresh.values.reduce(math.max);
    final leaders = fresh.entries.where((entry) => entry.value == highest).toList();
    return leaders.length == 1 ? leaders.single.key : null;
  }

  Future<List<String>?> _choosePieces(Map<String, dynamic> game, String title, List<Map<String, dynamic>> pieces,
      {bool allowEmpty = false, int? max}) async {
    final selected = <String>{};
    return showDialog<List<String>>(context: context, builder: (dialog) => StatefulBuilder(
      builder: (context, update) => AlertDialog(title: Text(title), content: SizedBox(width: 350,
        child: ListView(shrinkWrap: true, children: [for (var index = 0; index < pieces.length; index++) CheckboxListTile(
          title: Text('Ship ${index + 1} at ${_systemName(game, '${pieces[index]['systemId']}')}'
            '${pieces[index]['damaged'] == true ? ' · damaged' : ''}'),
          secondary: Icon(_pieceIcon('ship'), color: cyan),
          value: selected.contains('${pieces[index]['id']}'),
          onChanged: (value) => update(() {
            final id = '${pieces[index]['id']}';
            if (value == true && (max == null || selected.length < max)) selected.add(id);
            if (value == false) selected.remove(id);
          }),
        )])), actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
          ElevatedButton(onPressed: !allowEmpty && selected.isEmpty ? null : () => Navigator.pop(dialog, selected.toList()),
            child: const Text('Continue')),
        ])));
  }

  Set<String> _adjacentSystems(Map<String, dynamic> game, String from) {
    final active = (game['activeClusters'] as List).cast<int>();
    final parts = from.split(':');
    final cluster = int.parse(parts.first);
    final glyph = parts.last;
    final systems = (game['systems'] as Map).cast<String, dynamic>();
    final adjacent = <String>{};
    if (glyph == 'gate') {
      adjacent.addAll(['$cluster:arrow', '$cluster:crescent', '$cluster:hex']);
      var next = cluster % 6 + 1;
      while (!active.contains(next)) { next = next % 6 + 1; }
      var previous = (cluster + 4) % 6 + 1;
      while (!active.contains(previous)) { previous = (previous + 4) % 6 + 1; }
      adjacent.add('$next:gate'); adjacent.add('$previous:gate');
    } else {
      adjacent.add('$cluster:gate');
      if (glyph == 'crescent') adjacent.addAll(['$cluster:arrow', '$cluster:hex']);
      if (glyph == 'arrow' || glyph == 'hex') adjacent.add('$cluster:crescent');
      if (from == '2:hex') adjacent.add('3:arrow');
      if (from == '3:arrow') adjacent.add('2:hex');
      if (from == '5:hex') adjacent.add('6:arrow');
      if (from == '6:arrow') adjacent.add('5:hex');
    }
    return adjacent.where(systems.containsKey).toSet();
  }

  Future<Map<String, int>?> _chooseDice(int ships) async {
    var assault = 0; var skirmish = 0; var raid = 0;
    return showDialog<Map<String, int>>(context: context, builder: (dialog) => StatefulBuilder(
      builder: (context, update) => AlertDialog(title: Text('Roll up to $ships dice'), content: Column(
        mainAxisSize: MainAxisSize.min, children: [
          for (final kind in ['assault', 'skirmish', 'raid']) Row(children: [
            Expanded(child: Text(kind.toUpperCase())),
            IconButton(onPressed: () => update(() { if (kind == 'assault' && assault > 0) assault--;
              if (kind == 'skirmish' && skirmish > 0) skirmish--;
              if (kind == 'raid' && raid > 0) raid--; }), icon: const Icon(Icons.remove)),
            Text('${kind == 'assault' ? assault : kind == 'skirmish' ? skirmish : raid}'),
            IconButton(onPressed: assault + skirmish + raid >= ships ? null : () => update(() {
              if (kind == 'assault' && assault < 6) assault++;
              if (kind == 'skirmish' && skirmish < 6) skirmish++;
              if (kind == 'raid' && raid < 6) raid++; }), icon: const Icon(Icons.add)),
          ]),
        ]), actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
          ElevatedButton(onPressed: assault + skirmish + raid < 1 ? null : () => Navigator.pop(dialog,
            {'assault': assault, 'skirmish': skirmish, 'raid': raid}), child: const Text('Roll')),
        ])));
  }

  Future<void> _showActionPicker(Map<String, dynamic> game, String uid) async {
    final round = game['round'] as Map;
    final plays = (round['plays'] as List).cast<Map>();
    if (plays.isEmpty) return;
    final last = plays.last;
    final lead = round['lead'] as Map;
    final card = last['mode'] == 'copy' ? lead['card'] as Map : last['card'] as Map;
    final suit = card['suit'] as String;
    final allowed = switch (suit) {
      'administration' => ['tax', 'repair', 'influence'],
      'aggression' => ['battle', 'move', 'secure'],
      'construction' => ['build', 'repair'],
      _ => ['move', 'influence'],
    };
    if ((game['turn'] as Map)['weaponEnabled'] == true && !allowed.contains('battle')) allowed.add('battle');
    final guilds = (((game['players'] as Map)[uid] as Map)['guilds'] as List).cast<String>();
    final guildActions = _guildActionsFor(allowed, guilds);
    final chosen = await _pick('Take an action', {
      for (final kind in allowed) kind: kind.toUpperCase(), ...guildActions});
    if (chosen == null) return;
    final action = guildActions.containsKey(chosen)
      ? await _composeGuildAction(game, uid, chosen) : await _composeStandard(game, uid, chosen);
    if (action != null) await _send({'kind': 'pip', 'action': action});
  }

  Map<String, String> _guildActionsFor(List<String> allowed, List<String> guilds) {
    final guildActions = <String, String>{};
    if (allowed.contains('build')) {
      if (guilds.contains('ARCS-BC02')) guildActions['manufacture'] = 'Manufacture · Mining Interest';
      if (guilds.contains('ARCS-BC09')) guildActions['synthesize'] = 'Synthesize · Shipping Interest';
      if (guilds.contains('ARCS-BC12')) guildActions['pressgang'] = 'Pressgang · Prison Wardens';
    }
    if (allowed.contains('influence') && guilds.contains('ARCS-BC12')) guildActions['execute'] = 'Execute · Prison Wardens';
    if (allowed.contains('battle') && guilds.contains('ARCS-BC14')) guildActions['abduct'] = 'Abduct · Court Enforcers';
    if (allowed.contains('tax') && guilds.contains('ARCS-BC23')) guildActions['trade'] = 'Trade · Elder Broker';
    return guildActions;
  }

  Future<Map<String, dynamic>?> _composeGuildAction(Map<String, dynamic> game, String uid, String kind) async {
    final player = ((game['players'] as Map)[uid] as Map);
    final resources = (player['resources'] as List);
    switch (kind) {
      case 'manufacture': case 'synthesize': {
        final slot = await _chooseGainSlot(game, uid, 'Place gained resource');
        return slot == -2 ? null : {'kind': kind, 'slot': ?slot};
      }
      case 'pressgang': case 'execute': {
        final captiveOwners = (player['captiveOwners'] as List).cast<String>();
        if (captiveOwners.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You have no Captives.')));
          return null;
        }
        final count = await _pick('Use how many Captives?', {for (var i = 0; i <= captiveOwners.length; i++) '$i': '$i Captives'});
        if (count == null) return null;
        final selected = captiveOwners.take(int.parse(count)).toList();
        if (kind == 'execute') return {'kind': 'execute', 'captiveOwners': selected};
        final gains = <Map<String, dynamic>>[];
        for (var index = 0; index < selected.length; index++) {
          final resource = await _pick('Resource ${index + 1} of ${selected.length}', {
            for (final value in ['material', 'fuel', 'weapon', 'relic', 'psionic']) value: value.toUpperCase()});
          if (resource == null) return null;
          final slot = await _chooseGainSlot(game, uid, 'Place $resource');
          if (slot == -2) return null;
          gains.add({'resource': resource, 'slot': ?slot});
        }
        return {'kind': 'pressgang', 'captiveOwners': selected, 'gains': gains};
      }
      case 'abduct': {
        final court = (game['courtRow'] as List).cast<Map>();
        final index = await _pick('Abduct agents from Court card', await _courtChoiceOptions(court));
        return index == null ? null : {'kind': 'abduct', 'courtIndex': int.parse(index)};
      }
      case 'trade': {
        final systems = (game['systems'] as Map).cast<String, dynamic>();
        final players = (game['players'] as Map).cast<String, dynamic>();
        final cities = <String, String>{};
        for (final entry in systems.entries) {
          for (final piece in (entry.value as List).cast<Map>()) {
            if (piece['kind'] == 'city' && piece['owner'] != uid) {
              cities['${piece['id']}'] = '${_systemName(game, entry.key)} · ${(players['${piece['owner']}'] as Map)['name']} city';
            }
          }
        }
        final cityId = await _pick('Trade at a controlled Rival city', cities);
        if (cityId == null) return null;
        final owner = systems.values.expand((list) => (list as List).cast<Map>()).firstWhere((piece) => piece['id'] == cityId)['owner'];
        final rival = (players['$owner'] as Map);
        final give = await _pick('Give a resource they lack', {for (var i = 0; i < resources.length; i++)
          if (resources[i] != null) '$i': '${resources[i]} · slot ${i + 1}'});
        if (give == null) return null;
        final take = await _pick('Take a city-type resource', {for (var i = 0; i < (rival['resources'] as List).length; i++)
          if ((rival['resources'] as List)[i] != null) '$i': '${(rival['resources'] as List)[i]} · slot ${i + 1}'});
        return take == null ? null : {'kind': 'trade', 'cityId': cityId, 'giveSlot': int.parse(give), 'takeSlot': int.parse(take)};
      }
      default: return null;
    }
  }
  Future<Map<String, dynamic>?> _chooseSteal(Map<String, dynamic> game, String uid,
      {String? resource, bool allowSkip = false}) async {
    final players = (game['players'] as Map).cast<String, dynamic>();
    final cards = await _courtCards;
    final choices = <String, String>{};
    for (final entry in players.entries) {
      if (entry.key == uid) continue;
      final rival = entry.value as Map;
      final guardians = (rival['guilds'] as List).contains('ARCS-BC22');
      for (var slot = 0; slot < (rival['resources'] as List).length; slot++) {
        final token = (rival['resources'] as List)[slot];
        if (!guardians && token != null && (resource == null || token == resource)) {
          choices['resource|${entry.key}|$slot'] = '${rival['name']} · $token · slot ${slot + 1}';
        }
      }
      if (resource == null) {
        for (final card in (rival['guilds'] as List)) {
          if (!guardians || card == 'ARCS-BC22') {
            choices['guild|${entry.key}|$card'] = '${rival['name']} · ${cards[card]?.name ?? card}';
          }
        }
      }
    }
    if (allowSkip) choices['skip'] = 'Discard without stealing';
    if (choices.isEmpty) return null;
    final picked = await _pick('Steal from a Rival', choices);
    if (picked == null) return null;
    if (picked == 'skip') return {'kind': 'skip'};
    final parts = picked.split('|');
    if (parts.first == 'resource') {
      final destination = await _chooseGainSlot(game, uid, 'Place stolen resource');
      if (destination == -2) return null;
      return {'kind': 'resource', 'rivalUid': parts[1], 'rivalSlot': int.parse(parts[2]),
        'destinationSlot': ?destination};
    }
    return {'kind': 'guild', 'rivalUid': parts[1], 'cardId': parts[2]};
  }

  Future<List<String>?> _chooseActionCards(List<String> cards, String title) async {
    final selected = <String>{};
    return showDialog<List<String>>(context: context, builder: (dialog) => StatefulBuilder(
      builder: (context, update) => AlertDialog(title: Text(title), content: SizedBox(width: 350,
        child: ListView(shrinkWrap: true, children: [for (final card in cards) CheckboxListTile(
          title: Text(_cardLabel(card)), value: selected.contains(card),
          onChanged: (value) => update(() { if (value == true) {
            selected.add(card);
          } else {
            selected.remove(card);
          } }),
        )])), actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(dialog, selected.toList()), child: const Text('Continue')),
        ])));
  }

  Future<void> _showPrelude(Map<String, dynamic> game, Map<String, dynamic> hand, String uid) async {
    final me = ((game['players'] as Map)[uid] as Map);
    final cards = await _courtCards;
    final resources = (me['resources'] as List);
    final guilds = (me['guilds'] as List).cast<String>();
    final choices = <String, String>{};
    for (var slot = 0; slot < resources.length; slot++) {
      if (resources[slot] != null) choices['resource:$slot'] = 'Spend ${resources[slot]} · slot ${slot + 1}';
    }
    const preludeCards = {'ARCS-BC02', 'ARCS-BC03', 'ARCS-BC04', 'ARCS-BC05', 'ARCS-BC06',
      'ARCS-BC08', 'ARCS-BC09', 'ARCS-BC10', 'ARCS-BC11', 'ARCS-BC12', 'ARCS-BC13',
      'ARCS-BC14', 'ARCS-BC15', 'ARCS-BC16', 'ARCS-BC17', 'ARCS-BC20', 'ARCS-BC23', 'ARCS-BC24'};
    for (final card in guilds) {
      if (preludeCards.contains(card)) {
        choices['guild:$card'] = 'Use ${cards[card]?.name ?? card}\n${cards[card]?.plainText ?? ''}';
      }
    }
    final chosen = await _pick('Prelude', choices,
      resourceIcons: {
        for (var slot = 0; slot < resources.length; slot++)
          if (resources[slot] != null) 'resource:$slot': '${resources[slot]}',
      });
    if (chosen == null) return;
    if (chosen.startsWith('resource:')) {
      final slot = int.parse(chosen.split(':').last);
      final actual = resources[slot] as String;
      final conversions = <String>[actual];
      final loyal = <String, String>{'material': 'ARCS-BC01', 'fuel': 'ARCS-BC07',
        'weapon': 'ARCS-BC15', 'psionic': 'ARCS-BC19', 'relic': 'ARCS-BC21'};
      for (final entry in loyal.entries) {
        if (guilds.contains(entry.value) && !conversions.contains(entry.key)) conversions.add(entry.key);
      }
      final asResource = conversions.length == 1 ? actual : await _pick('Spend $actual as', {
        for (final value in conversions) value: value.toUpperCase()},
              resourceIcons: {for (final value in conversions) value: value});
      if (asResource == null) return;
      if (asResource == 'weapon') {
        await _send({'kind': 'resource', 'slot': slot, 'as': asResource});
        return;
      }
      final round = game['round'] as Map;
      final lead = round['lead'] as Map?;
      final leadSuit = lead?['card']?['suit'] as String?;
      final allowed = switch (asResource) {
        'material' => ['build', 'repair'], 'fuel' => ['move'], 'relic' => ['secure'],
        _ => switch (leadSuit) {
          'administration' => ['tax', 'repair', 'influence'], 'aggression' => ['battle', 'move', 'secure'],
          'construction' => ['build', 'repair'], _ => ['move', 'influence'],
        },
      };
      final guildActions = _guildActionsFor(allowed, guilds);
      final kind = await _pick('$asResource Prelude action', {
        for (final action in allowed) action: action.toUpperCase(), ...guildActions});
      if (kind == null) return;
      final action = guildActions.containsKey(kind)
        ? await _composeGuildAction(game, uid, kind) : await _composeStandard(game, uid, kind);
      if (action != null) await _send({'kind': 'resource', 'slot': slot, 'as': asResource, 'action': action});
      return;
    }
    final cardId = chosen.substring(6);
    Map<String, dynamic>? effect;
    switch (cardId) {
      case 'ARCS-BC02': case 'ARCS-BC09': {
        final resource = cardId == 'ARCS-BC02' ? 'material' : 'fuel';
        final capacity = [2, 3, 4, 6, 6, 6][me['citiesOut'] as int];
        final empty = [for (var slot = 0; slot < capacity; slot++) if (resources[slot] == null) slot];
        final count = await _pick('Gain up to ${empty.length} $resource', {
          for (var i = 0; i <= empty.length; i++) '$i': '$i resources'});
        if (count == null) return;
        final placements = <Map<String, dynamic>>[];
        var supply = _resourceSupply(game, resource);
        for (final slot in empty.take(int.parse(count))) {
          final placement = <String, dynamic>{'slot': slot};
          if (supply > 0) { supply--; }
          else {
            final stolen = await _chooseSteal(game, uid, resource: resource);
            if (stolen == null) return;
            placement['stealFrom'] = {'uid': stolen['rivalUid'], 'slot': stolen['rivalSlot']};
          }
          placements.add(placement);
        }
        effect = {'kind': 'interest', 'cardId': cardId, 'placements': placements};
        break;
      }
      case 'ARCS-BC03': case 'ARCS-BC06': {
        final steal = await _chooseSteal(game, uid, resource: cardId == 'ARCS-BC03' ? 'material' : 'fuel', allowSkip: true);
        if (steal == null) return;
        effect = {'kind': 'cartel', 'cardId': cardId, if (steal['kind'] != 'skip') 'steal': steal};
        break;
      }
      case 'ARCS-BC04': case 'ARCS-BC05': case 'ARCS-BC10': case 'ARCS-BC11': {
        final suit = {'ARCS-BC04': 'administration', 'ARCS-BC05': 'construction',
          'ARCS-BC10': 'mobilization', 'ARCS-BC11': 'aggression'}[cardId];
        final plays = ((game['round'] as Map)['plays'] as List).cast<Map>();
        final cards = {for (final play in plays) if (play['mode'] != 'copy' && (play['card'] as Map)['suit'] == suit)
          '${(play['card'] as Map)['id']}': '${(play['card'] as Map)['id']} · ${play['uid']}'};
        final selected = await _pick('Recover a played $suit card', cards);
        if (selected == null) return;
        effect = {'kind': 'union', 'cardId': cardId, 'actionCardId': selected};
        break;
      }
      case 'ARCS-BC08': {
        final available = (game['activeClusters'] as List).cast<int>().map((id) => '$id:gate').toList();
        final count = math.min(available.length, _shipSupply(game, uid));
        final chosen = <String>[];
        for (var index = 0; index < count; index++) {
          final gate = await _pick('Place ship ${index + 1} of $count',
            {for (final id in available) id: _systemName(game, id)});
          if (gate == null) return;
          chosen.add(gate); available.remove(gate);
        }
        effect = {'kind': 'gatekeepers', 'gateIds': chosen};
        break;
      }
      case 'ARCS-BC12': case 'ARCS-BC13': case 'ARCS-BC14': case 'ARCS-BC15': {
        final systems = (game['systems'] as Map).cast<String, dynamic>();
        final chosen = await _pick('Place three ships in a controlled system', _systemLabels(game, systems.keys));
        if (chosen == null) return;
        effect = {'kind': 'place-ships', 'cardId': cardId, 'systemId': chosen};
        break;
      }
      case 'ARCS-BC16': effect = {'kind': 'lattice-spies'}; break;
      case 'ARCS-BC17': {
        final discarded = await _chooseActionCards((hand['cards'] as List).cast<String>(), 'Discard action cards with Farseers');
        if (discarded == null) return;
        effect = {'kind': 'farseers', 'discardActionCardIds': discarded};
        break;
      }
      case 'ARCS-BC20': {
        final steal = await _chooseSteal(game, uid, allowSkip: true);
        if (steal == null) return;
        effect = {'kind': 'silver-tongues', if (steal['kind'] != 'skip') 'steal': steal};
        break;
      }
      case 'ARCS-BC23': {
        final slots = <int?>[];
        for (final resource in ['Material', 'Fuel', 'Weapon']) {
          final slot = await _chooseGainSlot(game, uid, 'Place $resource');
          if (slot == -2) return;
          slots.add(slot);
        }
        effect = {'kind': 'elder-broker', 'slots': slots};
        break;
      }
      case 'ARCS-BC24': {
        final slot = await _pick('Discard a resource', {for (var i = 0; i < resources.length; i++)
          if (resources[i] != null) '$i': '${resources[i]} · slot ${i + 1}'});
        if (slot == null) return;
        effect = {'kind': 'relic-fence', 'discardSlot': int.parse(slot)};
        break;
      }
    }
    if (effect != null) await _send({'kind': 'guild-prelude', 'effect': effect});
  }

  int _resourceSupply(Map<String, dynamic> game, String resource) {
    var count = 5;
    for (final player in (game['players'] as Map).values) {
      count -= ((player as Map)['resources'] as List).where((item) => item == resource).length;
    }
    count -= (game['phantomResources'] as List).where((item) => item == resource).length;
    for (final items in (game['heldResources'] as Map).values) {
      count -= (items as List).where((item) => item == resource).length;
    }
    count -= (((game['turn'] as Map)['spentResources'] as List).where((item) => item == resource).length);
    return count;
  }

  int _shipSupply(Map<String, dynamic> game, String uid) {
    var count = 15;
    for (final system in (game['systems'] as Map).values) {
      count -= (system as List).cast<Map>().where((piece) => piece['owner'] == uid && piece['kind'] == 'ship').length;
    }
    for (final player in (game['players'] as Map).values) {
      count -= ((player as Map)['trophies'] as List).cast<Map>()
        .where((piece) => piece['owner'] == uid && piece['kind'] == 'ship').length;
    }
    return math.max(0, count);
  }

  Future<void> _showBattle(Map<String, dynamic> game, Map battle, String uid) async {
    final faces = (battle['faces'] as List).cast<Map>();
    if (battle['phase'] == 'assign') {
      final player = ((game['players'] as Map)[uid] as Map);
      final guilds = (player['guilds'] as List).cast<String>();
      final skirmishIndexes = [for (var i = 0; i < faces.length; i++) if (faces[i]['die'] == 'skirmish') i];
      if (guilds.contains('ARCS-BC13') && battle['rerolled'] != true && skirmishIndexes.isNotEmpty) {
        final answer = await _pick('Rolled: ${_facesLabel(faces)}',
          {'reroll': 'Reroll skirmish dice with Skirmishers', 'assign': 'Keep roll and assign hits'});
        if (answer == null) return;
        if (answer == 'reroll') {
          if (!mounted) return;
          final icons = (player['resources'] as List).where((item) => item == 'weapon').length +
            guilds.where((id) => {'ARCS-BC11', 'ARCS-BC12', 'ARCS-BC13', 'ARCS-BC14', 'ARCS-BC15'}.contains(id)).length;
          final selected = <int>{};
          final reroll = await showDialog<List<int>>(context: context, builder: (dialog) => StatefulBuilder(
            builder: (context, update) => AlertDialog(title: Text('Reroll up to $icons skirmish dice'),
              content: SizedBox(width: 320, child: ListView(shrinkWrap: true, children: [
                for (final index in skirmishIndexes) CheckboxListTile(
                  title: Text('Die ${index + 1}: ${_faceLabel(faces[index])}'), value: selected.contains(index),
                  onChanged: (value) => update(() {
                    if (value == true && selected.length < icons) selected.add(index);
                    if (value == false) selected.remove(index);
                  })),
              ])), actions: [
                TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
                ElevatedButton(onPressed: selected.isEmpty ? null : () => Navigator.pop(dialog, selected.toList()),
                  child: const Text('Reroll')),
              ])));
          if (reroll != null) await _send({'kind': 'reroll-skirmish', 'faceIndexes': reroll});
          return;
        }
      } else {
        final answer = await _pick('Rolled: ${_facesLabel(faces)}', {'assign': 'Assign hits'});
        if (answer == null) return;
      }
    }
    if (battle['phase'] == 'raid') {
      final cards = await _courtCards;
      final defender = ((game['players'] as Map)[battle['defenderUid']] as Map);
      final keys = battle['keys'] as int;
      final choices = <String, String>{'finish': 'Finish raid'};
      final guardians = (defender['guilds'] as List).contains('ARCS-BC22');
      final resources = (defender['resources'] as List);
      for (var slot = 0; slot < resources.length; slot++) {
        final cost = [3, 1, 1, 2, 1, 3][slot];
        if (!guardians && resources[slot] != null && cost <= keys) choices['resource:$slot'] = '${resources[slot]} · slot ${slot + 1} · $cost keys';
      }
      const raidCosts = {'ARCS-BC01': 3, 'ARCS-BC07': 3, 'ARCS-BC15': 3, 'ARCS-BC19': 3,
        'ARCS-BC21': 3, 'ARCS-BC22': 1, 'ARCS-BC25': 1};
      for (final card in (defender['guilds'] as List)) {
        final cost = raidCosts[card] ?? 2;
        if (cost <= keys && (!guardians || card == 'ARCS-BC22')) {
          choices['guild:$card'] = '${cards[card]?.name ?? card} · $cost keys';
        }
      }
      final choice = await _pick('Spend $keys raid keys', choices);
      if (choice == null) return;
      if (choice == 'finish') { await _send({'kind': 'finish-raid'}); return; }
      if (choice.startsWith('resource:')) {
        final destination = await _chooseGainSlot(game, uid, 'Place raided resource');
        if (destination == -2) return;
        await _send({'kind': 'raid', 'target': {'kind': 'resource', 'slot': int.parse(choice.split(':').last),
          'destinationSlot': ?destination}});
      } else {
        await _send({'kind': 'raid', 'target': {'kind': 'guild', 'cardId': choice.substring(6)}});
      }
      return;
    }
    final systemId = battle['systemId'] as String;
    final pieces = ((game['systems'] as Map)[systemId] as List)
      .map((raw) => Map<String, dynamic>.from(raw as Map)).toList();
    final attacker = battle['attackerUid'] as String;
    final defender = battle['defenderUid'] as String;
    final freshDefenderShips = pieces.where((piece) => piece['owner'] == defender && piece['kind'] == 'ship' && piece['damaged'] == false).length;
    final ownHits = faces.fold<int>(0, (total, face) => total + (face['own'] as int)) +
      (faces.any((face) => face['intercept'] == true) ? freshDefenderShips : 0);
    final shipHits = faces.fold<int>(0, (total, face) => total + (face['ship'] as int));
    final buildingHits = faces.fold<int>(0, (total, face) => total + (face['building'] as int));
    final ownTargets = <String>[]; final shipTargets = <String>[]; final buildingTargets = <String>[];
    final ransack = <int>[];
    final simulatedCourt = (game['courtRow'] as List).map((slot) => Map<String, dynamic>.from(slot as Map)).toList();
    final refillCount = game['courtDeckCount'] as int;
    Future<bool> assign(int count, List<String> output, List<Map<String, dynamic>> Function() eligible) async {
      for (var hit = 0; hit < count; hit++) {
        final targets = eligible();
        if (targets.isEmpty) break;
        final id = await _pick('Assign hit ${hit + 1} of $count', {
          for (final piece in targets) '${piece['id']}':
            '${piece['owner'] == uid ? 'Yours' : 'Rival'} · ${piece['kind']} · ${piece['damaged'] == true ? 'damaged' : 'fresh'}',
        });
        if (id == null) return false;
        output.add(id);
        final piece = pieces.firstWhere((item) => item['id'] == id);
        if (piece['damaged'] == true) {
          pieces.remove(piece);
          if (piece['kind'] == 'city' && piece['owner'] == defender) {
            final options = <String, String>{};
            final labels = await _courtChoiceOptions(simulatedCourt.cast<Map>());
            for (var index = 0; index < simulatedCourt.length; index++) {
              if ((simulatedCourt[index]['agents'] as Map)[defender] != null) {
                options['$index'] = labels['$index']!;
              }
            }
            if (options.isNotEmpty) {
              final selected = await _pick('Ransack a Court card', options);
              if (selected == null) return false;
              final courtIndex = int.parse(selected);
              ransack.add(courtIndex);
              if (ransack.length <= refillCount) {
                simulatedCourt[courtIndex] = {'cardId': 'new card', 'agents': <String, int>{}};
              } else {
                simulatedCourt.removeAt(courtIndex);
              }
            }
          }
        } else { piece['damaged'] = true; }
      }
      return true;
    }
    final ownOk = await assign(ownHits, ownTargets, () => pieces.where((piece) => piece['owner'] == attacker && piece['kind'] == 'ship').toList());
    if (!ownOk) return;
    final shipsOk = await assign(shipHits, shipTargets, () {
      final ships = pieces.where((piece) => piece['owner'] == defender && piece['kind'] == 'ship').toList();
      return ships.isNotEmpty ? ships : pieces.where((piece) => piece['owner'] == defender && piece['kind'] != 'ship').toList();
    });
    if (!shipsOk) return;
    final buildingsOk = await assign(buildingHits, buildingTargets, () => pieces.where((piece) =>
      piece['owner'] == defender && piece['kind'] != 'ship').toList());
    if (!buildingsOk) return;
    await _send({'kind': 'assign-hits', 'assignment': {
      'own': ownTargets, 'ships': shipTargets, 'buildings': buildingTargets,
      'ransackCourtIndexes': ransack,
    }});
  }

  String _facesLabel(List<Map> faces) => faces.asMap().entries.map((entry) =>
    '${entry.key + 1}. ${entry.value['die']}: ${_faceLabel(entry.value)}').join(' | ');

  String _faceLabel(Map face) {
    final parts = <String>[];
    if ((face['own'] as int) > 0) parts.add('${face['own']} own hit');
    if (face['intercept'] == true) parts.add('intercept');
    if ((face['ship'] as int) > 0) parts.add('${face['ship']} ship hit');
    if ((face['building'] as int) > 0) parts.add('${face['building']} building hit');
    if ((face['keys'] as int) > 0) parts.add('${face['keys']} key');
    return parts.isEmpty ? 'blank' : parts.join(', ');
  }

  Future<void> _showVox(Map<String, dynamic> game, String cardId, String uid) async {
    final players = (game['players'] as Map).cast<String, dynamic>();
    switch (cardId) {
      case 'ARCS-BC26': {
        final cluster = await _pick('Mass Uprising · choose cluster', {
          for (final id in (game['activeClusters'] as List).cast<int>())
            '$id': '${_systemName(game, '$id:gate')} region',
        });
        if (cluster == null) return;
        final systems = ['$cluster:gate', '$cluster:arrow', '$cluster:crescent', '$cluster:hex'];
        final count = math.min(4, _shipSupply(game, uid));
        final chosen = <String>[];
        final available = [...systems];
        for (var index = 0; index < count; index++) {
          final system = await _pick('Place ship ${index + 1} of $count',
            {for (final id in available) id: _systemName(game, id)});
          if (system == null) return;
          chosen.add(system); available.remove(system);
        }
        await _send({'kind': 'vox', 'choice': {'kind': 'mass-uprising', 'cluster': int.parse(cluster),
          'systemIds': chosen}});
        break;
      }
      case 'ARCS-BC27': {
        final value = await _pick('Populist Demands', {'skip': 'Do not declare',
          for (final ambition in ['tycoon', 'tyrant', 'warlord', 'keeper', 'empath']) ambition: 'Declare ${ambition.toUpperCase()}'});
        if (value != null) await _send({'kind': 'vox', 'choice': {'kind': 'populist-demands', if (value != 'skip') 'ambition': value}});
        break;
      }
      case 'ARCS-BC28': {
        final value = await _pick('Outrage Spreads', {'skip': 'Do not spread Outrage',
          for (final resource in ['material', 'fuel', 'weapon', 'relic', 'psionic']) resource: 'Provoke $resource Outrage'});
        if (value != null) await _send({'kind': 'vox', 'choice': {'kind': 'outrage-spreads', if (value != 'skip') 'resource': value}});
        break;
      }
      case 'ARCS-BC29': {
        final systems = (game['systems'] as Map).cast<String, dynamic>();
        final choices = <String, String>{'skip': 'Return no city'};
        for (final entry in systems.entries) {
          for (final city in (entry.value as List).cast<Map>().where((piece) => piece['kind'] == 'city')) {
            choices['${city['id']}'] = '${_systemName(game, entry.key)} · ${(players['${city['owner']}'] as Map)['name']} city';
          }
        }
        final city = await _pick('Song of Freedom', choices);
        if (city == null) return;
        var seize = false;
        if (city != 'skip') {
          final answer = await _pick('Seize initiative?', {'no': 'No', 'yes': 'Yes'});
          if (answer == null) return;
          seize = answer == 'yes';
        }
        await _send({'kind': 'vox', 'choice': {'kind': 'song-of-freedom', if (city != 'skip') 'cityId': city, 'seize': seize}});
        break;
      }
      case 'ARCS-BC30': {
        final cards = await _courtCards;
        final choices = <String, String>{'skip': 'Steal no Guild card'};
        for (final entry in players.entries) {
          if (entry.key == uid) continue;
          for (final card in ((entry.value as Map)['guilds'] as List)) {
            choices['${entry.key}|$card'] = '${(entry.value as Map)['name']} · ${cards[card]?.name ?? card}';
          }
        }
        final chosen = await _pick('Guild Struggle', choices);
        if (chosen == null) return;
        final parts = chosen.split('|');
        await _send({'kind': 'vox', 'choice': {'kind': 'guild-struggle',
          if (chosen != 'skip') 'rivalUid': parts[0], if (chosen != 'skip') 'cardId': parts[1]}});
        break;
      }
      case 'ARCS-BC31': await _send({'kind': 'vox', 'choice': {'kind': 'call-to-action'}}); break;
    }
  }

  Future<void> _showFarseers(Map<String, dynamic> game, Map<String, dynamic> hand, String uid) async {
    final reveal = hand['farseersReveal'] as Map?;
    if (reveal == null) {
      final players = (game['players'] as Map).cast<String, dynamic>();
      final target = await _pick('Farseers · inspect a Rival hand', {
        for (final entry in players.entries) if (entry.key != uid) entry.key: '${(entry.value as Map)['name']}',
      });
      if (target != null) await _send({'kind': 'farseers-target', 'targetUid': target});
      return;
    }
    final yours = (hand['cards'] as List).cast<String>();
    final theirs = (reveal['cards'] as List).cast<String>();
    final mine = await _pick('Swap one of your cards?', {'skip': 'Keep both hands as they are',
      for (final id in yours) id: _cardLabel(id)});
    if (mine == null) return;
    if (mine == 'skip') { await _send({'kind': 'farseers-swap'}); return; }
    final rival = await _pick('Take which Rival card?', {for (final id in theirs) id: _cardLabel(id)});
    if (rival != null) await _send({'kind': 'farseers-swap', 'myCardId': mine, 'rivalCardId': rival});
  }

  Future<void> _showResourceChoice(Map<String, dynamic> game, String uid) async {
    final player = ((game['players'] as Map)[uid] as Map);
    final resources = (player['resources'] as List).whereType<String>().toList();
    final citiesOut = player['citiesOut'] as int;
    final capacity = [2, 3, 4, 6, 6, 6][citiesOut];
    final selected = <int>{};
    final result = await showDialog<List<String?>>(context: context, builder: (dialog) => StatefulBuilder(
      builder: (context, update) => AlertDialog(title: Text('Keep $capacity resources'),
        content: SizedBox(width: 350, child: ListView(shrinkWrap: true, children: [
          for (var index = 0; index < resources.length; index++) CheckboxListTile(
            title: Text('${resources[index]} · token ${index + 1}'), value: selected.contains(index),
                    secondary: ResourceIcon(
                      resource: resources[index],
                      size: 26,
                      excludeFromSemantics: true,
                    ),
            onChanged: (value) => update(() { if (value == true) {
              selected.add(index);
            } else {
              selected.remove(index);
            } })),
        ])), actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
          ElevatedButton(onPressed: selected.length != math.min(resources.length, capacity) ? null : () {
            final keep = [for (final index in selected.toList()..sort()) resources[index]];
            Navigator.pop(dialog, [...keep, ...List<String?>.filled(capacity - keep.length, null)]);
          }, child: const Text('Keep selected')),
        ])));
    if (result != null) await _send({'kind': 'choose-resources', 'slots': result});
  }

  Future<void> _arrangeResources(Map<String, dynamic> game, String uid) async {
    final player = ((game['players'] as Map)[uid] as Map);
    final original = (player['resources'] as List).cast<String?>();
    final capacity = [2, 3, 4, 6, 6, 6][player['citiesOut'] as int];
    final remaining = <int, String>{for (var i = 0; i < original.length; i++) if (original[i] != null) i: original[i]!};
    final next = <String?>[];
    for (var index = 0; index < capacity; index++) {
      final spacesLeft = capacity - index;
      final chosen = await _pick('Resource slot ${index + 1} · ${[3, 1, 1, 2, 1, 3][index]} raid keys', {
        if (remaining.length < spacesLeft) 'empty': 'Leave empty',
        for (final entry in remaining.entries) '${entry.key}': '${entry.value} (from slot ${entry.key + 1})',
        },
        resourceIcons: {
          for (final entry in remaining.entries) '${entry.key}': entry.value,
      });
      if (chosen == null) return;
      if (chosen == 'empty') {
        next.add(null);
      } else {
        next.add(remaining.remove(int.parse(chosen)));
      }
    }
    if (remaining.isEmpty) await _send({'kind': 'rearrange-resources', 'slots': next});
  }
}

String _cardLabel(String id) {
  final parts = id.split('-');
  final suit = parts.first;
  final rank = int.tryParse(parts.last) ?? 0;
  final pips = switch (suit) {
    'administration' => [4, 4, 3, 3, 3, 2, 1],
    'aggression' => [3, 3, 2, 2, 2, 2, 1],
    'construction' || 'mobilization' => [4, 4, 3, 3, 2, 2, 1],
    _ => [0, 0, 0, 0, 0, 0, 0],
  };
  final name = suit.isEmpty ? 'Unknown' : '${suit[0].toUpperCase()}${suit.substring(1)}';
  return '$name $rank · ${rank >= 1 && rank <= 7 ? pips[rank - 1] : 0} pips';
}

String _readableEvent(String summary, Map<String, String> courtNames) {
  final actionCards = summary.replaceAllMapped(
    RegExp(r'\b(administration|aggression|construction|mobilization)-([1-7])\b'),
    (match) {
      final suit = match.group(1)!;
      return '${suit[0].toUpperCase()}${suit.substring(1)} ${match.group(2)}';
    },
  );
  return actionCards.replaceAllMapped(RegExp(r'ARCS-BC(?:0[1-9]|[12][0-9]|3[01])'),
    (match) => courtNames[match.group(0)] ?? match.group(0)!);
}

class _ActionCardTile extends StatelessWidget {
  const _ActionCardTile({required this.id, required this.selected, required this.onTap});
  final String id;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final parts = id.split('-');
    final suit = parts.first;
    final rank = int.tryParse(parts.last) ?? 0;
    final color = switch (suit) {
      'administration' => cyan,
      'aggression' => const Color(0xFFEF8A7B),
      'construction' => gold,
      'mobilization' => const Color(0xFFC6A8F4),
      _ => muted,
    };
    final icon = switch (suit) {
      'administration' => Icons.account_balance,
      'aggression' => Icons.bolt,
      'construction' => Icons.construction,
      'mobilization' => Icons.route,
      _ => Icons.style,
    };
    final actions = switch (suit) {
      'administration' => 'Tax · Repair · Influence',
      'aggression' => 'Battle · Move · Secure',
      'construction' => 'Build · Repair',
      'mobilization' => 'Move · Influence',
      _ => '',
    };
    final pips = _cardLabel(id).split(' · ').last;
    return Semantics(
      button: true, selected: selected, enabled: onTap != null,
      label: '${_cardLabel(id)}. $actions', onTap: onTap,
      child: ExcludeSemantics(child: Tooltip(
        message: actions,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: 114,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [color.withValues(alpha: selected ? .26 : .15), panel]),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: selected ? gold : color.withValues(alpha: .5),
                  width: selected ? 2 : 1),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Icon(icon, color: color, size: 16), const SizedBox(width: 5),
                  Expanded(child: Text(suit.toUpperCase(), overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900,
                      letterSpacing: .8)))]),
                const Spacer(),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('$rank', style: TextStyle(color: color, fontSize: 29,
                    fontWeight: FontWeight.w900, height: .9)),
                  const SizedBox(width: 7),
                  Expanded(child: Text(pips.toUpperCase(), textAlign: TextAlign.right,
                    style: const TextStyle(color: Colors.white, fontSize: 11,
                      fontWeight: FontWeight.w800))),
                ]),
                const SizedBox(height: 4),
                Text(actions, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: muted, fontSize: 10)),
              ]),
            ),
          ),
        ),
      )),
    );
  }
}

class _PlayerLine extends StatelessWidget {
  const _PlayerLine({required this.player, required this.active});
  final Map<String, dynamic> player;
  final bool active;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      CircleAvatar(radius: 8, backgroundColor: _playerColor('${player['color']}')),
      const SizedBox(width: 8),
      Expanded(child: Text('${player['name']}', style: TextStyle(fontWeight: active ? FontWeight.bold : FontWeight.normal))),
      Text('${player['power']} POWER', style: const TextStyle(color: gold, fontSize: 12, fontWeight: FontWeight.bold)),
    ]));
}

Color _playerColor(String color) => switch (color) {
  'ember' => const Color(0xFFE86E66), 'azure' => cyan, 'gold' => gold,
  'violet' => const Color(0xFFB7A0E9), _ => muted,
};

// Display aliases vary by setup; commands still use official system IDs.
String _systemName(Map<String, dynamic> game, String id) =>
  ReachNames((game['activeClusters'] as List).cast<int>()).system(id);

IconData _pieceIcon(String kind) => switch (kind) {
  'ship' => Icons.rocket_launch_rounded,
  'city' => Icons.location_city_rounded,
  'starport' => Icons.hub_rounded,
  _ => Icons.circle,
};

int _pieceOrder(String kind) => switch (kind) {
  'starport' => 0,
  'city' => 1,
  _ => 2,
};

String _planetResource(String id) {
  const data = <String, String>{
    '1:arrow': 'Weapon', '1:crescent': 'Fuel', '1:hex': 'Material',
    '2:arrow': 'Psionic', '2:crescent': 'Weapon', '2:hex': 'Relic',
    '3:arrow': 'Material', '3:crescent': 'Fuel', '3:hex': 'Weapon',
    '4:arrow': 'Relic', '4:crescent': 'Fuel', '4:hex': 'Material',
    '5:arrow': 'Weapon', '5:crescent': 'Relic', '5:hex': 'Psionic',
    '6:arrow': 'Material', '6:crescent': 'Fuel', '6:hex': 'Psionic',
  };
  return data[id] ?? 'Gate';
}

Widget _systemDetails(
  Map<String, dynamic> game,
  String systemId,
  VoidCallback onClose,
) {
  final systems = (game['systems'] as Map).cast<String, dynamic>();
  if (!systems.containsKey(systemId)) return const SizedBox.shrink();
  final players = (game['players'] as Map).cast<String, dynamic>();
  final pieces = (systems[systemId] as List).cast<Map>();
  final name = _systemName(game, systemId);
  return Semantics(
    container: true,
    label: '$name details',
    child: GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name.toUpperCase(),
                  style: const TextStyle(
                    color: gold,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close system details',
                onPressed: onClose,
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
          if (systemId.endsWith(':gate'))
            const Text(
              'GATE',
              style: TextStyle(color: cyan, fontSize: 11, letterSpacing: 1),
            )
          else
            Row(
              children: [
                ResourceIcon(
                  resource: _planetResource(systemId),
                  size: 22,
                  excludeFromSemantics: true,
                ),
                const SizedBox(width: 6),
                Text(
                  '${_planetResource(systemId).toUpperCase()} PLANET',
                  style: const TextStyle(
                    color: cyan,
                    fontSize: 11,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 9),
          if (pieces.isEmpty)
            const Text('No pieces here.', style: TextStyle(color: muted)),
          for (final piece in pieces)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(
                    _pieceIcon('${piece['kind']}'),
                    size: 16,
                    color: _playerColor(
                      '${(players['${piece['owner']}'] as Map)['color']}',
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      '${(players['${piece['owner']}'] as Map)['name']} · ${piece['kind']} '
                      '${piece['damaged'] == true ? '· DAMAGED' : ''}',
                      style: TextStyle(
                        color: _playerColor(
                          '${(players['${piece['owner']}'] as Map)['color']}',
                        ),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

class _Deadline extends StatefulWidget {
  const _Deadline({required this.deadlineMs, required this.active});
  final int deadlineMs;
  final bool active;
  @override
  State<_Deadline> createState() => _DeadlineState();
}

class _DeadlineState extends State<_Deadline> {
  late final Timer _ticker;
  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() {}); });
  }
  @override
  void dispose() { _ticker.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final remaining = Duration(milliseconds: widget.deadlineMs - DateTime.now().millisecondsSinceEpoch);
    final label = !widget.active ? 'ENDED' : remaining.isNegative ? 'OVERDUE'
      : remaining.inHours >= 1 ? '${remaining.inHours}h ${remaining.inMinutes.remainder(60)}m'
      : '${remaining.inMinutes}:${remaining.inSeconds.remainder(60).toString().padLeft(2, '0')}';
    return Text(label, style: TextStyle(color: remaining.isNegative ? const Color(0xFFE86E66) : cyan,
      fontWeight: FontWeight.w800, letterSpacing: 1));
  }
}

class _ReachBoard extends StatefulWidget {
  const _ReachBoard({required this.game, required this.selectedSystem, required this.onSelect});
  final Map<String, dynamic> game;
  final String? selectedSystem;
  final ValueChanged<String?> onSelect;

  @override
  State<_ReachBoard> createState() => _ReachBoardState();
}

class _ReachBoardState extends State<_ReachBoard> {
  final GlobalKey _boardKey = GlobalKey();
  Offset? _tapPosition;

  void _rememberTap(TapDownDetails details) {
    final box = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null) _tapPosition = box.globalToLocal(details.globalPosition);
  }

  @override
  Widget build(BuildContext context) {
    final active = (widget.game['activeClusters'] as List).cast<int>();
    final systems = (widget.game['systems'] as Map).cast<String, dynamic>();
    final players = (widget.game['players'] as Map).cast<String, dynamic>();
    final layout = ReachBoardLayout(activeClusters: active, playerCount: players.length);
    const boardSize = 850.0;
    return GlassPanel(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final viewport = constraints.biggest;
            final tooltipWidth = math.min(
              320.0,
              math.max(0.0, viewport.width - 24),
            );
            final selectedPieces = widget.selectedSystem == null
                ? 0
                : ((systems[widget.selectedSystem] as List?)?.length ?? 0);
            final tooltipHeight = math.min(
              math.min(280.0, 132.0 + selectedPieces * 24.0),
              math.max(0.0, viewport.height - 24),
            );
            final anchor =
                _tapPosition ?? Offset(viewport.width / 2, viewport.height / 2);
            final left =
                (anchor.dx + tooltipWidth + 16 <= viewport.width - 12
                        ? anchor.dx + 16
                        : anchor.dx - tooltipWidth - 16)
                    .clamp(
                      12.0,
                      math.max(12.0, viewport.width - tooltipWidth - 12),
                    )
                    .toDouble();
            final below = anchor.dy + 16;
            final top =
                (below + tooltipHeight <= viewport.height - 12
                        ? below
                        : anchor.dy - tooltipHeight - 16)
                    .clamp(
                      12.0,
                      math.max(12.0, viewport.height - tooltipHeight - 12),
                    )
                    .toDouble();
            return Stack(
              key: _boardKey,
              fit: StackFit.expand,
              children: [
                _ZoomableBoard(
                  child: SizedBox(
                    width: boardSize,
                    height: boardSize,
                    child: LayoutBuilder(builder: (context, constraints) {
                      final size = constraints.biggest;
                      return Stack(children: [
                        Positioned.fill(child: CustomPaint(painter: _ReachPainter(layout))),
                        for (var cluster = 1; cluster <= 6; cluster++)
                          if (active.contains(cluster))
                            for (final glyph in ['gate', 'arrow', 'crescent', 'hex'])
                              _boardNode('$cluster:$glyph', size, systems, players, layout),
                      ]);
                    }),
                  ),
                ),
                Positioned(top: 12, left: 12, child: IgnorePointer(child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(color: panel.withValues(alpha: .94),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cyan.withValues(alpha: .24))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    for (final kind in ['ship', 'city', 'starport']) ...[
                      if (kind != 'ship') const SizedBox(width: 12),
                      Icon(_pieceIcon(kind), size: 14, color: cyan),
                      const SizedBox(width: 4),
                      Text(kind == 'starport' ? 'Starport' : kind == 'city' ? 'City' : 'Ship',
                        style: const TextStyle(color: muted, fontSize: 10)),
                    ],
                  ]),
                ))),
                if (widget.selectedSystem != null)
                  Positioned(
                    left: left,
                    top: top,
                    width: tooltipWidth,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: tooltipHeight),
                      child: SingleChildScrollView(
                        child: _systemDetails(
                          widget.game,
                          widget.selectedSystem!,
                          () => widget.onSelect(null),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _boardNode(String id, Size size, Map<String, dynamic> systems,
      Map<String, dynamic> players, ReachBoardLayout layout) {
    final position = layout.position(id, size);
    return Positioned(
      left: position.dx - 44,
      top: position.dy - 44,
      width: 88,
      height: 88,
      child: _SystemNode(
        id: id,
        name: _systemName(widget.game, id),
        pieces: (systems[id] as List).cast<Map>(),
        selected: id == widget. selectedSystem,
        colors: {for (final entry in players.entries) entry.key: '${(entry.value as Map)['color']}'},
        onTapDown: _rememberTap,
        onTap: () => widget. onSelect(id),
      ),
    );
  }
}

class _ZoomableBoard extends StatefulWidget {
  const _ZoomableBoard({required this.child});
  final Widget child;

  @override
  State<_ZoomableBoard> createState() => _ZoomableBoardState();
}

class _ZoomableBoardState extends State<_ZoomableBoard> {
  static const _boardSize = 850.0;
  final TransformationController _controller = TransformationController();
  Size? _viewport;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _fit(Size viewport) {
    final scale = (math.min(viewport.width, viewport.height) * .94 / _boardSize).clamp(.3, 4.0);
    _controller.value = Matrix4.identity()
      ..translateByDouble((viewport.width - _boardSize * scale) / 2,
          (viewport.height - _boardSize * scale) / 2, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  void _zoom(double factor) {
    final viewport = _viewport;
    if (viewport == null) return;
    final center = Offset(viewport.width / 2, viewport.height / 2);
    final sceneCenter = _controller.toScene(center);
    // The map is uniformly scaled in 2D; the unchanged Z axis stays at 1.
    final scale = (_controller.value.storage[0] * factor).clamp(.3, 4.0);
    _controller.value = Matrix4.identity()
      ..translateByDouble(center.dx - sceneCenter.dx * scale,
          center.dy - sceneCenter.dy * scale, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final size = constraints.biggest;
    if (size != _viewport) {
      _viewport = size;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _viewport == size) _fit(size);
      });
    }
    return Stack(fit: StackFit.expand, children: [
      InteractiveViewer(
        transformationController: _controller,
        constrained: false,
        minScale: .3,
        maxScale: 4,
        boundaryMargin: const EdgeInsets.all(180),
        child: widget.child,
      ),
      Positioned(right: 10, bottom: 10, child: DecoratedBox(
        decoration: BoxDecoration(color: panel.withValues(alpha: .96),
          borderRadius: BorderRadius.circular(12), border: Border.all(color: cyan.withValues(alpha: .3))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(tooltip: 'Zoom out on map', onPressed: () => _zoom(.75),
            icon: const Icon(Icons.remove, size: 18)),
          TextButton(onPressed: () => _fit(size), child: const Text('Fit map')),
          IconButton(tooltip: 'Zoom in on map', onPressed: () => _zoom(1.33),
            icon: const Icon(Icons.add, size: 18)),
        ]),
      )),
      if (size.width < 700) Positioned(left: 12, bottom: 14, child: IgnorePointer(
        child: Text('Drag to explore', style: TextStyle(color: muted, fontSize: 11,
          shadows: [Shadow(color: panel, blurRadius: 4)])))),
    ]);
  });
}

class _SystemNode extends StatelessWidget {
  const _SystemNode({required this.id, required this.name, required this.pieces, required this.selected,
    required this.colors, required this.onTapDown,
    required this.onTap});
  final String id;
  final String name;
  final List<Map> pieces;
  final bool selected;
  final Map<String, String> colors;
  final ValueChanged<TapDownDetails> onTapDown;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final ships = pieces.where((piece) => piece['kind'] == 'ship').length;
    final cities = pieces.where((piece) => piece['kind'] == 'city').length;
    final starports = pieces.where((piece) => piece['kind'] == 'starport').length;
    final markers = [...pieces]..sort((a, b) =>
      _pieceOrder('${a['kind']}').compareTo(_pieceOrder('${b['kind']}')));
    final shown = markers.take(markers.length > 8 ? 7 : 8);
    return Semantics(
      button: true,
      label: '$name, $ships ships, $cities cities, $starports starports',
      child: Material(
        color: selected ? gold.withValues(alpha: .25) : panel.withValues(alpha: .95),
        shape: CircleBorder(side: BorderSide(
          color: selected ? gold : cyan.withValues(alpha: .55), width: selected ? 3 : 1)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTapDown: onTapDown,
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(width: 76, child: Text(name, textAlign: TextAlign.center,
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: gold, fontSize: 10, fontWeight: FontWeight.w900,
                  height: 1.05))),
              if (!id.endsWith(':gate'))
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ResourceIcon(
                      resource: _planetResource(id),
                      size: 13,
                      excludeFromSemantics: true,
                    ),
                    const SizedBox(width: 2), Text(_planetResource(id),
                style: const TextStyle(color: cyan, fontSize: 9, fontWeight: FontWeight.w600),
                    ),
                  ]),
              if (pieces.isNotEmpty) const SizedBox(height: 2),
              if (pieces.isNotEmpty) SizedBox(width: 76, child: Wrap(
                alignment: WrapAlignment.center, spacing: 2, runSpacing: 1, children: [
                  for (final piece in shown) Tooltip(
                    message: '${colors['${piece['owner']}'] ?? 'Unknown'} ${piece['kind']}'
                      '${piece['damaged'] == true ? ' (damaged)' : ''}',
                    child: Container(width: 16, height: 16, alignment: Alignment.center,
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(4),
                        border: piece['damaged'] == true
                          ? Border.all(color: Colors.white, width: 1) : null),
                      child: Icon(_pieceIcon('${piece['kind']}'), size: 14,
                        color: _playerColor(colors['${piece['owner']}'] ?? ''))),
                  ),
                  if (markers.length > 8) SizedBox(width: 22, height: 16,
                    child: Center(child: Text('+${markers.length - 7}',
                      style: const TextStyle(color: muted, fontSize: 9)))),
                ],
              )),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReachPainter extends CustomPainter {
  const _ReachPainter(this.layout);
  final ReachBoardLayout layout;
  @override
  void paint(Canvas canvas, Size size) {
    final active = layout.activeClusters;
    final center = Offset(size.width / 2, size.height / 2);
    final pathPaint = Paint()..color = cyan.withValues(alpha: .3)..strokeWidth = 3;
    final localPaint = Paint()..color = gold.withValues(alpha: .18)..strokeWidth = 2;
    void connect(String a, String b, Paint paint) => canvas.drawLine(
      layout.position(a, size), layout.position(b, size), paint);
    for (var index = 0; index < active.length; index++) {
      final cluster = active[index];
      final next = active[(index + 1) % active.length];
      connect('$cluster:gate', '$next:gate', pathPaint);
      for (final glyph in ['arrow', 'crescent', 'hex']) {
        connect('$cluster:gate', '$cluster:$glyph', localPaint);
      }
      connect('$cluster:arrow', '$cluster:crescent', localPaint);
      connect('$cluster:crescent', '$cluster:hex', localPaint);
    }
    if (active.contains(2) && active.contains(3)) connect('2:hex', '3:arrow', localPaint);
    if (active.contains(5) && active.contains(6)) connect('5:hex', '6:arrow', localPaint);
    final title = TextPainter(text: const TextSpan(text: 'THE REACH', style: TextStyle(color: gold,
      fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 3)), textDirection: TextDirection.ltr)..layout();
    title.paint(canvas, center - Offset(title.width / 2, title.height / 2));
  }
  @override
  bool shouldRepaint(covariant _ReachPainter oldDelegate) =>
    layout.playerCount != oldDelegate.layout.playerCount ||
    layout.activeClusters.join(',') != oldDelegate.layout.activeClusters.join(',');
}
