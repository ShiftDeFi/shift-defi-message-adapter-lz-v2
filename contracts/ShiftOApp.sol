// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {OApp, Origin, MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IMessageAdapter} from "@shift-defi/core/contracts/interfaces/IMessageAdapter.sol";
import {IMessageRouter} from "@shift-defi/core/contracts/interfaces/IMessageRouter.sol";
import {Errors} from "@shift-defi/core/contracts/libraries/helpers/Errors.sol";

import {IShiftOApp} from "./interfaces/IShiftOApp.sol";

contract ShiftOApp is OApp, IMessageAdapter, IShiftOApp {
    using OptionsBuilder for bytes;

    address public router;

    mapping(uint256 chainId => uint32 eid) public chainIdToEid;
    mapping(uint32 eid => uint256 chainId) public eidToChainId;


    constructor(address _endpoint, address _owner, address _router) OApp(_endpoint, _owner) Ownable(_owner) {
        require(_router != address(0), Errors.ZeroAddress());
        router = _router;
    }

    function encodeParams(uint256 nativeFee, uint256 zroFee, uint128 gasLimit) public pure returns (bytes memory) {
        return abi.encode(nativeFee, zroFee, gasLimit);
    }

    function decodeParams(bytes memory params) public pure returns (uint256, uint256, uint128) {
        return abi.decode(params, (uint256, uint256, uint128));
    }

    function setEidAndChainId(uint32 eid, uint256 chainId) external onlyOwner {
        require(eid != 0, EIDCannotBeZero());
        require(chainId != 0, ChainIDCannotBeZero());
        chainIdToEid[chainId] = eid;
        eidToChainId[eid] = chainId;
        emit EidAndChainIdSet(eid, chainId);
    }

    function setRouter(address _router) external onlyOwner {
        require(_router != address(0), Errors.ZeroAddress());
        address oldRouter = router;
        require(oldRouter != _router, RouterAlreadySet(oldRouter));
        router = _router;
        emit RouterSet(oldRouter, router);
    }

    function estimateFee(
        uint256 chainTo,
        uint128 gasLimit,
        bytes memory rawMessage,
        bool payInLz
    ) external view returns (uint256) {
        uint32 eid = chainIdToEid[chainTo];
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(gasLimit, 0);
        MessagingFee memory messagingFee = _quote(eid, rawMessage, options, payInLz);
        if (payInLz) return messagingFee.lzTokenFee;
        return messagingFee.nativeFee;
    }

    function send(uint256 chainTo, bytes memory params, bytes memory rawMessage) external payable {
        require(msg.sender == router, OnlyRouter(msg.sender));
        require(chainIdToEid[chainTo] != 0, EIDNotFound(chainTo));
        (uint256 nativeFee, uint256 zroFee, uint128 gasLimit) = decodeParams(params);
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(gasLimit, 0);
        _lzSend(
            chainIdToEid[chainTo],
            rawMessage,
            options,
            // Fee in native gas and ZRO token.
            MessagingFee({nativeFee: nativeFee, lzTokenFee: zroFee}),
            // Refund address in case of failed source message.
            payable(tx.origin)
        );
    }

    function _lzReceive(
        Origin calldata,
        bytes32,
        bytes calldata payload,
        address, // Executor address as specified by the OApp.
        bytes calldata // Any extra data or options to trigger on receipt.
    ) internal override {
        require(router != address(0), RouterNotSet());
        IMessageRouter(router).receiveMessage(payload);
    }
}
