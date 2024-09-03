//
//  RecoverPasswordView.swift
//  Gula
//
//  Created by Jorge Planells Zamora on 17/7/24.
//

import SwiftUI

struct RecoverPasswordView: View {
    @ObservedObject var viewModel: RecoverPasswordViewModel
    @State private var errorTitle: LocalizedStringKey = ""
    @State private var errorMessage: LocalizedStringKey = ""
    @State private var showAlert = false
    @FocusState private var isEmailFieldFocused: Bool
    @Environment(\.presentationMode) var presentation
    
    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    DispatchQueue.main.async {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to:nil, from:nil, for:nil)
                    }
                }
            VStack(spacing: 30) {
                Text("recoverPasswordInfo")
                    .multilineTextAlignment(.center)
                    .font(.system(size: 14))
                    .padding(.horizontal, 56)
                    .padding(.top, 36)
                VStack(spacing: 20) {
                    CustomTextField(text: $viewModel.email,
                                    isFieldValid: $viewModel.uiState.isEmailValid,
                                    title: "email",
                                    placeholder: "writeEmail",
                                    errorMessage: "wrongEmailFormat",
                                    isFieldMandotory: true
                    )
                    CustomButton(buttonState: $viewModel.uiState.sendButtonState,
                                 type: .secondary,
                                 buttonText: "send") {
                        viewModel.recoverPassword()
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
        }
        .navigationDestination(isPresented: $viewModel.uiState.hasEmailBeenSent, destination: {
            SuccessBuilder().build(with: viewModel.email)
        })
        .navigationBarBackButtonHidden()
        .onChange(of: viewModel.uiState.authError, {
            _, error in
            guard let error = error else { return }
            set(this: error)
        })
        .alert(isPresented: $showAlert) {
            Alert(title: Text(errorTitle), message: Text(errorMessage), dismissButton: .default(Text("Accept"), action: {
                viewModel.closeAlert()
            }))
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("recoverPassword")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
            }
            ToolbarItem(placement: .topBarLeading) {
                HStack {
                    Button {
                        presentation.wrappedValue.dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .resizable()
                            .frame(maxWidth: 16, maxHeight: 16)
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .toolbarBackground(.grayCustom5, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
    
    func set(this error: AuthError) {
        switch error {
        case .badCredentials(let message):
            errorTitle = "wrongCredentials"
            errorMessage = LocalizedStringKey(message)
        case .customError(let message):
            errorTitle = "tryAgain"
            errorMessage = LocalizedStringKey(message)
        case .generalError:
            errorTitle = "tryAgain"
            errorMessage = "generalError"
        }
        showAlert = true
    }
}
