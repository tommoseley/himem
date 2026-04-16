import Foundation
import Network

final class ConnectivityMonitor: ObservableObject {
    static let shared = ConnectivityMonitor()

    @Published var isConnected = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.himem.connectivity")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
