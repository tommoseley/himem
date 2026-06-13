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
        // User-facing strings only — stock human sentences. The raw
        // `detail` payload on each case stays inside the enum (for
        // NSLog and telemetry); we don't dump it at the user. Per
        // Troika UX review: alerts were leaking `NSOSStatusErrorDomain
        // Code=-50` and `CoreData merge conflict` directly into the
        // toast text. Honest copy now, raw still available via
        // `rawDetail` for logging.
        switch self {
        case .saveFailed: return "Couldn't save that. Try again in a moment."
        case .editFailed: return "Couldn't apply your edit. Try again in a moment."
        case .deleteFailed: return "Couldn't delete that. Try again in a moment."
        case .processingFailed: return "Something went wrong while organizing this memory."
        case .networkError: return "Network's unreachable. Check your connection and try again."
        case .mediaError: return "Couldn't load that media."
        case .topicError: return "Couldn't update the topic."
        case .projectError: return "Couldn't update the project."
        case .searchFailed: return "Search hit a problem. Try again."
        case .albumSyncFailed: return "Couldn't sync to Photos. We'll try again next time."
        }
    }

    /// The raw underlying-error detail — for NSLog, telemetry, and
    /// crash-reporter context. NEVER shown directly to the user;
    /// `errorDescription` is the only surface that goes to the UI.
    var rawDetail: String {
        switch self {
        case .saveFailed(let d), .editFailed(let d), .deleteFailed(let d),
             .processingFailed(let d), .networkError(let d), .mediaError(let d),
             .topicError(let d), .projectError(let d), .searchFailed(let d),
             .albumSyncFailed(let d):
            return d
        }
    }
}

/// Observable error state that ViewModels publish and views consume.
@MainActor
class ErrorState: ObservableObject {
    static let shared = ErrorState()
    @Published var current: AppError? = nil

    func report(_ error: AppError) {
        // The raw detail never reaches the UI string (see
        // `AppError.errorDescription`); surface it in NSLog so the
        // diagnostic context is still there in device logs and Console.
        NSLog("[HiMem][AppError] \(error): \(error.rawDetail)")
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
