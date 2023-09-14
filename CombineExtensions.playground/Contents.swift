import Combine
import Foundation
import XCTest

// MARK: Tests
class PublisherTest: XCTestCase {
    private var cancellables = Set<AnyCancellable>()
    func testWithLatestFrom_EmitsEvent_FirstSequenceEmitsAfterSecond() {
        // :given
        let left = [1, 2].publisher.delay(for: 0.01, scheduler: DispatchQueue.main)
        let right = [10].publisher
        let refResult = [(1, 10), (2, 10)]
        let sinkExpectation = expectation(description: "sink expectation")

        // :when
        var result: [(Int, Int)]?
        left.withLatestFrom(right)
            .collect()
            .sink {
                result = $0
                sinkExpectation.fulfill()
            }
            .store(in: &cancellables)

        // :then
        waitForExpectations(timeout: 0.1)
        let unwrappedResult = result!
        XCTAssertEqual(refResult.map(\.0), unwrappedResult.map(\.0))
        XCTAssertEqual(refResult.map(\.1), unwrappedResult.map(\.1))
    }

    func testWithLatestFrom_DoesNotEmitEvent_FirstSequenceEmitsButSecondDoesNot() {
        // :given
        let left = [1].publisher.delay(for: 0.01, scheduler: DispatchQueue.main)
        let right = Empty<Int, Never>()
        let sinkExpectation = expectation(description: "sink expectation")
        sinkExpectation.isInverted = true

        // :when
        left.withLatestFrom(right)
            .sink { _ in
                sinkExpectation.fulfill()
            }
            .store(in: &cancellables)

        // :then
        waitForExpectations(timeout: 0.1)
    }

    func testWithLatestFrom_DoesNotEmitEvent_SecondSequenceEmitsAfterFirst() {
        // :given
        let left = [1].publisher
        let right = [2].publisher.delay(for: 0.01, scheduler: DispatchQueue.main)
        let sinkExpectation = expectation(description: "sink expectation")
        sinkExpectation.isInverted = true

        // :when
        left.withLatestFrom(right)
            .sink { _ in
                sinkExpectation.fulfill()
            }
            .store(in: &cancellables)

        // :then
        waitForExpectations(timeout: 0.1)
    }

    func testWithLatestFrom_EmitsEvent_FirstSequenceEmitsWhenSecondIsOptionalAndEmitNil() {
        // :given
        let left = [1].publisher.delay(for: 0.01, scheduler: DispatchQueue.main)
        let right: AnyPublisher<Int?, Never> = .just(nil)
        let refResult: [(Int, Int?)] = [(1, nil)]
        let sinkExpectation = expectation(description: "sink expectation")

        // :when
        var result: [(Int, Int?)]?
        left.withLatestFrom(right)
            .collect()
            .sink {
                result = $0
                sinkExpectation.fulfill()
            }
            .store(in: &cancellables)

        // :then
        waitForExpectations(timeout: 0.1)
        let unwrappedResult = result!
        XCTAssertEqual(refResult.map(\.0), unwrappedResult.map(\.0))
        XCTAssertEqual(refResult.map(\.1), unwrappedResult.map(\.1))
    }

    // MARK: Materialize
    func testMaterialize_CorrectStreamWithCompletion() {
        // :given
        let stream = [1, 2, 3].publisher
        let refEvents: [Materialized<Int, Never>] = [.value(1), .value(2), .value(3), .completed]

        // :when
        var events: [Materialized<Int, Never>] = []
        stream
            .materialize()
            .sink {
                events.append($0)
            }
            .store(in: &cancellables)

        // :then
        XCTAssertEqual(events, refEvents)
    }

    func testMaterialize_CorrectEmptyStream() {
        // :given
        let stream = [Int]().publisher
        let refEvents: [Materialized<Int, Never>] = [.completed]

        // :when
        var events: [Materialized<Int, Never>] = []
        stream
            .materialize()
            .sink {
                events.append($0)
            }
            .store(in: &cancellables)

        // :then
        XCTAssertEqual(events, refEvents)
    }

    func testMaterialize_CorrectErrorStream() {
        // :given
        let error = NSError(domain: "Test domain", code: 1234, userInfo: nil)
        let stream = AnyPublisher<Int, NSError>.error(error)
        let refEvents: [Materialized<Int, NSError>] = [.failed(error)]

        // :when
        var events: [Materialized<Int, NSError>] = []
        stream
            .materialize()
            .sink {
                events.append($0)
            }
            .store(in: &cancellables)

        // :then
        XCTAssertEqual(events, refEvents)
    }

    func testMaterialize_CorrectValueAndErrorStream() {
        // :given
        let error = NSError(domain: "Test domain", code: 1234, userInfo: nil)
        let stream = AnyPublisher<Int, NSError>.error(error)
            .prepend(1)
        let refEvents: [Materialized<Int, NSError>] = [.value(1), .failed(error)]

        // :when
        var events: [Materialized<Int, NSError>] = []
        stream
            .materialize()
            .sink {
                events.append($0)
            }
            .store(in: &cancellables)

        // :then
        XCTAssertEqual(events, refEvents)
    }

    func testMaterialize_CorrectInfiniteEmptyStream() {
        // :given
        let stream = AnyPublisher<Int, Never>.never()
        let exp = expectation(description: "Should not called")
        exp.isInverted = true

        // :when
        stream
            .materialize()
            .sink { _ in
                exp.fulfill()
            }
            .store(in: &cancellables)

        // :then
        waitForExpectations(timeout: 1)
    }

    // MARK: Denesification
    func testDenestification_ThreeValues() {
        // :given
        let a = 1
        let b = 2.0
        let c = "C"
        let refValues = (a, b, c)
        let t2v1 = [((a, b), c)].publisher
        let v1t2 = [(a, (b, c))].publisher

        // :when
        var values: [(Int, Double, String)] = []
        Publishers.Merge(
            t2v1.denestify(),
            v1t2.denestify()
        )
        .sink {
            values.append($0)
        }
        .store(in: &cancellables)

        // :then
        XCTAssertTrue(values.allSatisfy { $0 == refValues})
    }

    func testDenestification_FourValues() {
        // :given
        let a = 1
        let b = 2.0
        let c = "C"
        let d = Date()
        let refValues = (a, b, c, d)
        let t2v2 = [((a, b), c, d)].publisher
        let v1t2v1 = [(a, (b, c), d)].publisher
        let v2t2 = [(a, b, (c, d))].publisher
        let t2t2 = [((a, b), (c, d))].publisher
        let t3v1 = [((a, b, c), d)].publisher
        let v1t3 = [(a, (b, c, d))].publisher

        let t2t1v1 = [(((a, b), c), d)].publisher
        let t1t2v1 = [((a, (b, c)), d)].publisher
        let v1t2t1 = [(a, ((b, c), d))].publisher
        let v1t1t2 = [(a, (b, (c, d)))].publisher

        // :when
        var values: [(Int, Double, String, Date)] = []
        Publishers.MergeMany([
            t2v2.denestify(),
            v1t2v1.denestify(),
            v2t2.denestify(),
            t2t2.denestify(),
            t3v1.denestify(),
            v1t3.denestify(),
            t2t1v1.denestify(),
            t1t2v1.denestify(),
            v1t2t1.denestify(),
            v1t1t2.denestify()
        ])
        .sink {
            values.append($0)
        }
        .store(in: &cancellables)

        // :then
        XCTAssertTrue(values.allSatisfy { $0 == refValues})
    }
}

PublisherTest.defaultTestSuite.run()

extension Materialized: Equatable where Value: Equatable, Failure: Equatable {
    public static func == (lhs: Materialized, rhs: Materialized) -> Bool {
        switch (lhs, rhs) {
        case (.completed, .completed): return true
        case (.failed(let le), .failed(let re)): return le == re
        case (.value(let lv), .value(let rv)): return lv == rv
        default: return false
        }
    }
}
