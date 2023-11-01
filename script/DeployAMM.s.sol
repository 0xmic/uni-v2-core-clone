// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Script} from "forge-std/Script.sol";
import {Token} from "../src/Token.sol";
import {AMMPair} from "../src/AMMPair.sol";
import {AMMFactory} from "../src/AMMFactory.sol";

contract DeployAMM is Script {
    uint256 public constant INITIAL_SUPPLY = 1_000_000 ether; // 1 million tokens with 18 decimal places
    
    uint256 public DEFAULT_ANVIL_PRIVATE_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    uint256 public deployerKey;
    address public deployerAddress;

    string private constant TOKEN1_NAME = "Crypto Token";
    string private constant TOKEN1_SYMBOL = "CT";

    string private constant TOKEN2_NAME = "USD Token";
    string private constant TOKEN2_SYMBOL = "USD";    

    function run() external returns (Token token1, Token token2, AMMPair amm) {
        if (block.chainid == 31337) {
            deployerKey = DEFAULT_ANVIL_PRIVATE_KEY;
        } else {
            deployerKey = vm.envUint("PRIVATE_KEY");
        }

        deployerAddress = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);
        token1 = new Token(INITIAL_SUPPLY, TOKEN1_NAME, TOKEN1_SYMBOL);
        token2 = new Token(INITIAL_SUPPLY, TOKEN2_NAME, TOKEN2_SYMBOL);
        AMMFactory factory = new AMMFactory();
        amm = AMMPair(factory.createPair(address(token1), address(token2)));
        vm.stopBroadcast();

        return (token1, token2, amm);
    }
}
