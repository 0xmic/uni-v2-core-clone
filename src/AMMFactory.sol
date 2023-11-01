// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {AMMPair} from "./AMMPair.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/** 
 * @title Automated Market Maker (AMM) Factory Contract
 * @notice This contract is used to create new AMM pairs for token exchanges
 */
contract AMMFactory {
    using SafeERC20 for IERC20;

    mapping(address => mapping(address => address)) public getPair; // token1 => token2 => pair
    address[] public allPairs;

    /**
     * @notice Event emitted when a new pair is created
     * @param token0 The first token in the pair
     * @param token1 The second token in the pair
     * @param pair Address of the new AMM pair
     * @param length Total number of pairs after adding this new pair
     */
    event PairCreated(address indexed token0, address indexed token1, address pair, uint256 length);

    /** 
     * @notice Function to get the total number of pairs created
     * @return The total number of pairs
     */
    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    /**
     * @notice Creates a new AMM pair
     * @dev Ensures the pair doesn't already exist and tokens are not identical
     * @param tokenA The first token of the pair
     * @param tokenB The second token of the pair
     * @return ammPair The address of the newly created AMM pair
     */
    function createPair(address tokenA, address tokenB) external returns (address ammPair) {
        require(tokenA != tokenB, "AMMFactory: IDENTICAL_ADDRESSES");
        (address token1, address token2) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token1 != address(0), "AMMFactory: ZERO_ADDRESS");
        require(getPair[token1][token2] == address(0), "AMMFactory: PAIR_EXISTS");

        AMMPair amm = new AMMPair(token1, token2);
        ammPair = address(amm);
        
        getPair[token1][token2] = ammPair;
        getPair[token2][token1] = ammPair; 
        allPairs.push(ammPair);
        
        emit PairCreated(token1, token2, ammPair, allPairs.length);
    }
}
