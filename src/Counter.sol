// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/// @title Counter
/// @notice Minimal stateful contract used for Foundry examples and smoke tests.
contract Counter {
    /// @notice Current counter value.
    uint256 public number;

    /// @notice Sets the counter to an arbitrary value.
    /// @param newNumber New value to store.
    function setNumber(uint256 newNumber) public {
        number = newNumber;
    }

    /// @notice Increments the counter by exactly one.
    function increment() public {
        number++;
    }
}
