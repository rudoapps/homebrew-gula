//
//  Item.swift
//  testgula
//
//  Created by Fernando Salom Carratala on 2/9/24.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
