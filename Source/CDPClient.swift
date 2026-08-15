#if canImport(AppKit)
import Foundation

typealias JSONDictionary = [String: Any]

enum CDPClientError: LocalizedError {
    case invalidMessage
    case closed
    case protocolError(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidMessage: return "The renderer returned an invalid message."
        case .closed: return "The renderer connection was closed."
        case .protocolError(let message): return message
        case .timeout: return "The renderer did not respond in time."
        }
    }
}

final class CDPConnection {
    let targetID: String
    let targetTitle: String
    private let session: URLSession
    private let task: URLSessionWebSocketTask
    private let queue = DispatchQueue(label: "studio.morje.codexlimitpacer.cdp.connection")
    private var nextID = 1
    private var pending: [Int: (Result<JSONDictionary, Error>) -> Void] = [:]
    private var isClosed = false

    var closed: Bool { queue.sync { isClosed } }

    init(targetID: String, title: String, webSocketURL: URL) {
        self.targetID = targetID
        self.targetTitle = title
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        session = URLSession(configuration: configuration)
        task = session.webSocketTask(with: webSocketURL)
        task.resume()
        receiveNext()
    }

    func send(method: String, params: JSONDictionary = [:], completion: ((Result<JSONDictionary, Error>) -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self, !self.isClosed else {
                completion?(.failure(CDPClientError.closed)); return
            }
            let id = self.nextID
            self.nextID += 1
            var payload: JSONDictionary = ["id": id, "method": method]
            if !params.isEmpty { payload["params"] = params }

            guard JSONSerialization.isValidJSONObject(payload),
                  let data = try? JSONSerialization.data(withJSONObject: payload),
                  let string = String(data: data, encoding: .utf8) else {
                completion?(.failure(CDPClientError.invalidMessage)); return
            }

            if let completion {
                self.pending[id] = completion
                self.queue.asyncAfter(deadline: .now() + 5) { [weak self] in
                    guard let self, let callback = self.pending.removeValue(forKey: id) else { return }
                    callback(.failure(CDPClientError.timeout))
                }
            }

            self.task.send(.string(string)) { [weak self] error in
                guard let error else { return }
                self?.queue.async {
                    if let callback = self?.pending.removeValue(forKey: id) { callback(.failure(error)) }
                }
            }
        }
    }

    func evaluate(_ expression: String, completion: @escaping (Result<Any?, Error>) -> Void) {
        send(method: "Runtime.evaluate", params: [
            "expression": expression,
            "returnByValue": true,
            "awaitPromise": true,
            "userGesture": false
        ]) { result in
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success(let response):
                if let exception = response["exceptionDetails"] as? JSONDictionary {
                    let text = exception["text"] as? String ?? "JavaScript evaluation failed."
                    completion(.failure(CDPClientError.protocolError(text)))
                    return
                }
                guard let remote = response["result"] as? JSONDictionary else {
                    completion(.success(nil)); return
                }
                completion(.success(remote["value"]))
            }
        }
    }

    func close() {
        queue.async { [weak self] in
            guard let self, !self.isClosed else { return }
            self.isClosed = true
            self.task.cancel(with: .goingAway, reason: nil)
            self.session.invalidateAndCancel()
            let callbacks = self.pending.values
            self.pending.removeAll()
            callbacks.forEach { $0(.failure(CDPClientError.closed)) }
        }
    }

    private func receiveNext() {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                self.close()
            case .success(let message):
                let data: Data?
                switch message {
                case .string(let text): data = text.data(using: .utf8)
                case .data(let raw): data = raw
                @unknown default: data = nil
                }
                if let data,
                   let object = try? JSONSerialization.jsonObject(with: data) as? JSONDictionary,
                   let id = object["id"] as? Int {
                    self.queue.async {
                        guard let callback = self.pending.removeValue(forKey: id) else { return }
                        if let error = object["error"] as? JSONDictionary {
                            callback(.failure(CDPClientError.protocolError(error["message"] as? String ?? "CDP error")))
                        } else if let result = object["result"] as? JSONDictionary {
                            callback(.success(result))
                        } else {
                            callback(.success([:]))
                        }
                    }
                }
                self.receiveNext()
            }
        }
    }
}
#endif
