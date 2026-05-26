importScripts('https://www.gstatic.com/firebasejs/10.0.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.0.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: "AIzaSyBvTJR8pE3aPRD6Z3ibFCvbTpnXihs08MM",
  authDomain: "massage-pos-4fb5b.firebaseapp.com",
  projectId: "massage-pos-4fb5b",
  storageBucket: "massage-pos-4fb5b.firebasestorage.app",
  messagingSenderId: "279791437227",
  appId: "1:279791437227:web:42f3dae019a993e741feee"
});

const messaging = firebase.messaging();
messaging.onBackgroundMessage((payload) => {
  self.registration.showNotification(payload.notification.title, {
    body: payload.notification.body,
    icon: '/icons/Icon-192.png'
  });
});