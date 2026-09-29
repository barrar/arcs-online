// Version matches firebase_core_web's supported Firebase JS SDK.
importScripts('https://www.gstatic.com/firebasejs/12.19.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/12.19.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'REMOVED_FIREBASE_API_KEY',
  appId: '1:451692891873:web:a7adc5706e454f0f0d31a0',
  messagingSenderId: '451692891873',
  projectId: 'arcs-online-jeremiah-2026',
  authDomain: 'arcs-online-jeremiah-2026.firebaseapp.com',
  storageBucket: 'arcs-online-jeremiah-2026.firebasestorage.app',
});

// Firebase displays notification payloads in the background automatically.
firebase.messaging();
