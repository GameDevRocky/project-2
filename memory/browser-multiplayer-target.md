# Browser multiplayer is the shipping target

Fact: The online game must run from the existing GitHub Pages web export.

Why: Browser builds cannot use the raw UDP ENet transport used by the first
networking prototype. They need browser-compatible networking and an external
service because GitHub Pages only serves static files.

How to apply: Design multiplayer around WebRTC or secure WebSockets, and keep
all required signaling, lobby, relay, or authoritative server code deployable
outside GitHub Pages.
