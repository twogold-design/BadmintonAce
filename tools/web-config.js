// Cloud backend deployment: replace the assignment below with your WSS URL.
// This same setting works for a local game package or a competition platform.
// Example: window.ACE_SERVER = 'wss://badminton.example.com/ws';
// Preconfigured LAN host for downloaded/offline clients. Hosted pages use their own origin.
window.ACE_SERVER = location.protocol === 'file:' ? 'ws://10.11.179.27:8766/ws' : '';
