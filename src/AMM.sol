/**
 * TODO: Implement fixed point math for more precise calculations
 * TODO: Implement last recorded balance of token1 and token2 to calculate the TWAP and prevent oracle manipulation 
 * TODO: Implement flash swaps with EIP 3156
 */
//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.21;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title AMM (Automated Market Maker)
 * @dev This contract implements an AMM with two Token assets for liquidity providing and swapping.
 */ 
contract AMM {
    using SafeERC20 for IERC20;

    /**
     * @dev Public state variables
     */
    IERC20 public token1;
    IERC20 public token2;

    uint256 public token1Balance;
    uint256 public token2Balance;
    uint256 public K;

    uint256 public totalShares;
    mapping(address => uint256) public shares;
    uint256 public constant PRECISION = 10 ** 18;

    /**
     * @dev Event emitted when a token swap happens
     */
    event Swap(
        address user,
        address tokenGive,
        uint256 tokenGiveAmount,
        address tokenGet,
        uint256 tokenGetAmount,
        uint256 token1Balance,
        uint256 token2Balance,
        uint256 timestamp
    );

    /**
     * @dev Initializes the tokens for the AMM
     * @param _token1Address Address of the first token
     * @param _token2Address Address of the second token
     */
    constructor(address _token1Address, address _token2Address) {
        token1 = IERC20(_token1Address);
        token2 = IERC20(_token2Address);
    }

    /**
     * @dev Allows users to add liquidity to the pool
     * @param _token1Amount Amount of the first token to add
     * @param _token2Amount Amount of the second token to add
     */
    function addLiquidity(uint256 _token1Amount, uint256 _token2Amount) external {
        token1.transferFrom(msg.sender, address(this), _token1Amount);
        token2.transferFrom(msg.sender, address(this), _token2Amount);

        // Issue Shares
        uint256 share;

        // If first time adding liquidity, make share 100
        if (totalShares == 0) {
            share = 100 * PRECISION;
        } else {
            uint256 share1 = (_token1Amount * totalShares) / token1Balance;
            uint256 share2 = (_token2Amount * totalShares) / token2Balance;
            require((share1 / 10**3) == (share2 / 10**3), 'Must provide equal share amounts');
            share = share1;
        }

        // Manage Pool
        token1Balance += _token1Amount;
        token2Balance += _token2Amount;
        K = token1Balance * token2Balance;

        // Update Shares
        totalShares += share;
        shares[msg.sender] += share;
    }

    /**
     * @dev This function allows users to remove liquidity from the pool
     * @param _share Amount of liquidity shares to remove
     * @return token1Amount Amount of the first token received
     * @return token2Amount Amount of the second token received
     */
    function removeLiquidity(uint256 _share)
        external
        returns(uint256 token1Amount, uint256 token2Amount)
    {
        require(_share <= shares[msg.sender], "Must be less than or equal to your shares");

        (token1Amount, token2Amount) = calculateWithdrawAmount(_share);

        shares[msg.sender] -= _share;
        totalShares -= _share;

        token1Balance -= token1Amount;
        token2Balance -= token2Amount;
        K = token1Balance * token2Balance;

        token1.safeTransfer(msg.sender, token1Amount);
        token2.safeTransfer(msg.sender, token2Amount);
    }

    /**
     * @dev Calculates how much of token2 an LP needs to deposit for a specific amount of token1
     * @param _token1Amount Amount of the first token for the calculation
     */
    function calculateToken2Deposit(uint256 _token1Amount)
        public
        view
        returns(uint256 _token2Amount)
    {
        _token2Amount = (token2Balance * _token1Amount) / token1Balance;
    }

    /**
     * @dev Calculates how much of token1 an LP needs to deposit for a specific amount of token2
     * @param _token2Amount Amount of the second token for the calculation
     */
    function calculateToken1Deposit(uint256 _token2Amount)
        public
        view
        returns(uint256 _token1Amount)
    {
        _token1Amount = (token1Balance * _token2Amount) / token2Balance;
    }

    /**
     * @dev Calculates how much of token2 is received when swapping token1
     * @param _token1Amount Amount of the first token to swap
     */
    function calculateToken1Swap(uint256 _token1Amount)
        public
        view
        returns (uint256 token2Amount)
    {
        uint256 token1After = token1Balance + _token1Amount;
        uint256 token2After = K / token1After;
        token2Amount = token2Balance - token2After;

        // Don't let pool go to 0
        if(token2Amount == token2Balance) {
            token2Amount --;
        }

        require(token2Amount < token2Balance, 'Swap cannot exceed pool balance');
    }

    /**
     * @dev This function allows users to swap token1 for token2
     * @param _token1Amount Amount of the first token to swap
     */
    function swapToken1(uint256 _token1Amount)
        external
        returns(uint256 token2Amount)
    {
        // Calculate Token 2 Amount
        token2Amount = calculateToken1Swap(_token1Amount);

        // Do Swap
        token1.safeTransferFrom(msg.sender, address(this), _token1Amount);
        token1Balance += _token1Amount;
        token2Balance -= token2Amount;
        token2.safeTransfer(msg.sender, token2Amount);

        // Emit an event
        emit Swap(
            msg.sender,
            address(token1),
            _token1Amount,
            address(token2),
            token2Amount,
            token1Balance,
            token2Balance,
            block.timestamp
        );
    }

    /**
     * @dev This function calculates how much of token1 is received when swapping token2
     * @param _token2Amount Amount of the second token to swap
     */
    function calculateToken2Swap(uint256 _token2Amount)
        public
        view
        returns (uint256 token1Amount)
    {
        uint256 token2After = token2Balance + _token2Amount;
        uint256 token1After = K / token2After;
        token1Amount = token1Balance - token1After;

        // Don't let pool go to 0
        if(token1Amount == token1Balance) {
            token1Amount --;
        }

        require(token1Amount < token1Balance, 'Swap cannot exceed pool balance');
    }

    /**
     * @dev This function allows users to swap token2 for token1
     * @param _token2Amount Amount of the second token to swap
     */
    function swapToken2(uint256 _token2Amount)
        external
        returns(uint256 token1Amount)
    {
        // Calculate Token 1 Amount
        token1Amount = calculateToken2Swap(_token2Amount);

        // Do Swap
        token2.safeTransferFrom(msg.sender, address(this), _token2Amount);
        token2Balance += _token2Amount;
        token1Balance -= token1Amount;
        token1.safeTransfer(msg.sender, token1Amount);

        // Emit an event
        emit Swap(
            msg.sender,
            address(token2),
            _token2Amount,
            address(token1),
            token1Amount,
            token1Balance,
            token2Balance,
            block.timestamp
        );
    }

    /**
     * @dev This function calculates the amounts of token1 and token2 that an LP will withdraw for a specific share
     * @param _share Amount of liquidity shares to calculate the withdrawal for
     */
    function calculateWithdrawAmount(uint256 _share)
        public
        view
        returns(uint256 token1Amount, uint256 token2Amount)
    {
        require(_share < totalShares, "Must be less than total shares");
        token1Amount = (_share * token1Balance) / totalShares;
        token2Amount = (_share * token2Balance) / totalShares;
    }
}
