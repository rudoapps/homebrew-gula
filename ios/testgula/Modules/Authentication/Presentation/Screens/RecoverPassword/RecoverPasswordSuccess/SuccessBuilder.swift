//
//  SuccessBuilder.swift
//  Gula
//
//  Created by Jorge Planells Zamora on 18/7/24.
//

import Foundation

class SuccessBuilder {
    func build(with email: String) -> SuccessView {
        let viewModel = SuccessViewModel(email: email)
        let view = SuccessView(viewModel: viewModel)
        return view
    }
}
