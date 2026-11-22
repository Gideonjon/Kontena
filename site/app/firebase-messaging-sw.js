// Handles push notifications when the web app is in the background.
// Paste the same values as your Firebase web app config (Project settings > General > Your apps).
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyDKIXIR5wDil2-PWchIQRKoOKUITgsURe8',
  authDomain: 'usekontena.firebaseapp.com',
  projectId: 'usekontena',
  messagingSenderId: '91024604067',
  appId: '1:91024604067:web:d5940653e54e808b53f816',
});

const messaging = firebase.messaging();
messaging.onBackgroundMessage((payload) => {
  const n = payload.notification || {};
  self.registration.showNotification(n.title || 'Kontena', { body: n.body || '', icon: '/icons/Icon-192.png', data: payload.data || {} });
});
self.addEventListener('notificationclick', (e) => {
  e.notification.close();
  const id = e.notification.data && e.notification.data.orderId;
  e.waitUntil(clients.openWindow(id ? '/order/' + id : '/'));
});
