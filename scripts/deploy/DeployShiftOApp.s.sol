// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ShiftOApp} from "../../contracts/ShiftOApp.sol";

import {Script} from "forge-std/Script.sol";

contract DeployShiftOApp is Script {
    address public endpoint;
    address public owner;
    address public router;

    function run() public {
        owner = vm.envAddress("OWNER");
        endpoint = vm.envAddress("ENDPOINT");
        router = vm.envAddress("MESSAGE_ROUTER");

        vm.startBroadcast();
        new ShiftOApp(endpoint, owner, router);
        vm.stopBroadcast();
    }
}
