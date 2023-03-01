// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// https://medium.com/coinmonks/how-to-create-an-uups-proxy-66eca257b2f9

abstract contract VersionAware {
    string public versionAwareContractName;

    function getContractNameWithVersion() external pure virtual returns (string memory);
}
