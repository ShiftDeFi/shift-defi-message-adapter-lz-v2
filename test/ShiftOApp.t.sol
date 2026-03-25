// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Errors} from "@shift-defi/core/contracts/libraries/Errors.sol";

import {Base} from "./Base.t.sol";
import {IShiftOApp} from "../contracts/interfaces/IShiftOApp.sol";

interface ILayerZeroEndpointV2Extended is ILayerZeroEndpointV2 {
    function delegates(address account) external view returns (address);
}

contract ShiftOAppTest is Base {
    string ETHEREUM_RPC = vm.envString("ETH_RPC_URL");
    string ARBITRUM_RPC = vm.envString("ARB_RPC_URL");
    uint256 ETHEREUM_CHAIN_ID = 1;
    uint256 ARBITRUM_CHAIN_ID = 42161;
    uint32 ETHEREUM_EID = 30101;
    uint32 ARBITRUM_EID = 30110;

    address LZ_ENDPOINT_ETHEREUM = 0x1a44076050125825900e736c501f859c50fE728c;
    address LZ_ENDPOINT_ARBITRUM = 0x1a44076050125825900e736c501f859c50fE728c;

    address ETHEREUM_SEND_LIBRARY_ADDRESS = 0xbB2Ea70C9E858123480642Cf96acbcCE1372dCe1;
    address ETHEREUM_RECEIVE_LIBRARY_ADDRESS = 0xc02Ab410f0734EFa3F14628780e6e695156024C2;

    address ARBITRUM_SEND_LIBRARY_ADDRESS = 0x975bcD720be66659e3EB3C0e4F1866a3020E493A;
    address ARBITRUM_RECEIVE_LIBRARY_ADDRESS = 0x7B9E184e07a6EE1aC23eAe0fe8D6Be2f663f05e6;

    function setUp() public {
        l1Fork = Fork({
            rpc: ETHEREUM_RPC,
            chainId: ETHEREUM_CHAIN_ID,
            eid: ETHEREUM_EID,
            lzEndpoint: LZ_ENDPOINT_ETHEREUM,
            sendLibrary: ETHEREUM_SEND_LIBRARY_ADDRESS,
            receiveLibrary: ETHEREUM_RECEIVE_LIBRARY_ADDRESS
        });

        l2Fork = Fork({
            rpc: ARBITRUM_RPC,
            chainId: ARBITRUM_CHAIN_ID,
            eid: ARBITRUM_EID,
            lzEndpoint: LZ_ENDPOINT_ARBITRUM,
            sendLibrary: ARBITRUM_SEND_LIBRARY_ADDRESS,
            receiveLibrary: ARBITRUM_RECEIVE_LIBRARY_ADDRESS
        });

        _setUp(l1Fork, l2Fork);
    }

    function test_Configuration_Success() public {
        vm.selectFork(l1ForkId);
        address l1Endpoint = address(l1Peer.endpoint());
        address l1Delegate = ILayerZeroEndpointV2Extended(l1Endpoint).delegates(address(l1Peer));
        assertEq(l1Delegate, address(l1Peer), "test_Configuration_Success: l1 delegate should be set to l1Peer");
        assertEq(l1Peer.router(), SENDER, "test_Configuration_Success: l1 router should be set to SENDER");
        assertEq(
            l1Peer.chainIdToEid(l2Fork.chainId),
            l2Fork.eid,
            "test_Configuration_Success: l1 chainIdToEid for l2 should be set"
        );
        assertEq(
            l1Peer.eidToChainId(l2Fork.eid),
            l2Fork.chainId,
            "test_Configuration_Success: l1 eidToChainId for l2 should be set"
        );
        assertEq(l1Peer.owner(), OWNER, "test_Configuration_Success: owner set incorrect");

        vm.selectFork(l2ForkId);
        address l2Endpoint = address(l2Peer.endpoint());
        address l2Delegate = ILayerZeroEndpointV2Extended(l2Endpoint).delegates(address(l2Peer));
        assertEq(l2Delegate, address(l2Peer), "test_Configuration_Success: l2 delegate should be set to l2Peer");
        assertEq(
            l2Peer.router(),
            address(l2MockMessageRouter),
            "test_Configuration_Success: l2 router should be set to MockMessageRouter"
        );
        assertEq(
            l2Peer.chainIdToEid(l1Fork.chainId),
            l1Fork.eid,
            "test_Configuration_Success: l2 chainIdToEid for l1 should be set"
        );
        assertEq(
            l2Peer.eidToChainId(l1Fork.eid),
            l1Fork.chainId,
            "test_Configuration_Success: l2 eidToChainId for l1 should be set"
        );
        assertEq(l2Peer.owner(), OWNER, "test_Configuration_Success: owner set incorrect");
    }

    function test_Send_Success() public {
        bytes memory message = abi.encode("Hello, world");
        _sendMessage(message);
        assertEq(
            address(REFUND).balance,
            NATIVE_FEE_BUFFER,
            "test_Send_Success: refund should receive native fee buffer"
        );
    }

    function test_lzReceive_Success() public {
        bytes memory message = abi.encode("Hello, world");
        _sendMessage(message);

        Origin memory origin = Origin({
            srcEid: l1Fork.eid,
            sender: bytes32(uint256(uint160(address(l1Peer)))),
            nonce: uint64(vm.randomUint(0, type(uint64).max))
        });

        vm.selectFork(l2ForkId);
        vm.recordLogs();
        vm.prank(l2Fork.lzEndpoint);
        l2Peer.lzReceive(origin, bytes32("guid"), message, vm.randomAddress(), bytes(""));

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundMessageReceived;
        bytes32 expectedTopic = keccak256("MessageReceived(uint256,uint256,address,address,address,bytes32)");
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics.length > 0 && entries[i].topics[0] == expectedTopic) {
                foundMessageReceived = true;
                break;
            }
        }

        assertTrue(foundMessageReceived, "test_lzReceive_Success: MessageReceived event should be emitted by router");
    }

    function _sendMessage(bytes memory message) internal returns (uint256) {
        vm.selectFork(l1ForkId);
        uint256 nativeFee = l1Peer.estimateFee(l2Fork.chainId, GAS_LIMIT, message);
        uint256 nativeFeeWithBuffer = nativeFee + NATIVE_FEE_BUFFER;

        deal(SENDER, nativeFeeWithBuffer);
        bytes memory params = l1Peer.encodeParams(REFUND, nativeFeeWithBuffer, GAS_LIMIT);
        vm.prank(SENDER);
        l1Peer.send{value: nativeFeeWithBuffer}(l2Fork.chainId, params, message);
        return nativeFee;
    }

    function test_EncodeParams_RoundTripDecode() public {
        vm.selectFork(l1ForkId);
        address refund = REFUND;
        uint256 nativeFee = 1e18;
        uint128 gasLimit = GAS_LIMIT;
        bytes memory params = l1Peer.encodeParams(refund, nativeFee, gasLimit);
        (address decodedRefund, uint256 decodedFee, uint128 decodedGas) = l1Peer.decodeParams(params);
        assertEq(decodedRefund, refund, "test_EncodeParams_RoundTripDecode: refund address mismatch");
        assertEq(decodedFee, nativeFee, "test_EncodeParams_RoundTripDecode: native fee mismatch");
        assertEq(decodedGas, gasLimit, "test_EncodeParams_RoundTripDecode: gas limit mismatch");
    }

    function test_SetEidAndChainId_RevertIf_CallerIsNotOwner() public {
        vm.selectFork(l1ForkId);
        address notOwner = makeAddr("notOwner");
        vm.prank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        l1Peer.setEidAndChainId(999, 999);
    }

    function test_SetEidAndChainId_RevertIf_EidIsZero() public {
        vm.selectFork(l1ForkId);
        vm.prank(OWNER);
        vm.expectRevert(IShiftOApp.EIDCannotBeZero.selector);
        l1Peer.setEidAndChainId(0, l2Fork.chainId);
    }

    function test_SetEidAndChainId_RevertIf_ChainIdIsZero() public {
        vm.selectFork(l1ForkId);
        vm.prank(OWNER);
        vm.expectRevert(IShiftOApp.ChainIDCannotBeZero.selector);
        l1Peer.setEidAndChainId(l2Fork.eid, 0);
    }

    function test_SetEidAndChainId_UpdatesMappingsAndEmitsEvent() public {
        vm.selectFork(l1ForkId);
        uint32 eid = 30199;
        uint256 chainId = 99999;

        vm.expectEmit();
        emit IShiftOApp.EidAndChainIdSet(eid, chainId);

        vm.prank(OWNER);
        l1Peer.setEidAndChainId(eid, chainId);
        assertEq(
            l1Peer.chainIdToEid(chainId),
            eid,
            "test_SetEidAndChainId_UpdatesMappingsAndEmitsEvent: chainIdToEid mapping incorrect"
        );
        assertEq(
            l1Peer.eidToChainId(eid),
            chainId,
            "test_SetEidAndChainId_UpdatesMappingsAndEmitsEvent: eidToChainId mapping incorrect"
        );
    }

    function test_SetRouter_RevertIf_CallerIsNotOwner() public {
        vm.selectFork(l1ForkId);
        address newRouter = makeAddr("newRouter");
        vm.prank(newRouter);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, newRouter));
        l1Peer.setRouter(newRouter);
    }

    function test_SetRouter_RevertIf_RouterIsZeroAddress() public {
        vm.selectFork(l1ForkId);
        vm.prank(OWNER);
        vm.expectRevert(Errors.ZeroAddress.selector);
        l1Peer.setRouter(address(0));
    }

    function test_SetRouter_RevertIf_RouterAlreadySet() public {
        vm.selectFork(l1ForkId);
        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(IShiftOApp.RouterAlreadySet.selector, SENDER));
        l1Peer.setRouter(SENDER);
    }

    function test_SetRouter_UpdatesRouterAndEmitsEvent() public {
        vm.selectFork(l1ForkId);
        address oldRouter = l1Peer.router();
        address newRouter = makeAddr("newRouter");
        vm.expectEmit();
        emit IShiftOApp.RouterSet(oldRouter, newRouter);

        vm.prank(OWNER);
        l1Peer.setRouter(newRouter);
        assertEq(l1Peer.router(), newRouter, "test_SetRouter_UpdatesRouterAndEmitsEvent: router should be updated");
    }

    function test_SetSendLibrary_RevertIf_CallerIsNotOwner() public {
        vm.selectFork(l1ForkId);
        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        l1Peer.setSendLibrary(l1Fork.sendLibrary, l2Fork.eid);
    }

    function test_SetReceiveLibrary_RevertIf_CallerIsNotOwner() public {
        vm.selectFork(l1ForkId);
        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        l1Peer.setReceiveLibrary(l1Fork.receiveLibrary, l2Fork.eid);
    }

    function test_EstimateFee_ReturnsNonZeroWhenChainConfigured() public {
        vm.selectFork(l1ForkId);
        bytes memory message = abi.encode("test");
        uint256 fee = l1Peer.estimateFee(l2Fork.chainId, GAS_LIMIT, message);
        assertGt(fee, 0, "test_EstimateFee_ReturnsNonZeroWhenChainConfigured: fee should be > 0");
    }

    function test_EstimateFee_RevertIf_ChainNotConfigured() public {
        vm.selectFork(l1ForkId);
        uint256 unknownChainId = 999999;
        bytes memory message = abi.encode("test");
        vm.expectRevert(abi.encodeWithSelector(IShiftOApp.EIDCannotBeZero.selector));
        l1Peer.estimateFee(unknownChainId, GAS_LIMIT, message);
    }

    function test_Send_RevertIf_CallerIsNotRouter() public {
        vm.selectFork(l1ForkId);
        bytes memory message = abi.encode("test");
        uint256 nativeFee = l1Peer.estimateFee(l2Fork.chainId, GAS_LIMIT, message);
        bytes memory params = l1Peer.encodeParams(REFUND, nativeFee, GAS_LIMIT);
        address notRouter = makeAddr("notRouter");
        deal(notRouter, nativeFee);
        vm.prank(notRouter);
        vm.expectRevert(abi.encodeWithSelector(IShiftOApp.OnlyRouter.selector, notRouter));
        l1Peer.send{value: nativeFee}(l2Fork.chainId, params, message);
    }

    function test_Send_RevertIf_ChainNotConfigured() public {
        vm.selectFork(l1ForkId);
        uint256 unknownChainId = 999999;
        bytes memory message = abi.encode("test");
        bytes memory params = l1Peer.encodeParams(REFUND, 1e18, GAS_LIMIT);
        deal(SENDER, 1e18);
        vm.prank(SENDER);
        vm.expectRevert(abi.encodeWithSelector(IShiftOApp.EIDCannotBeZero.selector));
        l1Peer.send{value: 1e18}(unknownChainId, params, message);
    }

    function test_SetSendLibrary_RevertIf_SendLibraryIsZeroAddress() public {
        vm.selectFork(l1ForkId);
        vm.prank(OWNER);
        vm.expectRevert(Errors.ZeroAddress.selector);
        l1Peer.setSendLibrary(address(0), l2Fork.eid);
    }

    function test_SetSendLibrary_RevertIf_EidNotConfigured() public {
        vm.selectFork(l1ForkId);
        vm.prank(OWNER);
        vm.expectRevert(IShiftOApp.ChainIDCannotBeZero.selector);
        l1Peer.setSendLibrary(l1Fork.sendLibrary, 999999);
    }

    function test_SetReceiveLibrary_RevertIf_ReceiveLibraryIsZeroAddress() public {
        vm.selectFork(l1ForkId);
        vm.prank(OWNER);
        vm.expectRevert(Errors.ZeroAddress.selector);
        l1Peer.setReceiveLibrary(address(0), l2Fork.eid);
    }

    function test_SetReceiveLibrary_RevertIf_EidNotConfigured() public {
        vm.selectFork(l1ForkId);
        vm.prank(OWNER);
        vm.expectRevert(IShiftOApp.ChainIDCannotBeZero.selector);
        l1Peer.setReceiveLibrary(l1Fork.receiveLibrary, 999999);
    }

    function test_lzReceive_RevertIf_RouterNotSet() public {
        vm.selectFork(l2ForkId);
        vm.store(address(l2Peer), bytes32(uint256(3)), bytes32(uint256(0)));
        bytes memory message = abi.encode("test");
        Origin memory origin = Origin({
            srcEid: l1Fork.eid,
            sender: bytes32(uint256(uint160(address(l1Peer)))),
            nonce: 0
        });
        vm.prank(l2Fork.lzEndpoint);
        vm.expectRevert(IShiftOApp.RouterNotSet.selector);
        l2Peer.lzReceive(origin, bytes32("guid"), message, vm.addr(1), "");
    }
}
