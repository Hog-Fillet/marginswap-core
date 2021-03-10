// SPDX-License-Identifier: GPL-2.0-only
pragma solidity ^0.8.0;

import "./IncentiveDistribution.sol";
import "./RoleAware.sol";

abstract contract IncentivizedHolder is RoleAware {
    // here we cache incentive tranches to save on a bit of gas
    mapping(address => uint8) public incentiveTranches;
    // claimant => token => claimId
    mapping(address => mapping(address => uint256)) public claimIds;

    function setIncentiveTranche(address token, uint8 tranche) external {
        require(
            isTokenActivator(msg.sender),
            "Caller not authorized to set incentive tranche"
        );
        incentiveTranches[token] = tranche;
    }

    function stakeClaim(
        address claimant,
        address token,
        uint256 amount
    ) internal {
        IncentiveDistribution iD =
            IncentiveDistribution(incentiveDistributor());
        uint256 claimId = claimIds[claimant][token];
        uint8 tranche = incentiveTranches[token];
        if (claimId > 0) {
            iD.addToClaimAmount(tranche, claimId, amount);
        } else {
            claimId = iD.startClaim(tranche, claimant, amount);
            claimIds[claimant][token] = claimId;
        }
    }

    function withdrawClaim(
        address claimant,
        address token,
        uint256 amount
    ) internal {
        uint256 claimId = claimIds[claimant][token];
        uint8 tranche = incentiveTranches[token];
        IncentiveDistribution(incentiveDistributor()).subtractFromClaimAmount(
            tranche,
            claimId,
            amount
        );
    }
}
