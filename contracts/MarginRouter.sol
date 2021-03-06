// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "../libraries/UniswapV2Library.sol";

import "./RoleAware.sol";
import "./Fund.sol";
import "../interfaces/IMarginTrading.sol";
import "./Lending.sol";
import "./Admin.sol";
import "./IncentivizedHolder.sol";

contract MarginRouter is RoleAware, IncentivizedHolder, Ownable {
    /// different uniswap compatible factories to talk to
    mapping(address => bool) public factories;
    /// wrapped ETH ERC20 contract
    address public WETH;
    address public constant UNI = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address public constant SUSHI = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    /// emitted when a trader depoits on cross margin
    event CrossDeposit(
        address trader,
        address depositToken,
        uint256 depositAmount
    );
    /// emitted whenever a trade happens
    event CrossTrade(
        address trader,
        address inToken,
        uint256 inTokenAmount,
        uint256 inTokenBorrow,
        address outToken,
        uint256 outTokenAmount,
        uint256 outTokenExtinguish
    );
    /// emitted when a trader withdraws funds
    event CrossWithdraw(
        address trader,
        address withdrawToken,
        uint256 withdrawAmount
    );
    /// emitted upon sucessfully borrowing
    event CrossBorrow(
        address trader,
        address borrowToken,
        uint256 borrowAmount
    );

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "Trade has expired");
        _;
    }

    constructor(address _WETH, address _roles) RoleAware(_roles) {
        factories[UNI] = true;
        factories[SUSHI] = true;

        WETH = _WETH;
    }

    function authorizeAMM(address ammFactory) external onlyOwner {
        factories[ammFactory] = true;
    }

    /// @dev traders call this to deposit funds on cross margin
    function crossDeposit(address depositToken, uint256 depositAmount)
        external
    {
        require(
            Fund(fund()).depositFor(msg.sender, depositToken, depositAmount),
            "Cannot transfer deposit to margin account"
        );
        uint256 extinguishAmount =
            IMarginTrading(marginTrading()).registerDeposit(
                msg.sender,
                depositToken,
                depositAmount
            );
        if (extinguishAmount > 0) {
            Lending(lending()).payOff(depositToken, extinguishAmount);
            withdrawClaim(msg.sender, depositToken, extinguishAmount);
        }
        emit CrossDeposit(msg.sender, depositToken, depositAmount);
    }

    /// @dev deposit wrapped ehtereum into cross margin account
    function crossDepositETH() external payable {
        Fund(fund()).depositToWETH{value: msg.value}();
        uint256 extinguishAmount =
            IMarginTrading(marginTrading()).registerDeposit(
                msg.sender,
                WETH,
                msg.value
            );
        if (extinguishAmount > 0) {
            Lending(lending()).payOff(WETH, extinguishAmount);
            withdrawClaim(msg.sender, WETH, extinguishAmount);
        }
        emit CrossDeposit(msg.sender, WETH, msg.value);
    }

    /// @dev withdraw deposits/earnings from cross margin account
    function crossWithdraw(address withdrawToken, uint256 withdrawAmount)
        external
    {
        IMarginTrading(marginTrading()).registerWithdrawal(
            msg.sender,
            withdrawToken,
            withdrawAmount
        );
        require(
            Fund(fund()).withdraw(withdrawToken, msg.sender, withdrawAmount),
            "Could not withdraw from fund"
        );
        emit CrossWithdraw(msg.sender, withdrawToken, withdrawAmount);
    }

    /// @dev withdraw ethereum from cross margin account
    function crossWithdrawETH(uint256 withdrawAmount) external {
        IMarginTrading(marginTrading()).registerWithdrawal(
            msg.sender,
            WETH,
            withdrawAmount
        );
        Fund(fund()).withdrawETH(msg.sender, withdrawAmount);
    }

    /// @dev borrow into cross margin trading account
    function crossBorrow(address borrowToken, uint256 borrowAmount) external {
        Lending(lending()).registerBorrow(borrowToken, borrowAmount);
        IMarginTrading(marginTrading()).registerBorrow(
            msg.sender,
            borrowToken,
            borrowAmount
        );

        stakeClaim(msg.sender, borrowToken, borrowAmount);
        emit CrossBorrow(msg.sender, borrowToken, borrowAmount);
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(
        address factory,
        uint256[] memory amounts,
        address[] memory path,
        address _to
    ) internal virtual {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = UniswapV2Library.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) =
                input == token0
                    ? (uint256(0), amountOut)
                    : (amountOut, uint256(0));
            address to =
                i < path.length - 2
                    ? UniswapV2Library.pairFor(factory, output, path[i + 2])
                    : _to;
            IUniswapV2Pair(UniswapV2Library.pairFor(factory, input, output))
                .swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    /// @dev internal helper swapping exact token for token on AMM
    function _swapExactT4T(
        address factory,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path
    ) internal returns (uint256[] memory amounts) {
        amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);
        require(
            amounts[amounts.length - 1] >= amountOutMin,
            "MarginRouter: INSUFFICIENT_OUTPUT_AMOUNT"
        );
        require(
            Fund(fund()).withdraw(
                path[0],
                UniswapV2Library.pairFor(factory, path[0], path[1]),
                amounts[0]
            ),
            "MarginRouter: Insufficient lending funds"
        );
        _swap(factory, amounts, path, fund());
    }

    /// @dev external function to make swaps on AMM using protocol funds, only for authorized contracts
    function authorizedSwapExactT4T(
        address factory,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path
    ) external returns (uint256[] memory) {
        require(
            isAuthorizedFundTrader(msg.sender),
            "Calling contract is not authorized to trade with protocl funds"
        );
        return _swapExactT4T(factory, amountIn, amountOutMin, path);
    }

    // @dev internal helper swapping exact token for token on on AMM
    function _swapT4ExactT(
        address factory,
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path
    ) internal returns (uint256[] memory amounts) {
        // TODO minimum trade?
        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        require(
            amounts[0] <= amountInMax,
            "MarginRouter: EXCESSIVE_INPUT_AMOUNT"
        );
        require(
            Fund(fund()).withdraw(
                path[0],
                UniswapV2Library.pairFor(factory, path[0], path[1]),
                amounts[0]
            ),
            "MarginRouter: Insufficient lending funds"
        );
        _swap(factory, amounts, path, fund());
    }

    //// @dev external function for swapping protocol funds on AMM, only for authorized
    function authorizedSwapT4ExactT(
        address factory,
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path
    ) external returns (uint256[] memory) {
        require(
            isAuthorizedFundTrader(msg.sender),
            "Calling contract is not authorized to trade with protocl funds"
        );
        return _swapT4ExactT(factory, amountOut, amountInMax, path);
    }

    /// @dev entry point for swapping tokens held in cross margin account
    function crossSwapExactTokensForTokens(
        address ammFactory,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        // calc fees
        uint256 fees =
            Admin(feeController()).subtractTradingFees(path[0], amountIn);

        requireAuthorizedAMM(ammFactory);
        // swap
        amounts = _swapExactT4T(
            ammFactory,
            amountIn - fees,
            amountOutMin,
            path
        );

        registerTrade(
            msg.sender,
            path[0],
            path[path.length - 1],
            amountIn,
            amounts[amounts.length - 1]
        );
    }

    /// @dev entry point for swapping tokens held in cross margin account
    function crossSwapTokensForExactTokens(
        address ammFactory,
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        // calc fees
        uint256 fees =
            Admin(feeController()).addTradingFees(
                path[path.length - 1],
                amountOut
            );

        requireAuthorizedAMM(ammFactory);
        // swap
        amounts = _swapT4ExactT(
            ammFactory,
            amountOut + fees,
            amountInMax,
            path
        );

        registerTrade(
            msg.sender,
            path[0],
            path[path.length - 1],
            amounts[0],
            amountOut
        );
    }

    /// @dev helper function does all the work of telling other contracts
    /// about a trade
    function registerTrade(
        address trader,
        address inToken,
        address outToken,
        uint256 inAmount,
        uint256 outAmount
    ) internal {
        (uint256 extinguishAmount, uint256 borrowAmount) =
            IMarginTrading(marginTrading()).registerTradeAndBorrow(
                trader,
                inToken,
                outToken,
                inAmount,
                outAmount
            );
        if (extinguishAmount > 0) {
            Lending(lending()).payOff(outToken, extinguishAmount);
            withdrawClaim(trader, outToken, extinguishAmount);
        }
        if (borrowAmount > 0) {
            Lending(lending()).registerBorrow(inToken, borrowAmount);
            stakeClaim(trader, inToken, borrowAmount);
        }

        emit CrossTrade(
            trader,
            inToken,
            inAmount,
            borrowAmount,
            outToken,
            outAmount,
            extinguishAmount
        );
    }

    function getAmountsOut(
        address factory,
        uint256 inAmount,
        address[] calldata path
    ) external view returns (uint256[] memory) {
        return UniswapV2Library.getAmountsOut(factory, inAmount, path);
    }

    function getAmountsIn(
        address factory,
        uint256 outAmount,
        address[] calldata path
    ) external view returns (uint256[] memory) {
        return UniswapV2Library.getAmountsIn(factory, outAmount, path);
    }

    function requireAuthorizedAMM(address ammFactory) internal view {
        require(
            ammFactory == UNI || ammFactory == SUSHI || factories[ammFactory],
            "Not using an authorized AMM"
        );
    }
}
