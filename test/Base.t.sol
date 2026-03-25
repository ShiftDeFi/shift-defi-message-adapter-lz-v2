// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ShiftOApp} from "../contracts/ShiftOApp.sol";
import {MockMessageRouter} from "./mocks/MockMessageRouter.sol";

abstract contract Base is Test {
    ShiftOApp public l1Peer;
    ShiftOApp public l2Peer;

    uint256 public l1ForkId;
    uint256 public l2ForkId;

    struct Fork {
        string rpc;
        uint256 chainId;
        uint32 eid;
        address lzEndpoint;
        address sendLibrary;
        address receiveLibrary;
    }

    Fork l1Fork;
    Fork l2Fork;

    uint256 public baseL1SnapshotId;
    uint256 public baseL2SnapshotId;

    address SENDER = makeAddr("sender");
    address OWNER = makeAddr("owner");
    address REFUND = makeAddr("refund");

    MockMessageRouter l2MockMessageRouter;

    uint128 constant GAS_LIMIT = 100_000;
    uint256 constant NATIVE_FEE_BUFFER = 1e2;

    function _setUp(Fork memory _l1Fork, Fork memory _l2Fork) internal {
        l1Fork = _l1Fork;
        l2Fork = _l2Fork;
        l1ForkId = vm.createFork(l1Fork.rpc);
        l2ForkId = vm.createFork(l2Fork.rpc);

        vm.selectFork(l1ForkId);
        l1Peer = new ShiftOApp(l1Fork.lzEndpoint, OWNER, SENDER);
        vm.selectFork(l2ForkId);
        l2MockMessageRouter = new MockMessageRouter();
        l2Peer = new ShiftOApp(l2Fork.lzEndpoint, OWNER, address(l2MockMessageRouter));

        vm.selectFork(l1ForkId);
        vm.startPrank(OWNER);
        l1Peer.setEidAndChainId(l2Fork.eid, l2Fork.chainId);
        l1Peer.setPeer(l2Fork.eid, bytes32(uint256(uint160(address(l2Peer)))));
        l1Peer.setSendLibrary(l1Fork.sendLibrary, l2Fork.eid);
        l1Peer.setReceiveLibrary(l1Fork.receiveLibrary, l2Fork.eid);
        vm.stopPrank();
        vm.selectFork(l2ForkId);
        vm.startPrank(OWNER);
        l2Peer.setEidAndChainId(l1Fork.eid, l1Fork.chainId);
        l2Peer.setPeer(l1Fork.eid, bytes32(uint256(uint160(address(l1Peer)))));
        l2Peer.setSendLibrary(l2Fork.sendLibrary, l1Fork.eid);
        l2Peer.setReceiveLibrary(l2Fork.receiveLibrary, l1Fork.eid);
        vm.stopPrank();
    }
}
