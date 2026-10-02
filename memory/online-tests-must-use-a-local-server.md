# Online tests must run against a local server, never the live one

Fact: tools/tests/run_online_checklist.sh starts a local dedicated server
(`-- --server`, ws://127.0.0.1:9080) and test clients that hand NetworkSession
a socket to it before the menu runs. If that socket is not connected, the
client must stop, because the menu's own connect uses the hard-coded LIVE
`SERVER_URL`.

Why: on 2026-10-01 the local server took ~15 s to start (the project is read
over the WSL file share). The first test run gave up after 10 s, fell through
to the menu, and played a short 3-client test match on Rocklyn's live server.
It was harmless (the lobby closed on disconnect), but it was not supposed to
happen.

How to apply: keep the "wait for `listening on` in the server log" step in the
runner and the "quit if not connected locally" guard in the test. Give the
server up to 90 s to start. Never point a test at `SERVER_URL`. See
[[scratch-folder-is-wiped-keep-test-tools-in-tools-tests]].
