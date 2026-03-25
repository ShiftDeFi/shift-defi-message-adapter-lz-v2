// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IMessageRouter} from "@shift-defi/core/contracts/interfaces/IMessageRouter.sol";

contract MockMessageRouter is IMessageRouter {
    function calculatePath(address sender, address receiver, uint256 chainId) external pure returns (bytes32) {
        return keccak256(abi.encode(sender, receiver, chainId));
    }

    function encodeMessage(uint256 nonce, bytes32 path, bytes memory message) external pure returns (bytes memory) {
        return abi.encode(nonce, path, message);
    }

    function calculateCacheKey(
        uint256 chainTo,
        bytes memory rawMessageWithPathAndNonce
    ) external pure returns (bytes32) {
        return keccak256(abi.encode(chainTo, rawMessageWithPathAndNonce));
    }

    function decodeMessage(bytes memory message) external pure returns (uint256, bytes32, bytes memory) {
        return abi.decode(message, (uint256, bytes32, bytes));
    }

    function whitelistPath(address sender, address receiver, uint256 chainId) external {

    }

    function blacklistPath(address sender, address receiver, uint256 chainId) external {
    }

    function whitelistMessageAdapter(address adapter) external {
    }

    function blacklistMessageAdapter(address adapter) external {
    }

    function send(address receiver, SendParams calldata sendParams) external payable {
        emit MessageSent(
            0,
            sendParams.chainTo,
            msg.sender,
            receiver,
            sendParams.adapter,
            bytes32(0),
            bytes32(0)
        );
    }

    function receiveMessage(bytes memory) external {
        emit MessageReceived(0, 0, address(0), address(0), msg.sender, bytes32(0));
    }

    function retryCachedMessage(uint256, bytes32, SendParams calldata) external payable {
    }

    function removeMessageFromCache(uint256, uint256, bytes32, bytes memory) external {
    }

    function isMessageCached(
        uint256,
        uint256,
        bytes32,
        bytes memory
    ) external pure returns (bool) {
        return false;
    }
}
