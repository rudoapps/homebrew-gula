//
//  SuccessViewModel.swift
//  Gula
//
//  Created by Jorge Planells Zamora on 18/7/24.
//

import Foundation

class SuccessViewModel: ObservableObject {
    var email: String
    
    init(email: String) {
        self.email = email
    }
}
