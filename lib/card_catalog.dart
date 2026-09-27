import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'theme.dart';

class CourtCard {
  CourtCard(Map<String, dynamic> data)
    : id = data['id'] as String,
      name = data['name'] as String,
      type = data['type'] as String,
      suit = data['suit'] as String?,
      text = data['text'] as String;

  final String id;
  final String name;
  final String type;
  final String? suit;
  final String text;

  String get plainText => text.replaceAll(RegExp(r'\*+'), '').trim();
}

Future<List<CourtCard>> loadBaseCourt() async {
  final source = await rootBundle.loadString('assets/cards/base_court.json');
  final decoded = jsonDecode(source) as Map<String, dynamic>;
  return (decoded['cards'] as List).map((data) => CourtCard(data as Map<String, dynamic>)).toList();
}

class CardCatalogPage extends StatefulWidget {
  const CardCatalogPage({super.key});

  @override
  State<CardCatalogPage> createState() => _CardCatalogPageState();
}

class _CardCatalogPageState extends State<CardCatalogPage> {
  late final Future<List<CourtCard>> _cards = loadBaseCourt();
  String query = '';
  String filter = 'all';

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SpaceBackdrop(
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: ListView(
              padding: const EdgeInsets.all(22),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => context.go('/'),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Home'),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'THE COURT',
                  style: TextStyle(color: cyan, letterSpacing: 3, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text('Base card library', style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 42)),
                const SizedBox(height: 8),
                const Text('Explore the 25 Guild and 6 Vox cards from the official base game.',
                  style: TextStyle(color: muted)),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 320,
                      child: TextField(
                        decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search cards'),
                        onChanged: (value) => setState(() => query = value.toLowerCase()),
                      ),
                    ),
                    for (final option in ['all', 'guild', 'vox'])
                      ChoiceChip(
                        label: Text(option == 'all' ? 'All cards' : option == 'guild' ? 'Guild' : 'Vox'),
                        selected: filter == option,
                        onSelected: (_) => setState(() => filter = option),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                FutureBuilder<List<CourtCard>>(
                  future: _cards,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) return Text('Could not load cards: ${snapshot.error}');
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                    final cards = snapshot.data!.where((card) =>
                      (filter == 'all' || card.type == filter) &&
                      (query.isEmpty || card.name.toLowerCase().contains(query) || card.plainText.toLowerCase().contains(query))
                    ).toList();
                    return LayoutBuilder(builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 950 ? 4 : constraints.maxWidth >= 650 ? 3 : constraints.maxWidth >= 420 ? 2 : 1;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${cards.length} cards', style: const TextStyle(color: muted)),
                          const SizedBox(height: 12),
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: columns, crossAxisSpacing: 12, mainAxisSpacing: 12,
                              childAspectRatio: columns == 1 ? 1.35 : .83,
                            ),
                            itemCount: cards.length,
                            itemBuilder: (context, index) => _CardTile(card: cards[index]),
                          ),
                        ],
                      );
                    });
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _CardTile extends StatelessWidget {
  const _CardTile({required this.card});
  final CourtCard card;

  Color get accent => switch (card.suit) {
    'material' => const Color(0xFFE2B3DD),
    'fuel' => const Color(0xFFEBD872),
    'weapon' => const Color(0xFFEFA076),
    'relic' => const Color(0xFFB5D8EB),
    'psionic' => const Color(0xFFDFA2D2),
    _ => gold,
  };

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '${card.name}, ${card.type}${card.suit == null ? '' : ', ${card.suit}'}. Tap to read card.',
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(card.name),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: SingleChildScrollView(child: SelectableText(card.plainText)),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [accent.withValues(alpha: .23), panel]),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accent.withValues(alpha: .55)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(card.type.toUpperCase(), style: TextStyle(color: accent, fontSize: 11,
              letterSpacing: 2, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(card.name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            if (card.suit != null) Text(card.suit!.toUpperCase(), style: TextStyle(color: accent, fontSize: 11)),
            const SizedBox(height: 16),
            Expanded(child: Text(card.plainText, maxLines: 8, overflow: TextOverflow.fade,
              style: const TextStyle(height: 1.35, color: Color(0xFFDCE5F2)))),
            const SizedBox(height: 10),
            Text(card.id, style: const TextStyle(color: muted, fontSize: 10)),
          ],
        ),
      ),
    ),
  );
}
