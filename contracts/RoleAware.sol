import "./Roles.sol";

contract RoleAware {
    Roles public roles;

    constructor(address _roles) {
        roles = Roles(_roles);
    }

    modifier noIntermediary() {
        require(
            msg.sender == tx.origin,
            "Currently no intermediaries allowed for this function call"
        );
        _;
    }

    function fund() internal view returns (address) {
        return roles.mainCharacters(Characters.FUND);
    }

    function lending() internal view returns (address) {
        return roles.mainCharacters(Characters.LENDING);
    }

    function router() internal view returns (address) {
        return roles.mainCharacters(Characters.ROUTER);
    }

    function marginTrading() internal view returns (address) {
        return roles.mainCharacters(Characters.MARGIN_TRADING);
    }

    function feeController() internal view returns (address) {
        return roles.mainCharacters(Characters.FEE_CONTROLLER);
    }

    function price() internal view returns (address) {
        return roles.mainCharacters(Characters.PRICE_CONTROLLER);
    }

    function isBorrower(address contr) internal view returns (bool) {
        return roles.getRole(contr, ContractRoles.BORROWER);
    }

    function isWithdrawer(address contr) internal view returns (bool) {
        return roles.getRole(contr, ContractRoles.WITHDRAWER);
    }

    function isMarginTrader(address contr) internal view returns (bool) {
        return roles.getRole(contr, ContractRoles.MARGIN_TRADER);
    }

    function isFeeSource(address contr) internal view returns (bool) {
        return roles.getRole(contr, ContractRoles.FEE_SOURCE);
    }

    function isMarginCaller(address contr) internal view returns (bool) {
        return roles.getRole(contr, ContractRoles.MARGIN_CALLER);
    }

    function isInsuranceClaimant(address contr) internal view returns (bool) {
        return roles.getRole(contr, ContractRoles.INSURANCE_CLAIMANT);
    }

    function isIncentiveReporter(address contr) internal view returns (bool) {
        return roles.getRole(contr, ContractRoles.INCENTIVE_REPORTER);
    }
}
