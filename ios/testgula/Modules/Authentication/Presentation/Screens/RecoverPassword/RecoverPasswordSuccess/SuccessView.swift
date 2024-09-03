//
//  SuccessView.swift
//  Gula
//
//  Created by Jorge Planells Zamora on 18/7/24.
//

import SwiftUI

struct SuccessView: View {
    @ObservedObject var viewModel: SuccessViewModel
    @Environment(\.presentationMode) var presentation
    
    var body: some View {
        ZStack {
            VStack(spacing: 50) {
                Text("Gula")
                    .font(.system(size: 20))
                    .bold()
                    .padding(.top, 18)
                Image(systemName: "pencil")
                    .frame(width: 100, height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 50)
                            .stroke(.gray)
                    )
                VStack(spacing: 35) {
                    Text("emailSent")
                        .font(.system(size: 20))
                        .bold()
                    Text("emailSentInfo, \(viewModel.email)")
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 34)
                        .font(.system(size: 18))
                    VStack(spacing: 0) {
                        Text("emailNotReceived")
                            .font(.system(size: 14))
                        Button {
                            presentation.wrappedValue.dismiss()
                        } label: {
                            Text("sendAgain")
                                .font(.system(size: 14))
                                .bold()
                                .foregroundStyle(.black)
                                .underline()
                        }
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
