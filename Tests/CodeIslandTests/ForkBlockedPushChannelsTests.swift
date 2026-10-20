import XCTest
@testable import CodeIsland
@testable import CodeIslandCore

/// Records requests instead of sending them.
private final class RecordingTransport: PushTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [PushHTTPRequest] = []

    var requests: [PushHTTPRequest] { lock.withLock { recorded } }

    func send(_ request: PushHTTPRequest) async -> PushTransportResponse {
        lock.withLock { recorded.append(request) }
        return PushTransportResponse(statusCode: 200, body: Data())
    }
}

/// This fork never sends to Bark, DingTalk, Feishu / Lark or WeCom, even
/// when settings saved by an upstream build still have them enabled.
@MainActor
final class ForkBlockedPushChannelsTests: XCTestCase {
    private var transport = RecordingTransport()
    private let suiteName = "ForkBlockedPushChannelsTests"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        transport = RecordingTransport()
        let notifier = PushNotifier.shared
        notifier.resetForTesting()
        notifier.allowsBlockedChannelsForTesting = false
        notifier.defaults = defaults
        notifier.transport = transport
        notifier.presence = { PushPresenceSnapshot(screenLocked: true) }
        notifier.armsCatchUpTimer = false
        defaults.set(true, forKey: SettingsKey.pushEnabled)
    }

    override func tearDown() {
        let notifier = PushNotifier.shared
        notifier.transport = URLSessionPushTransport.shared
        notifier.presence = { PushPresence.current() }
        notifier.armsCatchUpTimer = true
        notifier.defaults = .standard
        notifier.resetForTesting()
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private var blockedConfigs: [PushChannelConfig] {
        PushChannelKind.allCases.filter(\.isBlockedInFork).map { kind in
            var config = PushChannelConfig(kind: kind)
            config.enabled = true
            config.target = "KEY"
            if config.endpoint.isEmpty { config.endpoint = "https://hooks.example.com/\(kind.rawValue)" }
            return config
        }
    }

    func testTheChineseServicesAreBlockedAndHiddenFromSettings() {
        XCTAssertEqual(Set(PushChannelKind.allCases.filter(\.isBlockedInFork)), [.bark, .dingtalk, .feishu, .wecom])
        XCTAssertEqual(PushChannelKind.allowedCases, [.ntfy, .slack, .telegram])
    }

    func testEnabledBlockedChannelsAreNeverSentTo() async {
        defaults.set(PushChannelConfig.encodeList(blockedConfigs), forKey: SettingsKey.pushChannels)
        XCTAssertFalse(PushNotifier.shared.channels.contains { $0.kind.isBlockedInFork })

        let approval = PushContent.permission(tool: "Bash", detail: "make deploy")
        let request = PushPendingRequest(key: "blocked") { approval }
        let decision = PushNotifier.shared.notify(approval, subject: PushSubject(sessionId: "blocked", agent: "Claude"), request: request)
        XCTAssertEqual(decision, .skipped(.noChannel))
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testSendTestToABlockedChannelMakesNoRequest() async {
        for config in blockedConfigs {
            let result = await PushNotifier.shared.sendTest(config)
            XCTAssertFalse(result.ok, "\(config.kind)")
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testAllowedChannelsStillSend() async {
        var ntfy = PushChannelConfig(kind: .ntfy)
        ntfy.enabled = true
        ntfy.target = "topic"
        defaults.set(PushChannelConfig.encodeList(blockedConfigs + [ntfy]), forKey: SettingsKey.pushChannels)

        let result = await PushNotifier.shared.sendTest(ntfy)
        XCTAssertTrue(result.ok)
        XCTAssertEqual(transport.requests.map { $0.url.host }, ["ntfy.sh"])
    }
}
