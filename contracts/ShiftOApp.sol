// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {OApp, Origin, MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {IMessagingChannel} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessagingChannel.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IMessageAdapter} from "@shift-defi/core/contracts/interfaces/IMessageAdapter.sol";
import {IMessageRouter} from "@shift-defi/core/contracts/interfaces/IMessageRouter.sol";
import {Errors} from "@shift-defi/core/contracts/libraries/Errors.sol";

import {IShiftOApp, SetConfigParam} from "./interfaces/IShiftOApp.sol";

contract ShiftOApp is OApp, ReentrancyGuard, IMessageAdapter, IShiftOApp {
    using OptionsBuilder for bytes;

    address public router;

    mapping(uint256 chainId => uint32 eid) public chainIdToEid;
    mapping(uint32 eid => uint256 chainId) public eidToChainId;
    mapping(uint32 srcEid => mapping(bytes32 sender => uint64 nonce)) public receivedNonce;

    address public nonceManager;

    modifier onlyNonceManager() {
        require(msg.sender == nonceManager, OnlyNonceManager(msg.sender));
        _;
    }

    /**
     * @notice Constructs the ShiftOApp contract
     * @dev Initializes the OApp with LayerZero endpoint, sets the owner, configures the router,
     *      and sets the endpoint delegate to this contract.
     * @param _endpoint The LayerZero endpoint address for cross-chain messaging
     * @param _owner The owner address who can configure the contract
     * @param _router The Shift DeFi message router address
     * @param _nonceManager The nonce manager address who can skip inbound messages
     */
    constructor(
        address _endpoint,
        address _owner,
        address _router,
        address _nonceManager
    ) OApp(_endpoint, _owner) Ownable(_owner) {
        _setRouter(_router);
        _setNonceManager(_nonceManager);
        ILayerZeroEndpointV2(endpoint).setDelegate(address(this));
    }

    /**
     * @inheritdoc IShiftOApp
     */
    function setNonceManager(address _nonceManager) external onlyOwner {
        _setNonceManager(_nonceManager);
    }

    function _setNonceManager(address _nonceManager) internal {
        require(_nonceManager != address(0), Errors.ZeroAddress());
        address previousNonceManager = nonceManager;
        require(previousNonceManager != _nonceManager, NonceManagerAlreadySet(previousNonceManager));
        nonceManager = _nonceManager;
        emit NonceManagerUpdated(previousNonceManager, nonceManager);
    }

    /**
     * @inheritdoc IShiftOApp
     */
    function encodeParams(
        address refundAddress,
        uint256 nativeFee,
        uint128 gasLimit
    ) public pure returns (bytes memory) {
        return abi.encode(refundAddress, nativeFee, gasLimit);
    }

    /**
     * @inheritdoc IShiftOApp
     */
    function decodeParams(bytes memory params) public pure returns (address, uint256, uint128) {
        return abi.decode(params, (address, uint256, uint128));
    }

    /// @inheritdoc IShiftOApp
    function setConfig(address _lib, SetConfigParam[] calldata _params) external onlyOwner {
        ILayerZeroEndpointV2(endpoint).setConfig(address(this), _lib, _params);
        emit LibraryConfigUpdated(_lib);
    }

    /**
     * @inheritdoc IShiftOApp
     */
    function skipInboundMessage(uint32 srcEid, bytes32 sender, uint64 nonce) external onlyNonceManager {
        uint64 expected = nextNonce(srcEid, sender);
        require(nonce == expected, InvalidSkipNonce(srcEid, sender, nonce));

        IMessagingChannel(address(endpoint)).skip(address(this), srcEid, sender, nonce);

        receivedNonce[srcEid][sender] = nonce;
    }

    /**
     * @inheritdoc IShiftOApp
     */
    function setEidAndChainId(uint32 eid, uint256 chainId) external onlyOwner {
        _setEidAndChainId(eid, chainId);
    }

    /**
     * @inheritdoc IShiftOApp
     */
    function setSendLibrary(address sendLibrary, uint32 eid) external onlyOwner {
        _setSendLibrary(sendLibrary, eid);
    }

    /**
     * @inheritdoc IShiftOApp
     */
    function setReceiveLibrary(address receiveLibrary, uint32 eid) external onlyOwner {
        _setReceiveLibrary(receiveLibrary, eid);
    }

    /**
     * @inheritdoc IShiftOApp
     */
    function setRouter(address _router) external onlyOwner {
        _setRouter(_router);
    }

    /**
     * @dev Public function to get the next expected nonce for a given source endpoint and sender.
     * @param _srcEid Source endpoint ID.
     * @param _sender Sender's address in bytes32 format.
     * @return uint64 Next expected nonce.
     */
    function nextNonce(uint32 _srcEid, bytes32 _sender) public view virtual override returns (uint64) {
        return receivedNonce[_srcEid][_sender] + 1;
    }

    /**
     * @inheritdoc IShiftOApp
     */
    function estimateFee(uint256 chainTo, uint128 gasLimit, bytes memory rawMessage) external view returns (uint256) {
        uint32 eid = chainIdToEid[chainTo];
        _validateEid(eid);
        bytes memory options = OptionsBuilder
            .newOptions()
            .addExecutorLzReceiveOption(gasLimit, 0)
            .addExecutorOrderedExecutionOption();
        MessagingFee memory messagingFee = _quote(eid, rawMessage, options, false);
        return messagingFee.nativeFee;
    }

    /**
     * @notice Sends a cross-chain message via LayerZero
     * @dev Only callable by the configured router. Sends the message to the destination chain
     *      using LayerZero's messaging protocol. Fees are paid from the contract's balance.
     *      Implements IMessageAdapter.send
     * @param chainTo The destination chain ID
     * @param params Encoded parameters containing nativeFee and gasLimit
     * @param rawMessage The raw message bytes to be sent
     */
    function send(uint256 chainTo, bytes memory params, bytes memory rawMessage) external payable nonReentrant {
        require(msg.sender == router, OnlyRouter(msg.sender));
        _validateEid(chainIdToEid[chainTo]);
        (address refundAddress, uint256 nativeFee, uint128 gasLimit) = decodeParams(params);
        require(refundAddress != address(0), RefundAddressCannotBeZero());
        bytes memory options = OptionsBuilder
            .newOptions()
            .addExecutorLzReceiveOption(gasLimit, 0)
            .addExecutorOrderedExecutionOption();
        _lzSend(
            chainIdToEid[chainTo],
            rawMessage,
            options,
            // Fee in native gas.
            MessagingFee({nativeFee: nativeFee, lzTokenFee: 0}),
            // Refund address in case of failed source message.
            payable(refundAddress)
        );
    }

    /**
     * @dev Internal function to accept nonce from the specified source endpoint and sender.
     * @param _srcEid Source endpoint ID.
     * @param _sender Sender's address in bytes32 format.
     * @param _nonce The nonce to be accepted.
     */
    function _acceptNonce(uint32 _srcEid, bytes32 _sender, uint64 _nonce) internal {
        uint64 newNonce = receivedNonce[_srcEid][_sender] + 1;
        require(newNonce == _nonce, InvalidNonce(_srcEid, _sender, _nonce));
        receivedNonce[_srcEid][_sender] = newNonce;
    }

    function _lzReceive(
        Origin calldata origin,
        bytes32,
        bytes calldata payload,
        address, // Executor address as specified by the OApp.
        bytes calldata // Any extra data or options to trigger on receipt.
    ) internal override {
        require(router != address(0), RouterNotSet());
        _validateEid(origin.srcEid);
        _acceptNonce(origin.srcEid, origin.sender, origin.nonce);
        IMessageRouter(router).receiveMessage(payload);
    }

    function _setRouter(address _router) internal {
        require(_router != address(0), Errors.ZeroAddress());
        address oldRouter = router;
        require(oldRouter != _router, RouterAlreadySet(oldRouter));
        router = _router;
        emit RouterSet(oldRouter, _router);
    }

    function _setEidAndChainId(uint32 eid, uint256 chainId) internal {
        require(eid != 0, EIDCannotBeZero());
        require(chainId != 0, ChainIDCannotBeZero());
        chainIdToEid[chainId] = eid;
        eidToChainId[eid] = chainId;
        emit EidAndChainIdSet(eid, chainId);
    }

    function _setSendLibrary(address sendLibrary, uint32 eid) internal {
        require(sendLibrary != address(0), Errors.ZeroAddress());
        _validateEid(eid);
        ILayerZeroEndpointV2(endpoint).setSendLibrary(address(this), eid, sendLibrary);
    }

    function _setReceiveLibrary(address receiveLibrary, uint32 eid) internal {
        require(receiveLibrary != address(0), Errors.ZeroAddress());
        _validateEid(eid);
        ILayerZeroEndpointV2(endpoint).setReceiveLibrary(address(this), eid, receiveLibrary, 0);
    }

    function _validateEid(uint32 eid) internal view {
        require(eid != 0, EIDCannotBeZero());
        uint256 chainId = eidToChainId[eid];
        require(chainId != 0, ChainIDCannotBeZero());
        require(chainIdToEid[chainId] == eid, CrossChainConfigurationMissmatch(eid, chainId));
    }
}
