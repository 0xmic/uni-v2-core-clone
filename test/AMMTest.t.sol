// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {Test, console2} from "forge-std/Test.sol";
import {StdCheats, console2} from "forge-std/StdCheats.sol";
import {Token} from "../src/Token.sol";
import {AMM} from "../src/AMM.sol";
import {DeployAMM} from "../script/DeployAMM.s.sol";

contract BondingCurveTokenTest is StdCheats, Test {
    Token public token1;
    Token public token2;
    AMM public amm;
    DeployAMM public deployer;

    address public deployerAddress;
    address public liquidityProvider;
    address public investor1;
    address public investor2;

    uint256 public constant PRECISION = 10 ** 18;

    function setUp() public {
        // Setup Accounts
        liquidityProvider = makeAddr("liquidityProvider");
        investor1 = makeAddr("investor1");
        investor2 = makeAddr("investor2");
        
        deployer = new DeployAMM();
        (token1, token2, amm) = deployer.run();
        deployerAddress = deployer.deployerAddress();

        // Send tokens to liquidity provider
        vm.startPrank(deployerAddress);
        token1.transfer(liquidityProvider, 100_000 ether);
        token2.transfer(liquidityProvider, 100_000 ether);

        // Send token1 to investor1
        token1.transfer(investor1, 100_000 ether);

        // Send token2 to investor2
        token2.transfer(investor2, 100_000 ether);
        vm.stopPrank();
    }

    function test_AddLiquidity() public {
        // ----------------------------------------------------
        // Deployer adds liquidity

        // Deployer approves 100k tokens
        vm.startPrank(deployerAddress);
        token1.approve(address(amm), 100_000 ether);
        token2.approve(address(amm), 100_000 ether);

        // Deployer adds liquidity
        amm.addLiquidity(100_000 ether, 100_000 ether);
        vm.stopPrank();

        // Check AMM receives tokens
        assertEq(token1.balanceOf(address(amm)), 100_000 ether);
        assertEq(token2.balanceOf(address(amm)), 100_000 ether);

        assertEq(amm.token1Balance(), 100_000 ether);
        assertEq(amm.token2Balance(), 100_000 ether);

        // Check deployer has 100 shares
        assertEq(amm.shares(deployerAddress), 100 * PRECISION);

        // Check pool has 100 total shares
        assertEq(amm.totalShares(), 100 * PRECISION);

        // ----------------------------------------------------
        // LP adds more liquidity
        
        // LP approves 50k tokens
        uint256 amount = 50_000 ether;

        vm.startPrank(liquidityProvider);
        token1.approve(address(amm), amount);
        token2.approve(address(amm), amount);

        // Calculate token2Deposit amount
        uint256 token2Deposit = amm.calculateToken2Deposit(amount);

        // LP adds liquidity
        amm.addLiquidity(amount, token2Deposit);
        vm.stopPrank();

        // LP should have 50 shares
        assertEq(amm.shares(liquidityProvider), 50 * PRECISION);

        // Deployer should still have 100 shares
        assertEq(amm.shares(deployerAddress), 100 * PRECISION);

        // Pool should have 150 total shares
        assertEq(amm.totalShares(), 150 * PRECISION);

        // Check price before swapping
        console2.log("CT Price: ", (amm.token2Balance() * PRECISION) / amm.token1Balance(), "\n");

    }

    function test_Swap() public {
        test_AddLiquidity();

        // ----------------------------------------------------
        // Investor 1 swaps

        console2.log("Investor1 swaps");

        // Investor1 approves all tokens
        vm.startPrank(investor1);
        token1.approve(address(amm), 100_000 ether);

        // Check investor1 balance of token2 before swap
        console2.log("Investor1 Token2 balance before swap: ", token2.balanceOf(investor1));
        assertEq(token2.balanceOf(investor1), 0 ether);

        // Estimate amount of tokens investor1 will receive after swapping 1 token1: includes slippage
        uint256 estimate = amm.calculateToken1Swap(1 ether);
        console2.log("Token2 amount investor1 will receive after swap: ", estimate);

        // Investor1 swaps 1 token1
        amm.swapToken1(1 ether);

        // Check investor1 balance after swap
        uint256 balance = token2.balanceOf(investor1);
        console2.log("Investor1 Token2 balance after swap: ", balance);
        assertEq(balance, estimate);

        // Check AMM balances are in sync
        assertEq(token1.balanceOf(address(amm)), amm.token1Balance());
        assertEq(token2.balanceOf(address(amm)), amm.token2Balance());

        // Check price after swapping (taking into account decimal precision)
        console2.log("CT Price: ", (amm.token2Balance() * PRECISION) / amm.token1Balance(), "\n");

        // ----------------------------------------------------
        // Investor 1 swaps again

        console2.log("Investor1 swaps again");

        // Investor1 balance before swapping
        console2.log("Investor1 Token2 balance before swap: ", token2.balanceOf(investor1));

        // Estimate amount of Token2 investor1 will receive after swapping 1 token1: includes slippage
        estimate = amm.calculateToken1Swap(1 ether);
        console2.log("Token2 amount investor1 will receive after swap: ", estimate);

        // Investor1 swaps 1 token
        amm.swapToken1(1 ether);

        // Check investor1 balance after swap
        balance = token2.balanceOf(investor1);
        console2.log("Investor1 Token2 balance after swap: ", balance);

        // Check AMM token balances are in sync
        assertEq(token1.balanceOf(address(amm)), amm.token1Balance());
        assertEq(token2.balanceOf(address(amm)), amm.token2Balance());

        // Check price after swapping
        console2.log("CT Price: ", (amm.token2Balance() * PRECISION) / amm.token1Balance(), "\n");

        // ----------------------------------------------------
        // Investor1 swaps a large amount

        console2.log("Investor1 swaps a large amount");

        // Check investor1 balance before swapping
        console2.log("Investor1 Token2 balance before swap: ", token2.balanceOf(investor1));

        // Estimate amount of Token2 investor1 will receive after swapping 100 token1: includes slippage
        estimate = amm.calculateToken1Swap(100 ether);
        console2.log("Token2 amount investor1 will receive after swap: ", estimate);

        // Investor1 swaps 100 token1
        amm.swapToken1(100 ether);
        vm.stopPrank();

        // Check investor1 balance after swap
        balance = token2.balanceOf(investor1);
        console2.log("Investor1 Token2 balance after swap: ", balance);

        // Check AMM token balances are in sync
        assertEq(token1.balanceOf(address(amm)), amm.token1Balance());
        assertEq(token2.balanceOf(address(amm)), amm.token2Balance());

        // Check price after swapping
        console2.log("CT Price: ", (amm.token2Balance() * PRECISION) / amm.token1Balance(), "\n");

        // ----------------------------------------------------
        // Investor2 swaps

        console2.log("Investor2 swaps");

        // Investor2 approves all tokens
        vm.startPrank(investor2);
        token2.approve(address(amm), 100_000 ether);

        // Check investor2 balance of token1 before swap
        console2.log("Investor2 Token1 balance before swap: ", token1.balanceOf(investor2));

        // Estimate amount of tokens investor2 will receive after swapping 1 token2: includes slippage
        estimate = amm.calculateToken2Swap(1 ether);
        console2.log("Token1 amount investor2 will receive after swap: ", estimate);

        // Investor2 swaps 1 token2
        amm.swapToken2(1 ether);
        vm.stopPrank();

        // Check investor2 balance after swap
        balance = token1.balanceOf(investor2);

        // Check AMM token balances are in sync
        assertEq(token1.balanceOf(address(amm)), amm.token1Balance());
        assertEq(token2.balanceOf(address(amm)), amm.token2Balance());

        // Check price after swapping
        console2.log("CT Price: ", (amm.token2Balance() * PRECISION) / amm.token1Balance(), "\n");
    }

    function test_RemoveLiquidity() public {
        test_Swap();

        // ----------------------------------------------------
        // Removing Liquidity

        console2.log("Removing Liquidity");

        console2.log("AMM Token1 Balance: ", amm.token1Balance());
        console2.log("AMM Token2 Balance: ", amm.token2Balance());

        // Check LP balance before removing tokens
        console2.log("LP Token1 Balance before removing tokens: ", token1.balanceOf(liquidityProvider));
        console2.log("LP Token2 Balance before removing tokens: ", token2.balanceOf(liquidityProvider));

        // LP removes tokens from AMM pool
        vm.startPrank(liquidityProvider);
        amm.removeLiquidity(50 * PRECISION);

        // Check LP balances after removing tokens
        console2.log("LP Token1 Balance after removing tokens: ", token1.balanceOf(liquidityProvider));
        console2.log("LP Token2 Balance after removing tokens: ", token2.balanceOf(liquidityProvider));

        // LP should have 0 shares
        assertEq(amm.shares(liquidityProvider), 0);

        // Deployer should still have 100 shares
        assertEq(amm.shares(deployerAddress), 100 * PRECISION);

        // AMM Pool should have 100 shares
        assertEq(amm.totalShares(), 100 * PRECISION);
    }

    function test_FlashSwap() public {
        test_AddLiquidity();

        // TODO: Implement flash swap test
    }

    // function test_TWAP()

}
