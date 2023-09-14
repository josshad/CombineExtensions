import Foundation
import Combine

// MARK: Extensions
public extension Publisher {
  func eraseToAnyPublisherOnMain() -> AnyPublisher<Output, Failure> {
    receive(on: DispatchQueue.main)
      .eraseToAnyPublisher()
  }

  func compactMap<T>() -> Publishers.CompactMap<Self, T> where Output == T? {
    compactMap { $0 }
  }

  func flatMapLatest<P>(
    _ transform: @escaping (Self.Output) -> P
  ) -> AnyPublisher<P.Output, P.Failure> where P: Publisher, Self.Failure == P.Failure {
    map(transform)
      .switchToLatest()
      .eraseToAnyPublisher()
  }

  func compactFlatMapLatest<O, P>(
    _ transform: @escaping (O) -> P
  ) -> AnyPublisher<P.Output, P.Failure> where P: Publisher, Failure == P.Failure, O? == Output {
    compactMap()
      .flatMapLatest(transform)
      .eraseToAnyPublisher()
  }

  func combineLatest<Others: Collection>(
    _ others: Others
  ) -> AnyPublisher<[Output], Failure> where Others.Element: Publisher, Others.Element.Output == Output, Others.Element.Failure == Failure {
    let seed = map { [$0] }.eraseToAnyPublisher()

    return others.reduce(seed) { combined, next in
      combined
        .combineLatest(next)
        .map { $0 + [$1] }
        .eraseToAnyPublisher()
    }
  }

  func handleEvents(
    receiveSubscription: ((Subscription) -> Void)? = nil,
    receiveOutput: ((Self.Output) -> Void)? = nil,
    receiveSuccess: (() -> Void)? = nil,
    receiveFailure: ((Self.Failure) -> Void)? = nil,
    receiveCancel: (() -> Void)? = nil,
    receiveRequest: ((Subscribers.Demand) -> Void)? = nil
  ) -> Publishers.HandleEvents<Self> {
    handleEvents(
      receiveSubscription: receiveSubscription,
      receiveOutput: receiveOutput,
      receiveCompletion: { completion in
        switch completion {
        case .finished: receiveSuccess?()
        case .failure(let err): receiveFailure?(err)
        }
      },
      receiveCancel: receiveCancel,
      receiveRequest: receiveRequest
    )
  }

  func withLatestFrom<P>(
    _ other: P
  ) -> AnyPublisher<(Self.Output, P.Output), Failure> where P: Publisher, Self.Failure == P.Failure {
    let other = other
    // Note: it's tempting to just use `.map(Optiona.some)` and `.prepend(nil)`.
    // But this won't work correctly with following `.combineLatest` if P.Output itself is Optional.
    // In this case prepended `Optional.some(nil)` will become just `nil` after `combineLatest`.
    // Seems like a bug.
    //
    // Note 2: it's tempting to use `drop(untilOutputFrom: other)` to ignore elements from the sequence.
    // But in this case we should share other sequence, otherwise client of the API may get
    // unexpected number of subscriptions to the passed sequence which can result, for example, in multiple network calls.
    // Sharing leads to problems with 'constant' sequences like Just(value) or [value].publisher:
    //   it eppears that `drop` consumes all elements upon subscription and `combineLatest` operator gets nothing.
      .map { (value: $0, ()) }
      .prepend((value: nil, ()))
    var token = 0
    return map { (value: $0, token: token.advance(by: 1)) }
      .combineLatest(other)
      .removeDuplicates(by: { (old, new) in
        let lhs = old.0, rhs = new.0
        return lhs.token == rhs.token
      })
      .map { ($0.value, $1.value) }
      .compactMap { (left, right) in
        right.map { (left, $0) }
      }
      .eraseToAnyPublisher()
  }

  /**
   Returns a Publisher that emits item emitted by source Publisher when latest item of predicate Publisher is true
   - parameter predicate: Publisher that controls when filter items from source observable
   - parameter latest: Should the last __not taken__ element from source Publisher be reproduced when predicate changed to true

   Marbles:
   # latest = false
   * s: `--A----B----C-------D-----E-`
   * p: `f---------t--f---t-f-t------`
   * o: `------------C-------------E-`

   # latest = true
   * s: `--A----B----C-------D-----E-`
   * p: `f---------t--f---t-f-t------`
   * o: `----------B-C--------D----E-`
   */
  func takeWhen<P>(
    _ predicate: P,
    latest: Bool = false
  ) -> AnyPublisher<Output, Failure> where P: Publisher, P.Output == Bool, P.Failure == Self.Failure {
    switch latest {
    case false:
      return withLatestFrom(predicate)
        .filter { _, predicate in
          predicate
        }
        .map { source, _ in
          source
        }
        .eraseToAnyPublisher()
    case true:
      return map { (value: $0, token: Int.positiveRangeRandom) }
        .combineLatest(predicate.removeDuplicates())
        .filter { _, predicate in
          predicate
        }
        .removeDuplicates(by: { (old, new) in
          let lhs = old.0, rhs = new.0
          return lhs.token == rhs.token
        })
        .map { sourcePair, _ in
          sourcePair.value
        }
        .eraseToAnyPublisher()
    }
  }

  func ignoreErrorJustComplete(_ onError: ((Error) -> Void)? = nil) -> AnyPublisher<Output, Never> {
    self
      .catch { e -> AnyPublisher<Output, Never> in
        onError?(e)
        return .empty()
      }
      .eraseToAnyPublisher()
  }

  func replaceError(using transform: @escaping (Failure) -> Output) -> AnyPublisher<Output, Never> {
    self
      .catch { e -> AnyPublisher<Output, Never> in
          .just(transform(e))
      }
      .eraseToAnyPublisher()
  }

  func materialize() -> AnyPublisher<Materialized<Output, Failure>, Never> {
    map(Materialized.value)
      .append(.completed)
      .replaceError { .failed($0) }
      .eraseToAnyPublisher()
  }
}

public extension Publisher where Failure == Never {
  func flatMapLatest<P>(
    _ transform: @escaping (Self.Output) -> P
  ) -> AnyPublisher<P.Output, P.Failure> where P: Publisher {
    map(transform)
      .switchToLatest()
      .eraseToAnyPublisher()
  }
}

public extension AnyPublisher {
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

public extension Publishers.CombineLatest where A.Output: Equatable, B.Output: Equatable {
  func removeDuplicates() -> AnyPublisher<Output, Failure> {
    removeDuplicates { lhs, rhs in
      lhs.0 == rhs.0 && lhs.1 == rhs.1
    }
    .eraseToAnyPublisher()
  }
}

public extension Publishers.CombineLatest3 where A.Output: Equatable, B.Output: Equatable, C.Output: Equatable {
  func removeDuplicates() -> AnyPublisher<Output, Failure> {
    removeDuplicates { lhs, rhs in
      lhs.0 == rhs.0 && lhs.1 == rhs.1 && lhs.2 == rhs.2
    }
    .eraseToAnyPublisher()
  }
}

public extension Publisher {
  func denestify<A, B, C>() -> AnyPublisher<(A, B, C), Failure> where Output == ((A, B), C) {
    map { ($0.0, $0.1, $1) }.eraseToAnyPublisher()
  }

  func denestify<A, B, C>() -> AnyPublisher<(A, B, C), Failure> where Output == (A, (B, C)) {
    map { ($0, $1.0, $1.1) }.eraseToAnyPublisher()
  }

  func denestify<A, B, C, D>() -> AnyPublisher<(A, B, C, D), Failure> where Output == ((A, B, C), D) {
    map { ($0.0, $0.1, $0.2, $1) }.eraseToAnyPublisher()
  }

  func denestify<A, B, C, D>() -> AnyPublisher<(A, B, C, D), Failure> where Output == (A, (B, C, D)) {
    map { ($0, $1.0, $1.1, $1.2) }.eraseToAnyPublisher()
  }

  func denestify<A, B, C, D>() -> AnyPublisher<(A, B, C, D), Failure> where Output == ((A, B), (C, D)) {
    map { ($0.0, $0.1, $1.0, $1.1) }.eraseToAnyPublisher()
  }

  func denestify<A, B, C, D>() -> AnyPublisher<(A, B, C, D), Failure> where Output == ((A, B), C, D) {
    map { ($0.0, $0.1, $1, $2) }.eraseToAnyPublisher()
  }

  func denestify<A, B, C, D>() -> AnyPublisher<(A, B, C, D), Failure> where Output == (A, (B, C), D) {
    map { ($0, $1.0, $1.1, $2) }.eraseToAnyPublisher()
  }

  func denestify<A, B, C, D>() -> AnyPublisher<(A, B, C, D), Failure> where Output == (A, B, (C, D)) {
    map { ($0, $1, $2.0, $2.1) }.eraseToAnyPublisher()
  }

  func denestify<A, B, C, D>() -> AnyPublisher<(A, B, C, D), Failure> where Output == (((A, B), C), D) {
    map { ($0.0.0, $0.0.1, $0.1, $1) }.eraseToAnyPublisher()
  }

  func denestify<A, B, C, D>() -> AnyPublisher<(A, B, C, D), Failure> where Output == ((A, (B, C)), D) {
    map { ($0.0, $0.1.0, $0.1.1, $1) }.eraseToAnyPublisher()
  }

  func denestify<A, B, C, D>() -> AnyPublisher<(A, B, C, D), Failure> where Output == (A, (B, (C, D))) {
    map { ($0, $1.0, $1.1.0, $1.1.1) }.eraseToAnyPublisher()
  }

  func denestify<A, B, C, D>() -> AnyPublisher<(A, B, C, D), Failure> where Output == (A, ((B, C), D)) {
    map { ($0, $1.0.0, $1.0.1, $1.1) }.eraseToAnyPublisher()
  }
}


public enum Materialized<Value, Failure> {
  case value(Value)
  case completed
  case failed(Failure)
}

private extension Int {
  mutating func advance(by: Int) -> Int {
    self += by
    return self
  }

  static var positiveRangeRandom: Int {
    Int.random(in: 0..<Int.max)
  }
}

