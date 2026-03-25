// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IShiftOApp
 * @notice Interface for Shift DeFi LayerZero OApp implementation
 * @dev Defines the interface for cross-chain messaging adapter using LayerZero protocol
 */
interface IShiftOApp {
    event EidAndChainIdSet(uint32 eid, uint256 chainId);
    event RouterSet(address oldRouter, address newRouter);

    error EIDCannotBeZero();
    error ChainIDCannotBeZero();
    error CrossChainConfigurationMissmatch(uint32 eid, uint256 chainId);
    error RouterAlreadySet(address oldRouter);
    error OnlyRouter(address sender);
    error RouterNotSet();
    error RefundAddressCannotBeZero();

    /**
     * @notice Sets the mapping between a chain ID and LayerZero endpoint ID
     * @dev Only callable by the owner. Establishes bidirectional mapping for chain identification
     * @param eid The LayerZero endpoint ID
     * @param chainId The standard chain ID
     * @custom:error EIDCannotBeZero Thrown when eid is zero
     * @custom:error ChainIDCannotBeZero Thrown when chainId is zero
     */
    function setEidAndChainId(uint32 eid, uint256 chainId) external;

    /**
     * @notice Updates the message router address
     * @dev Only callable by the owner. The router must be different from the current router
     * @param _router The new router address
     * @custom:error ZeroAddress Thrown when _router is the zero address
     * @custom:error RouterAlreadySet Thrown when _router is the same as the current router
     */
    function setRouter(address _router) external;

    /**
     * @notice Updates the LayerZero send library for a given endpoint id
     * @dev Only callable by the owner. Forwards the configuration to the LayerZero endpoint
     * @param sendLibrary The address of the new send library
     * @param eid The LayerZero endpoint id to configure
     */
    function setSendLibrary(address sendLibrary, uint32 eid) external;

    /**
     * @notice Updates the LayerZero receive library for a given endpoint id
     * @dev Only callable by the owner. Forwards the configuration to the LayerZero endpoint
     * @param receiveLibrary The address of the new receive library
     * @param eid The LayerZero endpoint id to configure
     */
    function setReceiveLibrary(address receiveLibrary, uint32 eid) external;

    /**
     * @notice Estimates the fee required to send a message to a destination chain
     * @dev Queries LayerZero to get the messaging fee for the specified destination and message
     * @param chainTo The destination chain ID
     * @param gasLimit The gas limit for message execution on the destination chain
     * @param rawMessage The raw message bytes to be sent
     * @return The estimated fee amount
     */
    function estimateFee(uint256 chainTo, uint128 gasLimit, bytes memory rawMessage) external view returns (uint256);

    /**
     * @notice Encodes fee parameters into a bytes array
     * @dev Utility function to pack native fee and gas limit into a single bytes parameter
     * @param refundAddress The address that should receive any fee refund
     * @param nativeFee The native token fee amount
     * @param gasLimit The gas limit for message execution on the destination chain
     * @return Encoded bytes containing the three parameters
     */
    function encodeParams(address refundAddress, uint256 nativeFee, uint128 gasLimit) external pure returns (bytes memory);

    /**
     * @notice Decodes fee parameters from a bytes array
     * @dev Utility function to unpack native fee and gas limit from encoded bytes
     * @param params The encoded bytes containing nativeFee and gasLimit
     * @return refundAddress The decoded refund address
     * @return nativeFee The decoded native token fee amount
     * @return gasLimit The decoded gas limit for message execution
     */
    function decodeParams(bytes memory params) external pure returns (address, uint256, uint128);
}
