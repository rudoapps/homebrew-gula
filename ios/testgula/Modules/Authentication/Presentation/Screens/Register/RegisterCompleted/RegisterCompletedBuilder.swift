//
//  RegisterCompletedBuilder.swift
//  Gula
//
//  Created by María Sogrob Garrido on 5/8/24.
//

import Foundation

class RegisterCompletedBuilder {
    func build(with id: String) -> RegisterCompletedView {
        let viewModel = RegisterCompletedViewModel()
        let view = RegisterCompletedView(viewModel: viewModel)
        return view
    }
}
