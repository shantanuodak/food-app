import Foundation
import Network
import Combine

final class NetworkStatusMonitor {
    @Published private(set) var isReachable: Bool = true
    @Published private(set) var isConstrained: Bool = false
    @Published private(set) var isExpensive: Bool = false

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "food.app.network.monitor")

    init() {
        monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isReachable = (path.status == .satisfied)
                self?.isConstrained = path.isConstrained
                self?.isExpensive = path.isExpensive
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
