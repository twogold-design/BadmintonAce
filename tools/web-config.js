// If the HTML files and the relay are hosted on different servers,
// set the relay's public secure WebSocket URL here before uploading.
// Example: window.ACE_SERVER = 'wss://badminton.example.com/ws';
// Preconfigured LAN host for downloaded/offline clients. Hosted pages use their own origin.
window.ACE_SERVER = location.protocol === 'file:' ? 'ws://10.11.179.27:8766/ws' : '';
