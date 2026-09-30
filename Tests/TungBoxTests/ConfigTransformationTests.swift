import Foundation
import XCTest
@testable import TungBox

final class ConfigTransformationTests: XCTestCase {
    func testCodecPreservesUnknownFieldsAndOrderedValues() throws {
        let source = #"""
        {
          "outbounds": [
            {"tag": "节点二", "type": "custom", "future_option": true},
            {"tag": "节点一", "type": "direct"}
          ],
          "future_section": {
            "label": "中文 😀",
            "values": [null, false, 9223372036854775807, 1.25],
            "url": "https://example.com/a/b?q=测试"
          }
        }
        """#
        let config = try XCTUnwrap(ConfigCodec.parseObject(from: source))
        let rendered = try ConfigCodec.render(config)
        let reparsed = try XCTUnwrap(ConfigCodec.parseObject(from: rendered))

        XCTAssertTrue(NSDictionary(dictionary: config).isEqual(to: reparsed))
        let outbounds = try XCTUnwrap(reparsed["outbounds"] as? [[String: Any]])
        XCTAssertEqual(outbounds.compactMap { $0["tag"] as? String }, ["节点二", "节点一"])
        XCTAssertEqual(outbounds[0]["future_option"] as? Bool, true)
        let section = try XCTUnwrap(reparsed["future_section"] as? [String: Any])
        XCTAssertEqual(section["label"] as? String, "中文 😀")
        let values = try XCTUnwrap(section["values"] as? [Any])
        XCTAssertTrue(values[0] is NSNull)
        XCTAssertEqual((values[2] as? NSNumber)?.int64Value, Int64.max)
    }

    func testCodecRejectsMalformedAndNonObjectJSON() {
        for source in ["", "{", #"{"route":}"#, "[]", "[{}]", "null", "true", "42", #""text""#] {
            XCTAssertNil(ConfigCodec.parseObject(from: source), "应拒绝：\(source)")
        }
        XCTAssertNotNil(ConfigCodec.parseObject(from: "{}"))
        XCTAssertNotNil(ConfigCodec.parseObject(from: " \n {\"route\": {}} \t"))
    }

    func testCodecRetainsPrettyPrintedSortedOutput() throws {
        let config: [String: Any] = ["z": [3, 1, 2], "a": ["y": true, "b": "value"]]
        let expected = """
        {
          "a" : {
            "b" : "value",
            "y" : true
          },
          "z" : [
            3,
            1,
            2
          ]
        }
        """

        XCTAssertEqual(try ConfigCodec.render(config), expected)
        XCTAssertEqual(try ConfigCodec.render([:]), "{\n\n}")
    }

    func testCodecRepeatedRoundTripsDoNotChangeOutput() throws {
        var text = #"{"route":{"rules":[{"outbound":"b"},{"outbound":"a"}]},"unknown":{"enabled":false}}"#
        text = try ConfigCodec.render(XCTUnwrap(ConfigCodec.parseObject(from: text)))
        let firstRender = text

        for _ in 0..<3 {
            text = try ConfigCodec.render(XCTUnwrap(ConfigCodec.parseObject(from: text)))
            XCTAssertEqual(text, firstRender)
        }
    }

}
