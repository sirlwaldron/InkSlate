//
//  SearchDebouncer.swift
//  InkSlate
//
//  Created by Performance Optimization on 9/30/25.
//

import Foundation
import Combine

// MARK: - Search Debouncer
class SearchDebouncer: ObservableObject {
    @Published var searchText: String = ""
    @Published var debouncedText: String = ""
    
    private var cancellables = Set<AnyCancellable>()
    private let debounceDelay: TimeInterval
    
    init(delay: TimeInterval = 0.3) {
        self.debounceDelay = delay
        
        // Debounce search text changes
        $searchText
            .debounce(for: .milliseconds(Int(delay * 1000)), scheduler: DispatchQueue.main)
            .assign(to: \.debouncedText, on: self)
            .store(in: &cancellables)
    }
    
    func cancel() {
        cancellables.removeAll()
    }
    
    deinit {
        cancel()
    }
}

