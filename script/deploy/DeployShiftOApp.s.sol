// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ShiftOApp} from "contracts/ShiftOApp.sol";

import {Script} from "forge-std/Script.sol";

contract DeployShiftOApp is Script {
    address public endpoint;
    address public router;
    address public nonceManager;

    address public sendLibrary;
    address public receiveLibrary;
    uint32 public remoteEid;
    uint256 public remoteChainId;

    /**
     * @dev Ownership stays with the deployer after this script runs. The remote adapter's
     *      address is not known yet (it may not be deployed yet), so setPeer and the
     *      ownership transfer happen later in ConfigurePeer.s.sol, once both sides are deployed.
     *
     *      IMPORTANT: when signing with a keystore, `--account` alone does NOT make
     *      `msg.sender` resolve to the keystore's address during simulation - it stays
     *      forge-std's DEFAULT_SENDER unless `--sender <address>` is also passed. Passing
     *      the wrong or no `--sender` does not revert; it silently deploys with the wrong
     *      owner. Always run with:
     *        --account <name> --sender $(cast wallet address --account <name>)
     */
    function run() public {
        address deployer = msg.sender;
        require(deployer != DEFAULT_SENDER, "pass --sender matching --account's address");

        endpoint = vm.envAddress("ENDPOINT");
        router = vm.envAddress("MESSAGE_ROUTER");
        nonceManager = vm.envAddress("NONCE_MANAGER_ROLE");

        sendLibrary = vm.envAddress("SEND_LIBRARY");
        receiveLibrary = vm.envAddress("RECEIVE_LIBRARY");
        remoteEid = uint32(vm.envUint("REMOTE_EID"));
        remoteChainId = vm.envUint("REMOTE_CHAIN_ID");

        vm.startBroadcast();

        // Deployer is the initial owner so the adapter can be configured within this broadcast.
        ShiftOApp oapp = new ShiftOApp(endpoint, deployer, router, nonceManager);

        oapp.setEidAndChainId(remoteEid, remoteChainId);
        oapp.setSendLibrary(sendLibrary, remoteEid);
        oapp.setReceiveLibrary(receiveLibrary, remoteEid);

        vm.stopBroadcast();
    }
}
