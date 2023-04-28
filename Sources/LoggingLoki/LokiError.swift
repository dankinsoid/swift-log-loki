import struct Foundation.Data
import protocol Foundation.LocalizedError

enum LokiError: LocalizedError, CustomStringConvertible {
    
    case invalidResponse(Data?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let data):
            guard let data else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }
	
	var description: String {
		errorDescription ?? "LokiError"
	}
}
