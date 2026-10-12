import XCTest
import MirAIeKit

final class StatusTests: XCTestCase {
    func testParsesLiveStatusPayload() throws {
        let json = """
        {"ts":"1791742852","rssi":-78,"ty":"AC","ps":"off","actmp":"26.0","acfs":"auto","acng":"off","acvs":2,"acmd":"cool","rmtmp":"30.0","V":"2.15","mo":"102126","errors":""}
        """
        let values = try JSONDecoder().decode([String: JSONValue].self, from: Data(json.utf8))
        let status = DeviceStatus(values: values)
        XCTAssertEqual(status.powerOn, false)
        XCTAssertEqual(status.mode, "cool")
        XCTAssertEqual(status.targetTemperature, 26.0)
        XCTAssertEqual(status.fanSpeed, "auto")
        XCTAssertEqual(status.swing, 2)
        XCTAssertEqual(status.roomTemperature, 30.0)
        XCTAssertNil(status.error)
    }

    func testParsesConnectionStatus() throws {
        let json = """
        {"deviceId":"abc123","connectedTime":1,"updatedTime":2,"nextUpdate":3,"onlineStatus":"false"}
        """
        let values = try JSONDecoder().decode([String: JSONValue].self, from: Data(json.utf8))
        let status = DeviceStatus(values: values)
        XCTAssertEqual(status.online, false)
    }

    func testErrorExtraction() throws {
        let values = try JSONDecoder().decode(
            [String: JSONValue].self,
            from: Data(#"{"DEVICE_ERROR":"1P2 "}"#.utf8)
        )
        XCTAssertEqual(DeviceStatus(values: values).error, "1P2 ")
    }

    func testTopicParser() {
        XCTAssertEqual(
            TopicParser.deviceId(from: "a/b/abc123def456/status"),
            "abc123def456"
        )
        XCTAssertEqual(
            TopicParser.kind(from: "a/b/abc123def456/status"),
            "status"
        )
        XCTAssertEqual(
            TopicParser.deviceId(from: "a/b/def456abc123/connectionStatus"),
            "def456abc123"
        )
    }
}

final class CredentialTests: XCTestCase {
    func testMillisecondDateRoundTrip() throws {
        let json = #"{"accessToken":"a","refreshToken":"r","expiresAt":1700000000000}"#
        let creds = try JSONDecoder().decode(Credentials.self, from: Data(json.utf8))
        XCTAssertEqual(creds.expiresAt.timeIntervalSince1970, 1700000000, accuracy: 0.001)
        let encoded = try JSONEncoder().encode(creds)
        let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        XCTAssertEqual(object?["expiresAt"] as? Double, 1700000000000)
    }
}

final class HomeDecodingTests: XCTestCase {
    func testDecodesHomesWithNumericModelId() throws {
        let json = """
        [{"homeId":"1234abcd","homeName":"Home","metaTopic":"prefix/1234abcd","spaces":[{"spaceId":"s1","spaceName":"Living Room","devices":[{"deviceId":"a1b2c3d4e5f6","deviceName":"Living Room AC","modelId":102126,"category":"AC","topic":["prefix/1234abcd/a1b2c3d4e5f6"]}]}]}]
        """
        let homes = try JSONDecoder().decode([Home].self, from: Data(json.utf8))
        XCTAssertEqual(homes.count, 1)
        let device = try XCTUnwrap(homes.first?.allDevices.first)
        XCTAssertEqual(device.modelId, "102126")
        XCTAssertTrue(device.isAirConditioner)
        XCTAssertEqual(CommandEncoder.controlTopic(for: device), "prefix/1234abcd/a1b2c3d4e5f6/control")
    }

    func testDecodesIdFallbackField() throws {
        let json = #"[{"id":"home1","homeName":"Home"}]"#
        let homes = try JSONDecoder().decode([Home].self, from: Data(json.utf8))
        XCTAssertEqual(homes.first?.homeId, "home1")
    }
}
