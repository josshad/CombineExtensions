import Combine
import Foundation
import XCTest

// MARK: Extensions
extension Publisher {
    func withLatestFrom<P>(
        _ other: P
    ) -> AnyPublisher<(Self.Output, P.Output), Failure> where P: Publisher, Self.Failure == P.Failure {
        drop(untilOutputFrom: other)
            .map { (value: $0, token: arc4random()) }
            .combineLatest(other)
            .removeDuplicates(by: { (old, new) in
                let lhs = old.0, rhs = new.0
                return lhs.token == rhs.token
            })
            .map { ($0.value, $1) }
            .eraseToAnyPublisher()
    }

    func ignoreErrorJustComplete(_ onError: ((Error) -> Void)? = nil) -> AnyPublisher<Output, Never> {
        self
            .catch({ error -> AnyPublisher<Output, Never> in
                onError?(error)
                return .empty()
            })
            .eraseToAnyPublisher()
    }
}

extension AnyPublisher {
    static func just(_ o: Output) -> Self {
        Just<Output>(o).setFailureType(to: Failure.self).eraseToAnyPublisher()
    }

    static func error(_ f: Failure) -> Self {
        Fail<Output, Failure>(error: f).eraseToAnyPublisher()
    }

    static func empty() -> Self {
        Empty<Output, Failure>().eraseToAnyPublisher()
    }

    static func never() -> Self {
        Empty<Output, Failure>(completeImmediately: false).eraseToAnyPublisher()
    }
}


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
}

PublisherTest.defaultTestSuite.run()
