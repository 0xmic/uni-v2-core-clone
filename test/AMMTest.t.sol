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
    address public withdrawUser;

    uint256 WAIT_DURATION = 3 days;

    function setUp() public {
        deployer = new DeployAMM();
        (token1, token2, amm) = deployer.run();
        deployerAddress = deployer.deployerAddress();
    }

    function test_AMMAddress() public {
        // console log amm address
        console2.log("AMM Address", address(amm));
        assertFalse(address(amm) == address(0));
    }
}
