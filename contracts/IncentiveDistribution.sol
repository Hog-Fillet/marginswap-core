import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./RoleAware.sol";
import "./Fund.sol";

struct Claim {
    uint256 startingRewardRate;
    address recipient;
    uint256 amount;
}

abstract contract IncentiveDistribution is RoleAware, Ownable {
    uint256 contractionPerMil = 999;
    address MFI;

    constructor(
        address _MFI,
        uint256 startingDailyDistribution,
        address _roles
    ) RoleAware(_roles) Ownable() {
        MFI = _MFI;
        currentDailyDistribution = startingDailyDistribution;
        // TODO init all the values for the first day / first hour
    }

    uint256 public currentDailyDistribution;
    uint256[] public tranchePercentShare;

    // TODO initialize non-zero
    mapping(uint8 => uint256) public currentDayTotals;
    mapping(uint8 => uint256[24]) public hourlyTotals;
    mapping(uint8 => uint256) public currentHourTotals;
    mapping(uint8 => uint256) public lastUpdatedHours;
    mapping(uint8 => uint256) public ongoingTotals;

    // Here's the crux: rewards are aggregated hourly for ongoing incentive distribution
    // If e.g. a lender keeps their money in for several days, then their reward is going to be
    // amount * (reward_rate_hour1 + reward_rate_hour2 + reward_rate_hour3...)
    // where reward_rate is the amount of incentive per trade volume / lending volume
    mapping(uint8 => uint256) public aggregateHourlyRewardRate;
    mapping(uint256 => Claim) public claims;
    uint256 public nextClaimId;

    function getSpotReward(
        uint8 tranche,
        address recipient,
        uint256 spotAmount
    ) external {
        require(isIncentiveReporter(msg.sender), "Contract not authorized to report incentives");

        updateHourTotals(tranche);
        currentHourTotals[tranche] += spotAmount;
        uint256 rewardAmount = spotAmount * currentHourlyRewardRate(tranche);
        Fund(fund()).withdraw(MFI, recipient, rewardAmount);
    }

    function updateHourTotals(uint8 tranche) internal {
        uint256 currentHour = (block.timestamp % (1 days)) / (1 hours);
        uint256 lastUpdatedHour = lastUpdatedHours[tranche];
        if (lastUpdatedHour != currentHour) {
            lastUpdatedHours[tranche] = currentHour;
            // This will skip hours if there has been no calls to this function in that tranche
            // In which case our rates are going to be somewhat out of whack anyway,
            // so we won't mind too much
            aggregateHourlyRewardRate[tranche] += currentHourlyRewardRate(
                tranche
            );
            currentDayTotals[tranche] -= hourlyTotals[tranche][lastUpdatedHour];
            hourlyTotals[tranche][lastUpdatedHour] = currentHourTotals[tranche];
            currentDayTotals[tranche] += hourlyTotals[tranche][lastUpdatedHour];
            currentHourTotals[tranche] = ongoingTotals[tranche];
            if (currentHour == 0) {
                currentDailyDistribution =
                    (currentDailyDistribution * contractionPerMil) /
                    1000;
            }
        }
    }

    function currentHourlyRewardRate(uint8 tranche) internal returns (uint256) {
        uint256 trancheDailyDistribution =
            (currentDailyDistribution * tranchePercentShare[tranche]) / 100;
        return trancheDailyDistribution / currentDayTotals[tranche] / 24;
    }

    function startClaim(
        uint8 tranche,
        address recipient,
        uint256 claimAmount
    ) external returns (uint256) {
        require(isIncentiveReporter(msg.sender), "Contract not authorized to report incentives");
        updateHourTotals(tranche);
        ongoingTotals[tranche] += claimAmount;
        currentHourTotals[tranche] += claimAmount;
        claims[nextClaimId] = Claim({
            startingRewardRate: aggregateHourlyRewardRate[tranche],
            recipient: recipient,
            amount: claimAmount
        });
        nextClaimId += 1;
        return nextClaimId - 1;
    }

    function addToClaimAmount(uint8 tranche, uint256 claimId, uint256 additionalAmount) external {
        require(isIncentiveReporter(msg.sender), "Contract not authorized to report incentives");
        updateHourTotals(tranche);

        Claim storage claim = claims[claimId];
        // add all rewards accrued up to now
        claim.startingRewardRate -= claim.amount / calcRewardAmount(tranche, claim);
        claim.amount += additionalAmount;
    }

    function subtractFromClaimAmount(uint8 tranche, uint256 claimId, uint256 subtractAmount) external {
        require(isIncentiveReporter(msg.sender), "Contract not authorized to report incentives");
        updateHourTotals(tranche);

        Claim storage claim = claims[claimId];
        // add all rewards accrued up to now
        claim.startingRewardRate -= claim.amount / calcRewardAmount(tranche, claim);
        claim.amount -= subtractAmount;
    }

    function endClaim(uint8 tranche, uint256 claimId) external {
        require(isIncentiveReporter(msg.sender), "Contract not authorized to report incentives");
        updateHourTotals(tranche);
        Claim storage claim = claims[claimId];
        // TODO what if empty?
        uint256 rewardAmount = calcRewardAmount(tranche, claim);
        Fund(fund()).withdraw(MFI, claim.recipient, rewardAmount);
        delete claim.recipient;
        delete claim.startingRewardRate;
        delete claim.amount;
    }

    function calcRewardAmount(uint8 tranche, Claim storage claim) internal view returns(uint256) {
        return claim.amount *
            (aggregateHourlyRewardRate[tranche] - claim.startingRewardRate);
    }
}
