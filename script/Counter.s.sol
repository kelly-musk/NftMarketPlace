// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {Counter} from "../src/Counter.sol";

/// @title Counter deployment script
/// @notice Demonstrates contract deployment using Foundry broadcast flow.
contract CounterScript is Script {
    /// @notice Reference to deployed Counter instance.
    Counter public counter;

    /// @dev Optional setup hook. Left empty for this simple script.
    function setUp() public {}

    /// @notice Broadcasts a transaction that deploys a new Counter contract.
    function run() public {
        // Start sending transactions with the configured deployer key.
        vm.startBroadcast();

        // Deploy contract and store address in state for easy access.
        counter = new Counter();

        // Stop broadcasting to avoid accidental extra transactions.
        vm.stopBroadcast();
    }
}
