// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ShiftOApp} from "contracts/ShiftOApp.sol";

import {Script} from "forge-std/Script.sol";

/**
 * @dev Run once per chain after ShiftOApp has been deployed on both sides of the route
 *      (see DeployShiftOApp.s.sol). Links the two adapters via setPeer and hands ownership
 *      over to OWNER.
 *
 *      Must be signed by the same account that received ownership from DeployShiftOApp.s.sol.
 *      If signing with a keystore, pass `--sender` alongside `--account` (see
 *      DeployShiftOApp.s.sol for why this matters) - otherwise the onlyOwner calls below
 *      simply revert during simulation.
 */
contract ConfigurePeer is Script {
    address public oapp;
    address public owner;
    uint32 public remoteEid;
    address public remotePeer;

    function run() public {
        require(msg.sender != DEFAULT_SENDER, "pass --sender matching --account's address");

        oapp = vm.envAddress("SHIFT_OAPP");
        owner = vm.envAddress("OWNER");
        remoteEid = uint32(vm.envUint("REMOTE_EID"));
        remotePeer = vm.envAddress("REMOTE_PEER");

        vm.startBroadcast();

        ShiftOApp(oapp).setPeer(remoteEid, bytes32(uint256(uint160(remotePeer))));
        ShiftOApp(oapp).transferOwnership(owner);

        vm.stopBroadcast();
    }
}
