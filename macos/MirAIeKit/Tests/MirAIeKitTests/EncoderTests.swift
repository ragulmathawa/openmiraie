import XCTest
import MirAIeKit

final class EncoderTests: XCTestCase {
    private func makeCatalog() throws -> DeviceCapabilitySet {
        let detail = try JSONDecoder().decode(DeviceModelDetail.self, from: Data(Self.modelJSON.utf8))
        return CapabilityCatalog.catalog(modelId: "102126", detail: detail)
    }

    private func object(_ json: String) throws -> [String: JSONValue] {
        try JSONDecoder().decode([String: JSONValue].self, from: Data(json.utf8))
    }

    func testCatalogParsesControls() throws {
        let catalog = try makeCatalog()
        XCTAssertEqual(catalog.control(named: "ACMode")?.key, "acmd")
        XCTAssertEqual(catalog.control(named: "ACMode")?.ki, 0)
        XCTAssertEqual(catalog.control(named: "ACMode")?.values, ["auto", "cool", "dry", "fan"])
        XCTAssertEqual(catalog.control(named: "PowerStatus")?.key, "ps")
        XCTAssertEqual(catalog.control(named: "PowerStatus")?.ki, 1)
        XCTAssertEqual(catalog.control(named: "ACTemperature")?.min, 16)
        XCTAssertEqual(catalog.control(named: "ACTemperature")?.max, 30)
        XCTAssertEqual(catalog.control(named: "ACTemperature")?.step, 0.5)
        XCTAssertEqual(catalog.control(named: "ACFanSpeed")?.values, ["auto", "low", "medium", "high"])
        XCTAssertEqual(catalog.control(named: "VerticalSwing")?.max, 5)
    }

    func testPowerPayloadMatchesProtocol() throws {
        let catalog = try makeCatalog()
        let payload = try XCTUnwrap(CommandEncoder.payload(for: .power(true), catalog: catalog, sid: 7))
        XCTAssertEqual(try object(#"{"ps":"on","ki":1,"cnt":"an","sid":"7"}"#), payload)
    }

    func testModePayload() throws {
        let catalog = try makeCatalog()
        let payload = try XCTUnwrap(CommandEncoder.payload(for: .mode("cool"), catalog: catalog, sid: 1))
        XCTAssertEqual(try object(#"{"acmd":"cool","ki":0,"cnt":"an","sid":"1"}"#), payload)
    }

    func testTemperaturePayload() throws {
        let catalog = try makeCatalog()
        let payload = try XCTUnwrap(CommandEncoder.payload(for: .temperature(24), catalog: catalog, sid: 2))
        XCTAssertEqual(try object(#"{"actmp":"24.0","ki":2,"cnt":"an","sid":"2"}"#), payload)
    }

    func testFanPayload() throws {
        let catalog = try makeCatalog()
        let payload = try XCTUnwrap(CommandEncoder.payload(for: .fan("auto"), catalog: catalog, sid: 3))
        XCTAssertEqual(try object(#"{"acfs":"auto","ki":4,"cnt":"an","sid":"3"}"#), payload)
    }

    func testSwingPayload() throws {
        let catalog = try makeCatalog()
        let payload = try XCTUnwrap(CommandEncoder.payload(for: .swing(3), catalog: catalog, sid: 4))
        XCTAssertEqual(try object(#"{"acvs":3,"ki":5,"cnt":"an","sid":"4"}"#), payload)
    }

    func testUnsupportedCommandReturnsNil() throws {
        let catalog = try makeCatalog()
        XCTAssertNil(CommandEncoder.payload(for: .toggle(name: "ECOMode", on: true), catalog: catalog, sid: 1))
    }

    static let modelJSON = """
    {
      "controlCapabilities": [
        {"capability": "PowerStatus", "attributes": [{"key": "ps", "values": ["on", "off"]}], "MinFWVersion": 1.0},
        {"capability": "ACMode", "attributes": [{"key": "acmd", "values": ["auto", "cool", "dry", "fan"]}], "MinFWVersion": 1.0},
        {"capability": "ACTemperature", "attributes": [{"key": "actmp", "range": {"min": [{"unit": "celcius", "value": 16}, {"unit": "fahrenheit", "value": 61}], "max": [{"unit": "celcius", "value": 30}, {"unit": "fahrenheit", "value": 86}], "increment": [{"value": 0.5}]}}], "MinFWVersion": 1.0},
        {"capability": "ACFanSpeed", "attributes": [{"key": "acfs", "values": ["auto", "low", "medium", "high"]}], "MinFWVersion": 1.0},
        {"capability": "VerticalSwing", "attributes": [{"key": "acvs", "range": {"min": [{"value": 0}], "max": [{"value": 5}], "increment": [{"value": 1}]}}], "MinFWVersion": 1.0}
      ]
    }
    """
}
