# Blinko Agent Hub protocol (v1)

Blinko shows what AI coding agents are doing in the island and lets you approve or deny their permission requests. Claude Code is supported out of the box (Settings → Agents → Connect Claude Code). Any other agent, such as Codex, Cursor, Aider or your own scripts, can report over the same local socket with this protocol.

## Transport

- **Socket:** a Unix domain stream socket at `~/Library/Application Support/Blinko/agents.sock`. You can override the path with `BLINKO_AGENT_SOCKET`; the app and the CLI both honour it.
- **Permissions:** the socket is mode `0600`, and Blinko rejects peers whose uid differs from its own (`getpeereid`). It never listens on the network.
- **Framing:** newline-delimited JSON. Each message is one UTF-8 JSON object followed by `\n`. A line can be at most 256 KiB; a longer one closes the connection. Lines that are not valid JSON objects with a `type` are ignored.
- **Connections:** a client can send one message and disconnect (status updates), or stay connected (permission requests: the answer comes back on the same connection).
- **Safety:** Blinko only displays what it receives. Nothing received over the socket is ever executed, opened or evaluated.
- **No Blinko:** if the socket doesn't exist or `connect()` fails, Blinko isn't running or the Agent Hub is off. Clients should carry on silently.

## Message fields

Every field except `type` is optional. Unknown fields are ignored.

| Field | Type | Meaning |
|---|---|---|
| `v` | int | Protocol version (`1`) |
| `type` | string | See below |
| `session` | string | Session id, unique per agent. Required for everything except `hello` and `permission_response` |
| `agent` | string | `claude-code`, `codex`, `cursor`, `gemini`, `aider` or any lowercase name. Default: `agent` |
| `cwd` | string | Working directory. Its last path component is shown as the project name |
| `title` | string | Display name; overrides the folder name |
| `state` | string | `working`, `idle` or `waiting` (for `status`) |
| `detail` | string | Short description of the latest activity (shown under the project name) |
| `tool` | string | Tool name (`Bash`, `Edit`…) |
| `phase` | string | `start` or `end` (for `tool`) |
| `summary` | string | One line about the tool call: a command, a file, a URL |
| `message` | string | Notification text |
| `id` | string | Permission request id, echoed in the response |
| `decision` | string | `allow`, `deny` or `ask` (for `permission_response`) |
| `reason` | string | Explanation sent with `deny` |
| `tokens` | int | Tokens used so far (optional) |
| `cost_usd` | number | Cost so far in USD (optional; shown in the Agents tab) |

A session (`agent` + `session`) is created by its first message of any type. Blinko keeps the 12 most recent sessions. Sessions idle for 3 hours are dropped. A session that claims to be `working` but sends nothing for 10 minutes is shown as idle.

## Client → Blinko

### `hello`
```json
{"v":1,"type":"hello","agent":"codex"}
```
Blinko replies `{"type":"ack","v":1}`. Optional; use it to check that Blinko is listening.

### `session_start` / `session_end`
```json
{"v":1,"type":"session_start","agent":"codex","session":"7f3a","cwd":"/Users/me/Projects/api"}
{"v":1,"type":"session_end","agent":"codex","session":"7f3a"}
```
`session_end` removes the session. Any approval still pending for it is answered `ask`.

### `status`
```json
{"v":1,"type":"status","agent":"codex","session":"7f3a","state":"working","detail":"Refactor the auth module"}
{"v":1,"type":"status","agent":"codex","session":"7f3a","state":"idle","detail":"Finished"}
```
- `working`: spinner in the closed island and the Agents tab.
- `idle`: done or waiting for the user's next prompt. Going from `working` to `idle` after at least 15 seconds of work shows a short "Finished" activity.
- `waiting`: the session needs attention. Approvals set this state themselves.

### `tool`
```json
{"v":1,"type":"tool","agent":"codex","session":"7f3a","phase":"start","tool":"Bash","summary":"npm test"}
{"v":1,"type":"tool","agent":"codex","session":"7f3a","phase":"end","tool":"Bash","summary":"npm test"}
```
Marks the session as working. The running tool's name is shown in the closed island.

### `notification`
```json
{"v":1,"type":"notification","agent":"codex","session":"7f3a","message":"Tests are failing on main"}
```
Shown briefly in the closed island (Settings → Agents → Agent notifications).

### `usage`
```json
{"v":1,"type":"usage","agent":"codex","session":"7f3a","tokens":48210,"cost_usd":0.37}
```
`tokens` and `cost_usd` can also be attached to any other message.

### `permission_request`
```json
{"v":1,"type":"permission_request","agent":"codex","session":"7f3a","cwd":"/Users/me/Projects/api",
 "id":"b1c9…","tool":"Bash","summary":"rm -rf dist","detail":"Clean the build output"}
```
Keep the connection open and wait for the answer:
```json
{"v":1,"type":"permission_response","id":"b1c9…","decision":"allow"}
{"v":1,"type":"permission_response","id":"b1c9…","decision":"deny","reason":"Denied in Blinko"}
{"v":1,"type":"permission_response","id":"b1c9…","decision":"ask"}
```
- `allow` / `deny`: the user clicked Approve (⌘↩) or Deny (esc).
- `ask`: let the agent use its own prompt. Blinko sends `ask` when the user clicks "Answer in Terminal", when the wait set in Settings runs out (30 s to 5 min, default 90 s), when approvals in the island are turned off, when the session ends, or when the Agent Hub is turned off.
- If the client disconnects first (for example because the user answered in the agent's own UI), the card disappears.
- Clients should also give up on their own after a while; the `blinko` hook waits at most 590 s. If Blinko quits, the connection closes.

Requests are answered in arrival order. The island shows the oldest one, with "1 of N" when there are more.

## The `blinko` CLI as a client

`blinko send` forwards protocol lines from stdin and prints every reply. Set `BLINKO_WAIT=<seconds>` to keep listening after stdin ends (needed for permission requests):

```bash
echo '{"type":"status","agent":"codex","session":"s1","cwd":"'"$PWD"'","state":"working","detail":"Running tests"}' | blinko send
echo '{"type":"permission_request","agent":"codex","session":"s1","id":"r1","tool":"Bash","summary":"git push --force"}' \
  | BLINKO_WAIT=120 blinko send     # → {"decision":"allow","id":"r1","type":"permission_response","v":1}
```

Raw sockets work too, e.g. `nc -U ~/Library/Application\ Support/Blinko/agents.sock`.

## Claude Code mapping

`blinko hook` is the command Claude Code runs for each hook. It reads the hook's JSON on stdin and translates it:

| Hook | Message |
|---|---|
| `SessionStart` | `session_start` (`session_title` → `title`) |
| `UserPromptSubmit` | `status` `working`, the prompt's first line as `detail` |
| `PreToolUse` / `PostToolUse` | `tool` `start` / `end`, with a summary of `tool_input` (command, file, pattern, URL…) |
| `PermissionRequest` | `permission_request`, then waits. `allow` / `deny` are printed as `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}` (deny adds `message`); `ask`, a timeout or no Blinko print nothing, so Claude Code shows its normal prompt |
| `Notification` | `idle_prompt` → `status` `idle`; `permission_prompt` is skipped (covered by `PermissionRequest`); others → `notification` |
| `Stop` | `status` `idle`, with the last message as `detail` |
| `SubagentStop` | `tool` `end` ("Explore finished") |
| `SessionEnd` | `session_end` |

The hook always exits 0 and never blocks Claude Code for more than a moment, except while it waits for an approval.

**Installer.** Connect Claude Code (or `blinko claude install [--settings PATH]`) does four things:
1. It reads `~/.claude/settings.json` (or `$CLAUDE_CONFIG_DIR/settings.json`). If the file isn't valid JSON, it changes nothing.
2. It copies the file to `settings.json.blinko-backup`. An existing backup is replaced only while the file has no Blinko entries, so the backup always shows your settings before Blinko.
3. It merges: each event above gets one more matcher group (`"matcher": "*"` for tool events) with the command `"~/Library/Application Support/Blinko/bin/blinko" hook`. The timeout is 10 s, or 600 s for `PermissionRequest`. Your own hooks are never touched. Older Blinko entries are replaced, so installing twice is harmless.
4. It writes the result atomically.

The hook command points to a copy of the CLI in Application Support, which Blinko keeps up to date at launch, so moving or updating the app doesn't break the hooks. Disconnect (or `blinko claude uninstall`) removes only the entries whose command contains `Blinko/bin/blinko`, plus any groups or events left empty.
