import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:uuid/uuid.dart';

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

  Future<void> signInEmail(String email, String password) async {
    await auth.signInWithEmailAndPassword(email: email.trim(), password: password);
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

  Future<void> signInGoogle() async {
    if (kIsWeb) {
      await auth.signInWithPopup(GoogleAuthProvider());
    } else {
      await GoogleSignIn.instance.initialize();
      final account = await GoogleSignIn.instance.authenticate();
      await auth.signInWithCredential(GoogleAuthProvider.credential(
        idToken: account.authentication.idToken,
      ));
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

  Future<void> enableTurnAlerts() async {
    const vapidKey = String.fromEnvironment('FCM_VAPID_KEY');
    if (kIsWeb && vapidKey.isEmpty) {
      throw StateError('Set FCM_VAPID_KEY before enabling browser push alerts.');
    }
    final settings = await FirebaseMessaging.instance.requestPermission();
    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      throw StateError('Notification permission was not granted.');
    }
    final token = await FirebaseMessaging.instance.getToken(vapidKey: kIsWeb ? vapidKey : null);
    if (token == null) throw StateError('This browser could not register for push alerts.');
    await functions.httpsCallable('registerPushToken').call({'token': token});
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      await functions.httpsCallable('registerPushToken').call({'token': newToken});
    });
  }

  Future<int> command(String gameId, Map<String, dynamic> command, {String? commandId}) async {
    final id = commandId ?? const Uuid().v4();
    final result = await functions.httpsCallable('submitGameCommand').call<Map<String, dynamic>>({
      'gameId': gameId, 'commandId': id, 'command': command,
    });
    return result.data['version'] as int;
  }

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

  Stream<DocumentSnapshot<Map<String, dynamic>>> game(String id) =>
      store.collection('games').doc(id).snapshots();
  Stream<DocumentSnapshot<Map<String, dynamic>>> hand(String gameId, String uid) =>
      store.collection('games').doc(gameId).collection('hands').doc(uid).snapshots();
  Stream<QuerySnapshot<Map<String, dynamic>>> events(String gameId) => store
      .collection('games').doc(gameId).collection('events').orderBy('version', descending: true).limit(80).snapshots();
}
