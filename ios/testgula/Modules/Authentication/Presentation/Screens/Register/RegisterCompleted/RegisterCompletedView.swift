//
//  RegisterCompletedView.swift
//  Gula
//
//  Created by María Sogrob Garrido on 5/8/24.
//

import SwiftUI

struct RegisterCompletedView: View {
    @EnvironmentObject var deeplinkManager: DeepLinkManager
    @ObservedObject var viewModel: RegisterCompletedViewModel
    @Environment(\.presentationMode) var presentation
    
    var body: some View {
        ZStack {
            VStack(spacing: 50) {
                Text("Gula")
                    .font(.system(size: 20))
                    .padding(.top, 18)
                Image(systemName: "pencil")
                    .frame(width: 100, height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 50)
                            .stroke(.gray)
                    )
                
                VStack(spacing: 35) {
                    Text("RegisterCompletedTitle")
                        .font(.system(size: 20))
                    Text("registerCompletedText")
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 34)
                        .font(.system(size: 18))
                    Button {
                        deeplinkManager.screen = .none
                    } label: {
                        Text("goBackToHomeText")
                            .font(.system(size: 14))
                            .foregroundStyle(.black)
                            .underline()
                    }
                    
                }
                Spacer()
            }
            .toolbar(.hidden, for: .navigationBar)
            .padding(.horizontal, 16)
        }
        .navigationBarBackButtonHidden()
    }
}

#Preview {
    RegisterCompletedBuilder().build(with: "")
}
