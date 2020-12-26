//
//  Service.swift
//  homework
//
//  Created by Santiago Carmona on 23/12/20.
//  Copyright © 2020 Indigo. All rights reserved.
//

import Foundation
import Combine

protocol APINetworkClient {
    func executeRequest<Response: Codable>(_ endpoint: Endpoint<Response>, completion: @escaping((Result<Response, Error>) -> Void))
}

final class NetworkClient: APINetworkClient {
    private let session: URLSession
    private let requestsInProcessQueue = DispatchQueue(label: "requestsInProcess")
    private var requestsInProcess: [Int: AnyCancellable] = [:]

    init(session: URLSession) {
        self.session = session
    }

    func executeRequest<Response: Codable>(_ endpoint: Endpoint<Response>, completion: @escaping((Result<Response, Error>) -> Void)) {
        guard let urlRequest = endpoint.urlRequest() else {
            completion(.failure(NetworkError.malformedURLRequest))
            return
        }

        let id = urlRequest.hashValue
        let request = self.session.dataTaskPublisher(for: urlRequest)
            .tryMap {
                guard $0.1.hasSuccessStatusCode else {
                    throw self.handleTaskError(data: $0.0, response: $0.1)
                }

                return $0.0
            }
            .decode(type: Response.self, decoder: endpoint.decoder)
            .sink { [weak self] (sinkCompletion) in
                if case .failure(let error) = sinkCompletion {
                    completion(.failure(error))
                }
                self?.requestsInProcessQueue.async(flags: .barrier) {
                    self?.requestsInProcess.removeValue(forKey: id)
                }
            } receiveValue: { (data) in
                completion(.success(data))
            }

        requestsInProcess[id] = request
    }

    private func handleTaskError(data: Data, response: URLResponse) -> Error {
        let error = data.decodeError()
        return NetworkError.invalidStatusCode(
            """
            Status code: \(response.httpStatusCode)
            error: \(error?.error ?? "N/A")
            description: \(error?.errorDescription ?? "N/A")
            """
        )
    }
}

struct DataError: Codable {
    let error: String
    let errorDescription: String

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}


private extension Data {
    func decodeError() -> DataError? {
        try? JSONDecoder().decode(DataError.self, from: self)
    }
}

private extension URLResponse {
    var httpStatusCode: Int {
        (self as? HTTPURLResponse)?.statusCode ?? 418
    }

    var hasSuccessStatusCode: Bool {
        (200 ..< 300) ~= httpStatusCode
    }
}
