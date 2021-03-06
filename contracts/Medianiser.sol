// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

contract Medianiser {
    uint256 value;
    constructor(bytes32 initValue) {
        value = uint256(initValue);
    }

    function peek() public view returns (bytes32 resp, bool valid) {
        return (bytes32(value), true);
    }

    function set(uint256 newValue) public returns (bool success) {
        value = newValue;
        return true;
    }
}
