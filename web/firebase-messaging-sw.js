// Version matches firebase_core_web's supported Firebase JS SDK.
importScripts('https://www.gstatic.com/firebasejs/12.19.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/12.19.0/firebase-messaging-compat.js');

importScripts('firebase-config.js');
firebase.initializeApp(self.ARCS_FIREBASE_CONFIG);

// Firebase displays notification payloads in the background automatically.
firebase.messaging();
