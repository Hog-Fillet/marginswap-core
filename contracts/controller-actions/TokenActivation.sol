// SPDX-License-Identifier: GPL-2.0-only
pragma solidity ^0.8.0;

import "./SelfDestructReturningExec.sol";
import "../TokenAdmin.sol";

contract TokenActivation is SelfDestructReturningExec {
    uint16 public constant TOKEN_ADMIN = 109;
    address[] public tokens;
    uint256[] public exposureCaps;
    uint256[] public lendingBuffers;
    uint256[] public incentiveWeights;
    address[][] public liquidationPaths;

    constructor(address controller,
                address[] memory tokens2activate,
                uint256[] memory _exposureCaps,
                uint256[] memory _lendingBuffers,
                uint256[] memory _incentiveWeights,
                address[][] memory _liquidationPaths
                )
        SelfDestructReturningExec(controller)
    {
        tokens = tokens2activate;
        exposureCaps = _exposureCaps;
        lendingBuffers = _lendingBuffers;
        incentiveWeights = _incentiveWeights;
        liquidationPaths = _liquidationPaths;
        
        propertyCharacters.push(TOKEN_ADMIN);
        
    }

    function _execute() internal override {
        for (uint24 i = 0; tokens.length > i; i++) {
            address token = tokens[i];
            uint256 exposureCap = exposureCaps[i];
            uint256 lendingBuffer = lendingBuffers[i];
            uint256 incentiveWeight = incentiveWeights[i];
            address[] memory liquidationPath = liquidationPaths[i];

            TokenAdmin(roles().mainCharacters(TOKEN_ADMIN))
                .activateToken(token,
                               exposureCap,
                               lendingBuffer,
                               incentiveWeight,
                               liquidationPath);
        }
    }
}
