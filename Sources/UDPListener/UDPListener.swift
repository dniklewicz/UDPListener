import Combine
import Foundation
import Network

public enum UDPListenerError: Error {
	case emptyData
	case other(Error)
}

public class UDPListener: ObservableObject {
	private(set) public var listener: NWListener?
	private var connection: NWConnection?
	private let queue = DispatchQueue.global(qos: .userInitiated)
	
	public let message: PassthroughSubject<Data, UDPListenerError> = .init()
	
	@Published private(set) public var isReady: Bool = false
	public var isReadyPublisher: Published<Bool>.Publisher { $isReady }
	
	public var isListening: Bool = true
	
	public init(on port: NWEndpoint.Port) throws {
		let params = NWParameters.udp
		params.allowFastOpen = true
		params.allowLocalEndpointReuse = true
		
		self.listener = try NWListener(using: params, on: port)
		self.listener?.stateUpdateHandler = { update in
			switch update {
			case .ready:
				self.isReady = true
			case .failed, .cancelled:
				self.isListening = false
				self.isReady = false
			default:
				break
			}
		}
		self.listener?.newConnectionHandler = { connection in
			print("Listener receiving new message")
			self.process(connection: connection)
		}
		self.listener?.start(queue: self.queue)
	}
	
	func process(connection: NWConnection) {
		self.connection = connection
		self.connection?.stateUpdateHandler = { newState in
			switch newState {
			case .ready:
				self.receive()
			case .cancelled, .failed:
				self.listener?.cancel()
				self.isListening = false
			default:
				break
			}
		}
		self.connection?.start(queue: .global())
	}
	
	func receive() {
		connection?.receiveMessage { [weak self] data, context, isComplete, error in
			if let error {
				self?.message.send(completion: .failure(.other(error)))
				return
			}
			guard isComplete, let data else {
				self?.message.send(completion: .failure(.emptyData))
				return
			}
			self?.message.send(data)
			if self?.isListening == true {
				self?.receive()
			}
		}
	}
	
	public func cancel() {
		self.isListening = false
		self.connection?.cancel()
	}
}
