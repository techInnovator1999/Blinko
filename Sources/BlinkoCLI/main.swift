import BlinkoKit
import Foundation

// `blinko` — command-line companion to Blinko.app.
// Automation commands open blinko:// URLs (so they launch Blinko if needed); `hook` and
// `send` talk to the Agent Hub socket. Never needs root.

let usage = """
usage: blinko <command> [options]

  alert <title> [--body TEXT] [--icon SF_SYMBOL] [--color NAME|#HEX] [--duration SECONDS]
                              show a custom activity in the island
  timer <minutes> [--label TEXT]   start a countdown
  focus [start|stop]          start or stop a Pomodoro focus session
  open [TAB]                  open the island (home, shelf, clipboard, stats, timer, notes, tools, agents)
  shelf add <path>...         put files on the shelf
  keepawake [MINUTES|on|off]  keep the display awake (on = until stopped)
  url <blinko://…>            open any Blinko URL

  hook                        Claude Code hook client (reads the hook JSON on stdin)
  send                        send Agent Hub protocol lines from stdin, print replies
  claude install|uninstall|status [--settings PATH]
                              add / remove Blinko's hooks in ~/.claude/settings.json
  version
"""

func fail(_ message: String, code: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data("blinko: \(message)\n".utf8))
    exit(code)
}

/// Splits `--name value` options from positional arguments.
func parse(_ args: ArraySlice<String>) -> (positional: [String], options: [String: String]) {
    var positional: [String] = []
    var options: [String: String] = [:]
    var it = args.makeIterator()
    while let arg = it.next() {
        if arg.hasPrefix("--"), arg.count > 2 {
            let name = String(arg.dropFirst(2))
            if let eq = name.firstIndex(of: "=") {
                options[String(name[..<eq])] = String(name[name.index(after: eq)...])
            } else {
                guard let value = it.next() else { fail("--\(name) needs a value") }
                options[name] = value
            }
        } else {
            positional.append(arg)
        }
    }
    return (positional, options)
}

func openURL(_ path: String, _ items: [(String, String?)] = []) -> Never {
    var c = URLComponents()
    c.scheme = "blinko"
    // blinko://shelf/add → host "shelf", path "/add"
    let parts = path.split(separator: "/", maxSplits: 1).map(String.init)
    c.host = parts.first
    if parts.count > 1 { c.path = "/" + parts[1] }
    let query = items.compactMap { name, value in value.map { URLQueryItem(name: name, value: $0) } }
    if !query.isEmpty {
        c.queryItems = query
        // URLComponents leaves "+" alone; some decoders read it as a space.
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
    }
    guard let url = c.url else { fail("could not build the URL") }
    openRaw(url.absoluteString)
}

func openRaw(_ url: String) -> Never {
    guard url.lowercased().hasPrefix("blinko://") else { fail("not a blinko:// URL") }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    // -g: don't bring anything to the front. The bundle id makes sure Blinko handles it.
    p.arguments = ["-g", "-b", "app.blinko.Blinko", url]
    do { try p.run() } catch { fail("could not run open: \(error.localizedDescription)", code: 1) }
    p.waitUntilExit()
    exit(p.terminationStatus == 0 ? 0 : 1)
}

let argv = CommandLine.arguments
guard argv.count > 1 else { print(usage); exit(0) }
let command = argv[1]
let rest = argv.dropFirst(2)

switch command {
case "alert":
    let (pos, opt) = parse(rest)
    guard let title = pos.first ?? opt["title"] else { fail("alert needs a title") }
    openURL("alert", [("title", title), ("body", opt["body"] ?? (pos.count > 1 ? pos[1] : nil)),
                      ("icon", opt["icon"]), ("color", opt["color"]), ("duration", opt["duration"])])

case "timer":
    let (pos, opt) = parse(rest)
    guard let minutes = pos.first.flatMap(Double.init), minutes > 0 else { fail("timer needs a number of minutes") }
    openURL("timer", [("minutes", String(minutes)), ("label", opt["label"])])

case "focus":
    let (pos, _) = parse(rest)
    openURL(pos.first == "stop" ? "focus/stop" : "focus/start")

case "open":
    let (pos, _) = parse(rest)
    openURL("open", [("tab", pos.first)])

case "shelf":
    let (pos, _) = parse(rest)
    guard pos.first == "add", pos.count > 1 else { fail("usage: blinko shelf add <path>...") }
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let paths = pos.dropFirst().map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, relativeTo: cwd).standardizedFileURL.path }
    for path in paths where !FileManager.default.fileExists(atPath: path) { fail("no such file: \(path)", code: 1) }
    openURL("shelf/add", paths.map { ("path", $0) })

case "keepawake":
    let (pos, _) = parse(rest)
    switch pos.first {
    case nil, "on": openURL("keepawake")
    case "off", "stop": openURL("keepawake", [("off", "1")])
    case let m?:
        guard let minutes = Double(m), minutes > 0 else { fail("keepawake takes minutes, on or off") }
        openURL("keepawake", [("minutes", String(minutes))])
    }

case "url":
    guard let url = rest.first else { fail("url needs a blinko:// URL") }
    openRaw(url)

case "hook":
    exit(runHook())

case "send":
    exit(runSend())

case "claude":
    let (pos, opt) = parse(rest)
    let settings = opt["settings"].map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) } ?? ClaudeHooks.defaultSettingsURL
    do {
        switch pos.first {
        case "install":
            let helper = opt["helper"] ?? AgentProtocol.hookHelperPath
            if opt["helper"] == nil {
                try HookHelper.install(from: URL(fileURLWithPath: CommandLine.arguments[0]).absoluteURL, to: helper)
            }
            try ClaudeHooks.install(settingsURL: settings, helperPath: helper)
            print("Installed Blinko hooks in \(settings.path) (backup: \(settings.path).blinko-backup)")
        case "uninstall":
            try ClaudeHooks.uninstall(settingsURL: settings)
            print("Removed Blinko hooks from \(settings.path)")
        case "status", nil:
            print(ClaudeHooks.isInstalled(settingsURL: settings) ? "installed" : "not installed")
        default:
            fail("usage: blinko claude install|uninstall|status [--settings PATH]")
        }
    } catch {
        fail(error.localizedDescription, code: 1)
    }

case "version", "--version", "-v":
    print("blinko (Agent Hub protocol v\(AgentProtocol.version))")

case "help", "--help", "-h":
    print(usage)

default:
    fail("unknown command '\(command)'\n\n\(usage)")
}
