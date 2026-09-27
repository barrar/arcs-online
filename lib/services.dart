import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class ArcsService {
  ArcsService({
    FirebaseAuth? auth,
    FirebaseFirestore? store,
    FirebaseFunctions? functions,
  }) : auth = auth ?? FirebaseAuth.instance,
       store = store ?? FirebaseFirestore.instance,
       functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'us-west1');
  final FirebaseAuth auth;
  final FirebaseFirestore store;
  final FirebaseFunctions functions;

  Future<User> ensureGuest() async {
    final existing = auth.currentUser;
    if (existing != null) return existing;
    return (await auth.signInAnonymously()).user!;
  }

  String get defaultName {
    final user = auth.currentUser;
    final given = user?.displayName;
    return given?.isNotEmpty == true
        ? given!
        : 'Explorer ${user?.uid.substring(0, 5).toUpperCase() ?? 'NEW'}';
  }

  Future<void> linkEmail(String email, String password) async {
    final user = await ensureGuest();
    await user.linkWithCredential(
      EmailAuthProvider.credential(email: email.trim(), password: password),
    );
  }

  Future<void> linkGoogle() async {
    final user = await ensureGuest();
    if (kIsWeb) {
      await user.linkWithPopup(GoogleAuthProvider());
    } else {
      await GoogleSignIn.instance.initialize();
      final account = await GoogleSignIn.instance.authenticate();
      final credential = GoogleAuthProvider.credential(
        idToken: account.authentication.idToken,
      );
      await user.linkWithCredential(credential);
    }
  }

  Future<String> createLobby({
    required String name,
    required String displayName,
    required String visibility,
    required int maxPlayers,
    required Map<String, dynamic> timer,
  }) async {
    final result = await functions
        .httpsCallable('createLobby')
        .call<Map<String, dynamic>>({
          'name': name,
          'displayName': displayName,
          'visibility': visibility,
          'maxPlayers': maxPlayers,
          'timer': timer,
        });
    return result.data['lobbyId'] as String;
  }

  Future<String> joinLobby(String code, String name) async {
    final result = await functions
        .httpsCallable('joinLobby')
        .call<Map<String, dynamic>>({
          'code': code.toUpperCase().trim(),
          'displayName': name,
        });
    return result.data['lobbyId'] as String;
  }

  Future<void> setReady(String lobbyId, bool ready) => functions
      .httpsCallable('setReady')
      .call({'lobbyId': lobbyId, 'ready': ready})
      .then((_) {});
  Future<void> leaveLobby(String lobbyId) => functions
      .httpsCallable('leaveLobby')
      .call({'lobbyId': lobbyId})
      .then((_) {});
  Future<void> startGame(String lobbyId) => functions
      .httpsCallable('startGame')
      .call({'lobbyId': lobbyId})
      .then((_) {});

  Stream<QuerySnapshot<Map<String, dynamic>>> publicLobbies() => store
      .collection('lobbies')
      .where('visibility', isEqualTo: 'public')
      .where('status', isEqualTo: 'waiting')
      .orderBy('createdAt', descending: true)
      .snapshots();
  Stream<DocumentSnapshot<Map<String, dynamic>>> lobby(String id) =>
      store.collection('lobbies').doc(id).snapshots();
  Stream<QuerySnapshot<Map<String, dynamic>>> myGames(String uid) => store
      .collection('games')
      .where('memberIds', arrayContains: uid)
      .orderBy('updatedAt', descending: true)
      .snapshots();
}
