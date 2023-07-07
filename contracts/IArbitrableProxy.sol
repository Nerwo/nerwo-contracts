// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IArbitrator} from "@kleros/erc-792/contracts/IArbitrator.sol";

/**
 *  @title IArbitrableProxy
 *  A general purpose arbitrable contract. Supports non-binary rulings.
 */
interface IArbitrableProxy {
    function arbitrator() external view returns (IArbitrator arbitrator);

    function createDispute(
        bytes calldata _arbitratorExtraData,
        string calldata _metaevidenceURI,
        uint256 _numberOfRulingOptions
    ) external payable returns (uint256 disputeID);

    struct DisputeStruct {
        bytes arbitratorExtraData;
        bool isRuled;
        uint256 ruling;
        uint256 disputeIDOnArbitratorSide;
    }

    function externalIDtoLocalID(uint256 _externalID) external view returns (uint256 localID);

    function disputes(
        uint256 _localID
    ) external view returns (bytes memory extraData, bool isRuled, uint256 ruling, uint256 disputeIDOnArbitratorSide);

    function submitEvidence(uint256 _localDisputeID, string calldata _evidenceURI) external;
}
