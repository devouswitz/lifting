#if STANDALONE_CHECKS
import Foundation

// Run the exact XCTest test cases on machines with Command Line Tools but no XCTest SDK.
class XCTestCase {}
enum CheckFailure: Error { case unwrap }
var failedChecks = 0
func fail(_ text: String, file: StaticString, line: UInt) { failedChecks += 1; print("FAIL \(file):\(line): \(text)") }
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) { if a != b { fail("\(a) != \(b)", file: file, line: line) } }
func XCTAssertEqual(_ a: Double, _ b: Double, accuracy: Double, file: StaticString = #filePath, line: UInt = #line) { if abs(a - b) > accuracy { fail("\(a) != \(b)", file: file, line: line) } }
func XCTAssertNotEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) { if a == b { fail("Values match", file: file, line: line) } }
func XCTAssertLessThan<T: Comparable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) { if !(a < b) { fail("\(a) >= \(b)", file: file, line: line) } }
func XCTAssertTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { if !value { fail("Expected true", file: file, line: line) } }
func XCTAssertFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { if value { fail("Expected false", file: file, line: line) } }
func XCTAssertNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) { if value != nil { fail("Expected nil", file: file, line: line) } }
func XCTAssertNotNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) { if value == nil { fail("Expected value", file: file, line: line) } }
func XCTAssertNoThrow<T>(_ body: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) { do { _ = try body() } catch { fail(error.localizedDescription, file: file, line: line) } }
func XCTAssertThrowsError<T>(_ body: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) { do { _ = try body(); fail("Expected error", file: file, line: line) } catch {} }
func XCTUnwrap<T>(_ value: T?) throws -> T { guard let value else { throw CheckFailure.unwrap }; return value }
#endif
