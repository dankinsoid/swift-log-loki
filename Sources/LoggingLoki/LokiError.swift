import Foundation

enum LokiError: LocalizedError {
    
    case invalidResponse(Data)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse(let data):
            return String(data: data, encoding: .utf8)
        }
    }
}
