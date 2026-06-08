import Foundation

/// Errors surfaced when resolving a Smart List (saved filter) into tasks.
/// Extracted from `TaskListView` to keep that file under the file-length budget.
enum SavedFilterTaskListError: LocalizedError, CustomStringConvertible {
    case missing
    case corrupt

    var errorDescription: String? {
        switch self {
        case .missing:
            return "This Smart List no longer exists."
        case .corrupt:
            return "This Smart List cannot be decoded. Delete it and save the filter again."
        }
    }

    var description: String {
        errorDescription ?? "Smart List error."
    }
}
