/*
 * Copyright (c) 2020, Psiphon Inc.
 * All rights reserved.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

import XCTest
import ReactiveSwift
import SwiftCheck
import Testing
@testable import PsiApi
@testable import AppStoreIAP
@testable import PsiApiTestingCommon

final class SubscriptionAuthStateTest : XCTestCase {

    /// Test which checks that recursively running the resulting actions of a single action
    /// through the reducer will eventually terminate. This is not done direcly, but the test
    /// will run forever and eventually be killed if this occurs.
    /// Additionally expected state changes are checked.
    func testExternalActions() {
        property("Subscription auth state reducer") <- forAll {
            (action: SubscriptionAuthStateAction,
            state: SubscriptionReducerState,
            env: SubscriptionAuthStateReducerEnvironment) in

            var actions = [action]
            var inputState = state
            
            while let action = actions.popLast() {

                let output = SubscriptionAuthStateTest.runReducer(effectsTimeout: 5,
                                                                  state: inputState,
                                                                  action: action,
                                                                  env: env)

                let newActions =
                    output.actions.compactMap { (x: [Signal<SubscriptionAuthStateAction, SignalProducer<SubscriptionAuthStateAction, Never>.SignalError>.Event]) -> [SubscriptionAuthStateAction] in

                        return x.compactMap { (y: Signal<SubscriptionAuthStateAction, SignalProducer<SubscriptionAuthStateAction, Never>.SignalError>.Event) -> SubscriptionAuthStateAction? in
                            
                            switch y {
                            case .value(let action):
                                return .some(action)
                            default:
                                return .none
                            }
                        }
                    }.flatMap{$0}

                // Add new actions so the last element is the next action.
                actions.append(contentsOf: newActions.reversed())

                switch action {
                case .localDataUpdate(type: _):

                    if output.state != inputState {
                        return (output.state ==== inputState)
                    }

                case .didLoadStoredPurchaseAuthState(loadResult: let loadResult,
                                                     replayDataUpdate: _):
                    switch loadResult {
                    case .success(let loadedValue):
                        var stateCopy = inputState
                        stateCopy.subscription.purchasesAuthState = loadedValue

                        if output.state != stateCopy {
                            return (output.state ==== stateCopy) <?> ".didLoadStoredPurchaseAuthState.sucess"
                        }

                    case .failure(_):
                        var stateCopy = inputState
                        stateCopy.subscription.purchasesAuthState = [:]

                        if output.state != stateCopy {
                            return (output.state ==== stateCopy) <?> ".didLoadStoredPurchaseAuthState.failure"
                        }
                    }

                case ._localDataUpdateResult(_):
                    // Purchases auth state may have changed by:
                    // - being marked as rejected by Psiphon
                    // - being changed from marked as rejected with 400 to not requested
                    var stateCopy = inputState
                    stateCopy.subscription.purchasesAuthState =
                        output.state.subscription.purchasesAuthState
                    break

                case .requestAuthorizationForPurchases:
                    // Txns pending auth request may have changed

                    if (output.state.subscription.transactionsPendingAuthRequest !=
                        inputState.subscription.transactionsPendingAuthRequest) {

                        // Check that max one txn was inserted as pending auth request

                        let diff = output.state.subscription.transactionsPendingAuthRequest.subtracting(inputState.subscription.transactionsPendingAuthRequest)

                        if diff.count > 1 {
                            // Ensure diff is logged
                            return (
                                output.state.subscription.transactionsPendingAuthRequest ====
                                inputState.subscription.transactionsPendingAuthRequest
                                ) <?> ".requestAuthorizationForPurchases.maxOneTxnInserted"
                        }
                    }

                    // Check ignoring txns pending auth request

                    var stateCopy = inputState
                    stateCopy.subscription.transactionsPendingAuthRequest =
                        output.state.subscription.transactionsPendingAuthRequest

                    if output.state != inputState {
                        return (output.state ==== stateCopy) <?> ".requestAuthorizationForPurchases.stateEqual"
                    }

                case ._authorizationRequestResult(_, _):

                    if (output.state.subscription.transactionsPendingAuthRequest !=
                        inputState.subscription.transactionsPendingAuthRequest) {

                        // Check that max one txn was removed

                        let diff = inputState.subscription.transactionsPendingAuthRequest.subtracting(output.state.subscription.transactionsPendingAuthRequest)

                        if diff.count > 1 {
                            // Ensure diff is logged
                            return (
                                output.state.subscription.transactionsPendingAuthRequest ====
                                inputState.subscription.transactionsPendingAuthRequest
                                ) <?> "_authorizationRequestResult.maxOneTxnRemoved"
                        }
                    }

                    break
                }

                // Update current state
                inputState = output.state
            }

            return true
        }
    }

    // MARK: test helpers

    struct ReducerOutputs {
        let state: SubscriptionReducerState
        let actions: [[Signal<SubscriptionAuthStateAction,
                              SignalProducer<SubscriptionAuthStateAction,
                                             Never>.SignalError>
                      .Event]]
    }

    static func runReducer(effectsTimeout: TimeInterval,
                           state: SubscriptionReducerState,
                           action: SubscriptionAuthStateAction,
                           env: SubscriptionAuthStateReducerEnvironment) -> ReducerOutputs {

        let (nextState, effectsResults) =
            testReducer(state, action, env, subscriptionAuthStateReducer, effectsTimeout)

        return ReducerOutputs(state: nextState,
                              actions: effectsResults)
    }
}
