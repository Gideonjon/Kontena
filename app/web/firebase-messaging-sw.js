// Handles push notifications when the web app is in the background.
// Paste the same values as your Firebase web app config (Project settings > General > Your apps).
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'REPLACE_ME',
  authDomain: 'kontena-app.firebaseapp.com',
  projectId: 'kontena-app',
  messagingSenderId: 'REPLACE_ME',
  appId: 'REPLACE_ME',
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
