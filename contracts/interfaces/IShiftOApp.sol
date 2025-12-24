// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface IShiftOApp {
    event EidAndChainIdSet(uint32 eid, uint256 chainId);
    event RouterSet(address oldRouter, address newRouter);

    error EIDNotFound(uint256 chainId);
    error EIDCannotBeZero();
    error ChainIDCannotBeZero();
    error RouterAlreadySet(address oldRouter);
    error OnlyRouter(address sender);
    error RouterNotSet();

    function setEidAndChainId(uint32 eid, uint256 chainId) external;
    function setRouter(address _router) external;
    function estimateFee(uint256 chainTo, uint128 gasLimit, bytes memory rawMessage, bool payInLz) external view returns (uint256);
}
