import XCTest
@testable import PerchKit

/// The app's springs and eases as plain functions of time, so a snapshot can hold any moment of a
/// movement where the animation itself would be. They must match SwiftUI's own curves.
final class MotionCurveTests: XCTestCase {
    func testASpringStartsAtRestAndSettlesOnTheTarget() {
        let spring = MotionCurve.spring(response: 0.3, damping: 0.8)
        XCTAssertEqual(spring.value(at: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(spring.value(at: -1), 0, accuracy: 1e-9)
        XCTAssertEqual(spring.value(at: 3), 1, accuracy: 1e-6)
    }

    func testAnUnderdampedSpringOvershootsByTheTextbookAmount() {
        // Peak of a damped oscillator from rest: 1 + exp(-ζπ/√(1-ζ²)), at t = π/ωd.
        let response = 0.3, damping = 0.8
        let spring = MotionCurve.spring(response: response, damping: damping)
        let omega = 2 * Double.pi / response
        let peakTime = Double.pi / (omega * (1 - damping * damping).squareRoot())
        let expected = 1 + exp(-damping * Double.pi / (1 - damping * damping).squareRoot())
        XCTAssertEqual(spring.value(at: peakTime), expected, accuracy: 1e-9)
        // And nowhere else goes higher.
        let highest = stride(from: 0.0, through: 2, by: 0.001).map { spring.value(at: $0) }.max() ?? 0
        XCTAssertEqual(highest, expected, accuracy: 1e-5)
    }

    func testACriticallyDampedSpringNeverPassesTheTarget() {
        let spring = MotionCurve.spring(response: 0.22, damping: 1)
        let values = stride(from: 0.0, through: 2, by: 0.005).map { spring.value(at: $0) }
        XCTAssertTrue(values.allSatisfy { $0 <= 1 + 1e-12 })
        XCTAssertEqual(zip(values, values.dropFirst()).filter { $1 < $0 - 1e-12 }.count, 0, "it only ever moves forward")
        XCTAssertEqual(spring.value(at: 1), 1, accuracy: 1e-4)
    }

    func testAnOverdampedSpringIsSlowerThanACriticalOne() {
        let critical = MotionCurve.spring(response: 0.3, damping: 1)
        let over = MotionCurve.spring(response: 0.3, damping: 1.4)
        XCTAssertLessThan(over.value(at: 0.1), critical.value(at: 0.1))
        XCTAssertEqual(over.value(at: 4), 1, accuracy: 1e-4)
    }

    func testEaseOutIsCSSEaseOutOverItsDuration() {
        let ease = MotionCurve.easeOut(duration: 0.46)
        XCTAssertEqual(ease.value(at: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(ease.value(at: 0.46), 1, accuracy: 1e-9)
        XCTAssertEqual(ease.value(at: 1), 1, accuracy: 1e-9)
        // cubic-bezier(0, 0, 0.58, 1) is front-loaded: at the halfway time it is well past half.
        XCTAssertGreaterThan(ease.value(at: 0.23), 0.6)
        // Known point of that curve: at x = 0.5 the bezier gives y ≈ 0.6853.
        XCTAssertEqual(ease.value(at: 0.23), 0.6853, accuracy: 0.002)
        let values = stride(from: 0.0, through: 0.46, by: 0.01).map { ease.value(at: $0) }
        XCTAssertEqual(zip(values, values.dropFirst()).filter { $1 < $0 }.count, 0)
    }

    func testEaseInOutIsSymmetric() {
        let ease = MotionCurve.easeInOut(duration: 2)
        XCTAssertEqual(ease.value(at: 1), 0.5, accuracy: 1e-6)
        XCTAssertEqual(ease.value(at: 0.5) + ease.value(at: 1.5), 1, accuracy: 1e-6)
    }

    func testADelayHoldsTheStart() {
        let ease = MotionCurve.easeOut(duration: 0.22)
        XCTAssertEqual(ease.value(at: 0.05, delay: 0.08), 0, accuracy: 1e-9)
        XCTAssertEqual(ease.value(at: 0.30, delay: 0.08), 1, accuracy: 1e-9)
    }

    func testSettlingTimeIsWhenItStaysCloseForGood() {
        let spring = MotionCurve.spring(response: 0.3, damping: 0.8)
        let settled = spring.settlingTime(tolerance: 0.001)
        XCTAssertGreaterThan(settled, 0.2)
        XCTAssertLessThan(settled, 1)
        for time in stride(from: settled, through: settled + 1, by: 0.002) {
            XCTAssertEqual(spring.value(at: time), 1, accuracy: 0.001)
        }
        XCTAssertEqual(MotionCurve.easeOut(duration: 0.18).settlingTime(), 0.18, accuracy: 0.01)
    }
}
