import Foundation
import DshClient

let args = CommandLine.arguments
let base = args.count > 1 ? args[1] : "http://127.0.0.1:3080"
guard let url = URL(string: base) else {
    print("usage: dsh-spike [baseURL]   (default: http://127.0.0.1:3080)")
    exit(1)
}
let client = DshClient(baseURL: url)
print("base = \(url)")

// 1) host.describe — typed decode
let host: HostInfo = try await client.call("host.describe", as: HostInfo.self)
print("\n=== host.describe (typed) ===")
print("version=\(host.version) cwd=\(host.cwd) provider=\(host.provider ?? "-") model=\(host.model ?? "-") attachedSessions=\(host.attachedSessions)")

// 2) session.list — raw JSON
let sessions = try await client.call("session.list")
print("\n=== session.list (raw) ===")
print(sessions.prettyPrinted)

// 3) events.mux — first frames (connect replays one session/subscribed per session)
print("\n=== /api/events.mux (first frames) ===")
var n = 0
for try await frame in client.muxEvents() {
    n += 1
    print("frame[\(n)] method=\(frame.method)")
    if n >= 8 { break }
}
print("received \(n) frames")
