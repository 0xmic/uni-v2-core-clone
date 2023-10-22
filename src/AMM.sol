//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.21;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";

/**
 * @title AMM (Automated Market Maker)
 * @dev This contract implements an AMM with two Token assets for liquidity providing and swapping.
 */ 
contract AMM is IERC3156FlashLender {
    using SafeERC20 for IERC20;

    /**
     * @dev Public state variables
     */
    IERC20 public token1;
    IERC20 public token2;

    uint256 public token1Balance;
    uint256 public token2Balance;
    uint256 public K;

    mapping(address => uint256) public shares;
    uint256 public totalShares;
    uint256 public constant PRECISION = 10 ** 18;

    uint256 public feeRate = 50; // 50 basis points = 0.5% fee

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
            require((share1 / 10**3) == (share2 / 10**3), "Must provide equal share amounts");
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
    function removeLiquidity(uint256 _share) external returns(uint256 token1Amount, uint256 token2Amount) {
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
    function calculateToken2Deposit(uint256 _token1Amount) public view returns(uint256 _token2Amount) {
        _token2Amount = (token2Balance * _token1Amount) / token1Balance;
    }

    /**
     * @dev Calculates how much of token1 an LP needs to deposit for a specific amount of token2
     * @param _token2Amount Amount of the second token for the calculation
     */
    function calculateToken1Deposit(uint256 _token2Amount) public view returns(uint256 _token1Amount) {
        _token1Amount = (token1Balance * _token2Amount) / token2Balance;
    }

    /**
     * @dev Calculates how much of token2 is received when swapping token1
     * @param _token1Amount Amount of the first token to swap
     */
    function calculateToken1Swap(uint256 _token1Amount) public view returns (uint256 token2Amount) {
        uint256 token1After = token1Balance + _token1Amount;
        uint256 token2After = K / token1After;
        token2Amount = token2Balance - token2After;

        // Don't let pool go to 0
        if(token2Amount == token2Balance) {
            token2Amount --;
        }

        require(token2Amount < token2Balance, "Swap cannot exceed pool balance");
    }

    /**
     * @dev This function allows users to swap token1 for token2
     * @param _token1Amount Amount of the first token to swap
     */
    function swapToken1(uint256 _token1Amount) external returns(uint256 token2Amount) {
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
    function calculateToken2Swap(uint256 _token2Amount) public view returns (uint256 token1Amount) {
        uint256 token2After = token2Balance + _token2Amount;
        uint256 token1After = K / token2After;
        token1Amount = token1Balance - token1After;

        // Don't let pool go to 0
        if(token1Amount == token1Balance) {
            token1Amount --;
        }

        require(token1Amount < token1Balance, "Swap cannot exceed pool balance");
    }

    /**
     * @dev This function allows users to swap token2 for token1
     * @param _token2Amount Amount of the second token to swap
     */
    function swapToken2(uint256 _token2Amount) external returns (uint256 token1Amount) {
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
        public view returns (uint256 token1Amount, uint256 token2Amount)
    {
        require(_share < totalShares, "Must be less than total shares");
        token1Amount = (_share * token1Balance) / totalShares;
        token2Amount = (_share * token2Balance) / totalShares;
    }

    /**
     * @dev Initiate a flash loan.
     * @param receiver The receiver of the tokens in the loan, and the receiver of the callback.
     * @param token The loan currency.
     * @param amount The amount of tokens lent.
     * @param data Arbitrary data structure, intended to contain user-defined parameters.
     */
    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) external override returns (bool) {
        require(token == address(token1) || token == address(token2), "Unsupported token");
        uint256 fee = _flashFee(amount);
        uint256 balanceBefore = (token == address(token1) ? token1Balance : token2Balance);
        
        // Transfer tokens to receiver
        IERC20(token).safeTransfer(address(receiver), amount);
        require(
            receiver.onFlashLoan(msg.sender, token, amount, fee, data) ==
            keccak256("ERC3156FlashBorrower.onFlashLoan"),
            "IERC3156: Callback failed"
        );

        // Check that the loan has been paid back
        uint256 balanceAfter = IERC20(token).balanceOf(address(this));
        require(balanceAfter == balanceBefore + fee, "Flash loan hasn't been paid back properly");
        token == address(token1) ? token1Balance += fee : token2Balance += fee;

        return true;
    }

    /**
     * @dev The fee to be charged for a given loan.
     * @param token The loan currency.
     * @param amount The amount of tokens lent.
     * @return The amount of `token` to be charged for the loan, on top of the returned principal.
     */
    function flashFee(address token, uint256 amount) external view override returns (uint256) {
        require(token == address(token1) || token == address(token2), "Unsupported token");
        return _flashFee(amount);
    }

    /**
     * @dev The fee to be charged for a given loan. Internal function with no checks.
     * @param amount The amount of tokens lent.
     * @return The amount of `token` to be charged for the loan, on top of the returned principal.
     */
    function _flashFee(
        uint256 amount
    ) internal view returns (uint256) {
        return amount * feeRate / 10000;
    }

    /**
     * @dev The amount of currency available to be lended.
     * @param token The loan currency.
     * @return The amount of `token` that can be borrowed.
     */
    function maxFlashLoan(address token) external view override returns (uint256) {
        if (token == address(token1)) {
            return token1Balance;
        } else if (token == address(token2)) {
            return token2Balance;
        } else {
            return 0;
        }
    }
}
