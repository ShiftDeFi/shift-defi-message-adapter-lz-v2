// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

contract GetPeerAddress is Script {
    address constant PEER_ADDRESS = 0x808F3DCFA853c28d5ac27a2BC6C8796cA15D2B13;

    function run() public {
        console.logBytes32(bytes32(uint256(uint160(PEER_ADDRESS))));
    }
}
