import Foundation
import SwiftUI

/// Structured error types for Hi Mem. Every catch block should use these
/// instead of print(). Errors surface to the UI via ViewModel @Published state.
enum AppError: LocalizedError, Identifiable {
    case saveFailed(String)
    case editFailed(String)
    case deleteFailed(String)
    case processingFailed(String)
    case networkError(String)
    case mediaError(String)
    case topicError(String)
    case projectError(String)
    case searchFailed(String)
    case albumSyncFailed(String)

    var id: String { errorDescription ?? "unknown" }

    var errorDescription: String? {
        switch self {
        case .saveFailed(let detail): return "Couldn't save: \(detail)"
        case .editFailed(let detail): return "Couldn't edit: \(detail)"
        case .deleteFailed(let detail): return "Couldn't delete: \(detail)"
        case .processingFailed(let detail): return "Processing failed: \(detail)"
        case .networkError(let detail): return "Network error: \(detail)"
        case .mediaError(let detail): return "Media error: \(detail)"
        case .topicError(let detail): return "Topic error: \(detail)"
        case .projectError(let detail): return "Project error: \(detail)"
        case .searchFailed(let detail): return "Search failed: \(detail)"
        case .albumSyncFailed(let detail): return "Album sync failed: \(detail)"
        }
    }
}

/// Observable error state that ViewModels publish and views consume.
@MainActor
class ErrorState: ObservableObject {
    static let shared = ErrorState()
    @Published var current: AppError? = nil

    func report(_ error: AppError) {
        current = error
        // Auto-dismiss after 5 seconds
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if current?.id == error.id {
                current = nil
            }
        }
    }

    func dismiss() {
        current = nil
    }
}
