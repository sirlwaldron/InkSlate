import Foundation
import Combine

// MARK: - Search debouncer
class SearchDebouncer: ObservableObject {
    @Published var searchText: String = ""
    @Published var debouncedText: String = ""
    
    private var cancellables = Set<AnyCancellable>()
    private let debounceDelay: TimeInterval
    
    init(delay: TimeInterval = 0.3) {
        self.debounceDelay = delay
        
        $searchText
            .debounce(for: .milliseconds(Int(delay * 1000)), scheduler: DispatchQueue.main)
            .sink { [weak self] value in
                self?.debouncedText = value
            }
            .store(in: &cancellables)
    }
    
    func cancel() {
        cancellables.removeAll()
    }
    
    deinit {
        cancel()
    }
}

