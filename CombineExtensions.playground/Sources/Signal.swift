import Combine
import Foundation

public struct Signal<Output> {
  private let publisher: AnyPublisher<Output, Never>
  public init<P>(_ publisher: P) where Output == P.Output, P.Failure == Never, P: Publisher {
    self.publisher = publisher
      .flatMap { o -> AnyPublisher<Output, Never> in
        if Thread.current.isMainThread { return .just(o) }
        return .just(o).eraseToAnyPublisherOnMain()
      }
      .share()
      .eraseToAnyPublisher()
  }
}

internal struct SignalSubscriber<S: Subscriber>: Subscriber {
  typealias Input = S.Input
  typealias Failure = S.Failure
  let combineIdentifier = CombineIdentifier()
  private let subscriber: S

  init(subscriber: S) {
    self.subscriber = subscriber
  }

  func receive(subscription: Subscription) {
    subscriber.receive(subscription: subscription)
  }

  func receive(_ input: Input) -> Subscribers.Demand {
    subscriber.receive(input)
  }

  func receive(completion: Subscribers.Completion<S.Failure>) {
    OnMainQueue {
      subscriber.receive(completion: completion)
    }
  }
}

extension Signal: Publisher {
  public typealias Failure = Never
  public func receive<S>(subscriber: S) where Output == S.Input, Failure == S.Failure, S: Subscriber {
    publisher.receive(subscriber: SignalSubscriber(subscriber: subscriber))
  }
}

public extension Publisher {
  func asSignal(onErrorJustReturn fallbackValue: Output) -> Signal<Output> {
    replaceError(with: fallbackValue)
      .asSignal()
  }
}

public extension Publisher where Failure == Never {
  func asSignal() -> Signal<Output> {
    Signal(self)
  }

}

public extension Signal {
  static func never() -> Signal<Output> {
    AnyPublisher<Output, Never>.never().asSignal()
  }

  static func just(_ e: Output) -> Signal<Output> {
    AnyPublisher<Output, Never>.just(e).asSignal()
  }
}

private func OnMainQueue(after: TimeInterval? = nil, block: @escaping () -> Void) {
    if let timeAfter = after {
        DispatchQueue.main.asyncAfter(deadline: .now() + timeAfter, execute: block)
    } else if Thread.current.isMainThread {
        block()
    } else {
        DispatchQueue.main.async(execute: block)
    }
}
