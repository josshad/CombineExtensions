import Combine
import Foundation
import XCTest

// MARK: Tests
final class PublisherTests: XCTestCase {
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

final class SignalTests: XCTestCase {
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        super.tearDown()
    }

    func testSignal_EmitsElementsOnMainQueue() {
        // :given
        let publisher = [1].publisher
            .receive(on: DispatchQueue(label: "test queue", qos: .userInitiated))

        let signal = publisher.asSignal()
        let exp = expectation(description: #function)

        // :when
        signal
            .sink(
                receiveValue: { _ in
                    XCTDispatchAssertQueue(.main)
                    exp.fulfill()
                }
            )
            .store(in: &cancellables)

        // :then
        waitForExpectations(timeout: 1)
    }

    func testSignal_EmitsElementsOnSameRunLoopCycle_IfElementEmitsOnMainQueueOriginally() {
        // :given
        let refArray = [1, 2, 3]
        let publisher = refArray.publisher
        let signal = publisher.asSignal()

        // :when
        var result: [Int] = []
        signal
            .sink {
                result.append($0)
            }
            .store(in: &cancellables)

        // :then
        XCTAssertEqual(result, refArray)
    }

    func testSignal_SharesInitialPublisher_UnlikeTheAnyPublisher() {
        // :given
        let queue = DispatchQueue.init(label: "Publisher queue")

        let initialPublisher = [(1, 0), (2, 300), (3, 400)]
            .delayedPublisher()
            .receive(on: queue)
        let signal = initialPublisher.asSignal()
        let publisher = initialPublisher.eraseToAnyPublisherOnMain()

        var firstSignalArray: [Int] = []
        var firstPublisherArray: [Int] = []
        var secondSignalArray: [Int] = []
        var secondPublisherArray: [Int] = []
        let exp = expectation(description: "Wait for all publishers")
        exp.expectedFulfillmentCount = 4

        let preExp = expectation(description: "Wait for first values")
        preExp.expectedFulfillmentCount = 2
        preExp.assertForOverFulfill = false

        signal
            .xctExpectsCompletion(with: exp) {
                firstSignalArray.append($0)
                preExp.fulfill()
            }
            .store(in: &cancellables)
        publisher
            .xctExpectsCompletion(with: exp) {
                firstPublisherArray.append($0)
                preExp.fulfill()
            }
            .store(in: &cancellables)

        // :when
        wait(for: [preExp])
        signal
            .xctExpectsCompletion(with: exp) { secondSignalArray.append($0) }
            .store(in: &cancellables)

        publisher
            .xctExpectsCompletion(with: exp) { secondPublisherArray.append($0) }
            .store(in: &cancellables)

        // :then
        waitForExpectations(timeout: 1)
        XCTAssertEqual(firstSignalArray, firstPublisherArray)
        XCTAssertEqual(firstPublisherArray, secondPublisherArray)
        XCTAssertEqual(firstSignalArray, [1, 2, 3])
        XCTAssertEqual(secondSignalArray, [2, 3])
    }

    func testSignal_EmitsCompletionOnMainQueue_IfInitialPublisherReceivesOnAnotherQueue() {
        // :given
        let publisher = [Int]().publisher
            .delay(for: 0.01, scheduler: DispatchQueue.main)
            .receive(on: DispatchQueue(label: "test queue", qos: .userInitiated))
        print("Kek 2")
        let signal = publisher.asSignal()
        print("Kek 1")
        let exp = expectation(description: "Wait for completion")
        print("Kek")

        // :when
        signal
            .sink(
                receiveCompletion: { _ in
                    print("Lol")
                    XCTDispatchAssertQueue(.main)
                    print("XXX")
                    exp.fulfill()
                },
                receiveValue: { _ in

                }
            )
            .store(in: &cancellables)

        // :then
        print("ololo")
        waitForExpectations(timeout: 1)
    }

    func testSignal_EmitsCompletionOnMainQueue_IfValuesAndCompletionReceivedAsynAfterSubscription() {
        // :given
        let subject = PassthroughSubject<Int, Never>()
        let signal = subject.asSignal()
        let exp = expectation(description: #function)

        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(1)) {
            subject.send(1)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(100)) {
            subject.send(completion: .finished)
        }

        // :when
        signal
            .sink(
                receiveCompletion: { _ in
                    XCTDispatchAssertQueue(.main)
                    exp.fulfill()
                },
                receiveValue: { _ in

                }
            )
            .store(in: &cancellables)

        // :then
        waitForExpectations(timeout: 1)
    }
}

PublisherTests.defaultTestSuite.run()
SignalTests.defaultTestSuite.run()

// MARK: Test helpers
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

private extension Publisher where Failure == Never, Output == Int {
    func xctExpectsCompletion(
        with exp: XCTestExpectation,
        receiveValue: @escaping (Int) -> Void
    ) -> AnyCancellable {
        sink(
            receiveCompletion: { _ in exp.fulfill() },
            receiveValue: receiveValue
        )
    }
}

extension Array {
    func delayedPublisher<E>() -> AnyPublisher<E, Never> where Element == (E, Int) {
        publisher
            .flatMap { e -> AnyPublisher<E, Never> in
                let (element, delay) = e
                return AnyPublisher.just(element)
                    .delay(for: .milliseconds(delay), scheduler: RunLoop.main)
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }
}

private func XCTDispatchAssertQueue(
    _ queue: DispatchQueue,
    _ message: String = "XCTDispatchAssertQueue failed") {
    if !queue.isCurrentQueue {
        print("Keks")
        XCTFail(message)
        print("sKek")
    }
}

private func XCTDispatchAssertNotQueue(
    _ queue: DispatchQueue,
    _ message: String = "XCTDispatchAssertNotQueue failed"
) {
    if queue.isCurrentQueue {
        XCTFail(message)
    }
}

private class QueueKey {
    static var shared = QueueKey()
    let currentQueueKey = DispatchSpecificKey<UUID>()
}

private extension DispatchQueue {
    var isCurrentQueue: Bool {
        let value = UUID()
        let key = QueueKey.shared.currentQueueKey
        setSpecific(key: key, value: value)
        return DispatchQueue.getSpecific(key: key) == value
    }
}
