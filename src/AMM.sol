//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.21;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {UD60x18, ud} from "@prb-math/UD60x18.sol";

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

    // price
    UD60x18 public token1Balance;
    UD60x18 public token2Balance;
    UD60x18 public K;

    // shares
    mapping(address => UD60x18) public shares;
    UD60x18 public totalShares;

    // flash loan
    UD60x18 public feeRate = ud(50); // 50 basis points = 0.5% fee

    // TWAP
    UD60x18 public cumulativePrice1;
    UD60x18 public cumulativePrice2;
    uint32 public lastBlockTimestamp;


    event Swap(
        address user,
        address tokenGive,
        UD60x18 tokenGiveAmount,
        address tokenGet,
        UD60x18 tokenGetAmount,
        UD60x18 token1Balance,
        UD60x18 token2Balance,
        uint256 timestamp
    );
    event AddLiquidity(
        address indexed provider,
        UD60x18 amountToken1,
        UD60x18 amountToken2,
        UD60x18 totalToken1Balance,
        UD60x18 totalToken2Balance,
        UD60x18 sharesIssued,
        uint256 timestamp
    );
    event RemoveLiquidity(
        address indexed provider,
        UD60x18 amountToken1,
        UD60x18 amountToken2,
        UD60x18 totalToken1Balance,
        UD60x18 totalToken2Balance,
        UD60x18 sharesBurned,
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
     * @dev Calculates how much of token2 an LP needs to deposit for a specific amount of token1
     * @param _token1Amount Amount of the first token for the calculation
     */
    function calculateToken2Deposit(UD60x18 _token1Amount) external view returns(UD60x18 _token2Amount) {
        _token2Amount = _token1Amount.mul(token2Balance).div(token1Balance);
    }

    /**
     * @dev Calculates how much of token1 an LP needs to deposit for a specific amount of token2
     * @param _token2Amount Amount of the second token for the calculation
     */
    function calculateToken1Deposit(UD60x18 _token2Amount) external view returns(UD60x18 _token1Amount) {
        _token1Amount = _token2Amount.mul(token1Balance).div(token2Balance);
    }

    /**
     * @dev Allows users to add liquidity to the pool
     * @param _token1Amount Amount of the first token to add
     * @param _token2Amount Amount of the second token to add
     */
    function addLiquidity(UD60x18 _token1Amount, UD60x18 _token2Amount) external {
        token1.safeTransferFrom(msg.sender, address(this), _token1Amount.intoUint256());
        token2.safeTransferFrom(msg.sender, address(this), _token2Amount.intoUint256());

        // Issue Shares
        UD60x18 share;

        // If first time adding liquidity, make share 100
        if (totalShares.intoUint256() == 0) {
            share = ud(100e18);
        } else {
            UD60x18 share1 = _token1Amount.mul(totalShares).div(token1Balance);
            UD60x18 share2 = _token2Amount.mul(totalShares).div(token2Balance);
            require(share1 == share2, "Must provide equal share amounts");
            share = share1;
        }

        // Manage Pool
        token1Balance = token1Balance.add(_token1Amount);
        token2Balance = token2Balance.add(_token2Amount);
        K = token1Balance.mul(token2Balance);

        // Update Shares
        totalShares = totalShares.add(share);
        shares[msg.sender] = shares[msg.sender].add(share);

        _updateCumulativePrices();

        emit AddLiquidity(
            msg.sender,
            _token1Amount,
            _token2Amount,
            token1Balance,
            token2Balance,
            share,
            block.timestamp
        );
    }

    /**
     * @dev This function calculates the amounts of token1 and token2 that an LP will withdraw for a specific share
     * @param _share Amount of liquidity shares to calculate the withdrawal for
     */
    function calculateWithdrawAmount(UD60x18 _share) public view returns (UD60x18 token1Amount, UD60x18 token2Amount) {
        require(_share.lt(totalShares), "Must be less than total shares");
        token1Amount = _share.mul(token1Balance).div(totalShares);
        token2Amount = _share.mul(token2Balance).div(totalShares);
    }

    /**
     * @dev This function allows users to remove liquidity from the pool
     * @param _share Amount of liquidity shares to remove
     * @return token1Amount Amount of the first token received
     * @return token2Amount Amount of the second token received
     */
    function removeLiquidity(UD60x18 _share) external returns(UD60x18 token1Amount, UD60x18 token2Amount) {
        require(_share.lte(shares[msg.sender]), "Must be less than or equal to your shares");

        (token1Amount, token2Amount) = calculateWithdrawAmount(_share);

        // Update Shares
        shares[msg.sender] = shares[msg.sender].sub(_share);
        totalShares = totalShares.sub(_share);

        // Manage Pool
        token1Balance = token1Balance.sub(token1Amount);
        token2Balance = token2Balance.sub(token2Amount);
        K = token1Balance.mul(token2Balance);

        token1.safeTransfer(msg.sender, token1Amount.intoUint256());
        token2.safeTransfer(msg.sender, token2Amount.intoUint256());

        _updateCumulativePrices();

        emit RemoveLiquidity(
            msg.sender,
            token1Amount,
            token2Amount,
            token1Balance,
            token2Balance,
            _share,
            block.timestamp
        );
    }

    /**
     * @dev Calculates how much of token2 is received when swapping token1
     * @param _token1Amount Amount of the first token to swap
     */
    function calculateToken1Swap(UD60x18 _token1Amount) public view returns (UD60x18 token2Amount) {
        UD60x18 token1After = token1Balance.add(_token1Amount);
        UD60x18 token2After = K.div(token1After);
        token2Amount = token2Balance.sub(token2After);

        require(token2Amount.lt(token2Balance), "Swap cannot exceed pool balance");
    }

    /**
     * @dev This function allows users to swap token1 for token2
     * @param _token1Amount Amount of the first token to swap
     */
    function swapToken1(UD60x18 _token1Amount) external returns(UD60x18 token2Amount) {
        // Calculate Token 2 Amount
        token2Amount = calculateToken1Swap(_token1Amount);

        // Do Swap
        token1.safeTransferFrom(msg.sender, address(this), _token1Amount.intoUint256());
        token1Balance = token1Balance.add(_token1Amount);
        token2Balance = token2Balance.sub(token2Amount);
        token2.safeTransfer(msg.sender, token2Amount.intoUint256());

        _updateCumulativePrices();

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
    function calculateToken2Swap(UD60x18 _token2Amount) public view returns (UD60x18 token1Amount) {
        UD60x18 token2After = token2Balance.add(_token2Amount);
        UD60x18 token1After = K.div(token2After);
        token1Amount = token1Balance.sub(token1After);

        require(token1Amount.lt(token1Balance), "Swap cannot exceed pool balance");
    }

    /**
     * @dev This function allows users to swap token2 for token1
     * @param _token2Amount Amount of the second token to swap
     */
    function swapToken2(UD60x18 _token2Amount) external returns (UD60x18 token1Amount) {
        // Calculate Token 1 Amount
        token1Amount = calculateToken2Swap(_token2Amount);

        // Do Swap
        token2.safeTransferFrom(msg.sender, address(this), _token2Amount.intoUint256());
        token2Balance = token2Balance.add(_token2Amount);
        token1Balance = token1Balance.sub(token1Amount);
        token1.safeTransfer(msg.sender, token1Amount.intoUint256());

        _updateCumulativePrices();

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

    function _updateCumulativePrices() internal {
        uint32 timeElapsed = uint32(block.timestamp) - lastBlockTimestamp;

        if (timeElapsed > 0) {
            // Calculate prices based on updated reserves
            UD60x18 price1 = token2Balance.div(token1Balance);
            UD60x18 price2 = token1Balance.div(token2Balance);

            // Update cumulative prices
            cumulativePrice1 = cumulativePrice1.add(price1.mul(ud(timeElapsed)));
            cumulativePrice2 = cumulativePrice2.add(price2.mul(ud(timeElapsed)));

            // Update the last block timestamp
            lastBlockTimestamp = uint32(block.timestamp);
        }
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
    ) external override returns (bool success) {
        require(token == address(token1) || token == address(token2), "Unsupported token");

        UD60x18 fee = ud(_flashFee(amount));
        UD60x18 balanceBefore = (token == address(token1) ? token1Balance : token2Balance);
        
        // Transfer tokens to receiver
        IERC20(token).safeTransfer(address(receiver), amount);
        require(
            receiver.onFlashLoan(msg.sender, token, amount, fee.intoUint256(), data) ==
            keccak256("ERC3156FlashBorrower.onFlashLoan"),
            "IERC3156: Callback failed"
        );

        // Check that the loan has been paid back plus fees
        UD60x18 balanceAfter = ud(IERC20(token).balanceOf(address(this)));
        require(balanceAfter.eq(balanceBefore.add(fee)), "Flash loan hasn't been paid back properly");

        // Update state variables
        token == address(token1) ? 
            token1Balance = token1Balance.add(fee) : 
            token2Balance = token2Balance.add(fee);
        K = token1Balance.mul(token2Balance);

        success = true;
    }

    /**
     * @dev The fee to be charged for a given loan.
     * @param token The loan currency.
     * @param amount The amount of tokens lent.
     * @return fee The amount of `token` to be charged for the loan, on top of the returned principal.
     */
    function flashFee(address token, uint256 amount) external view override returns (uint256 fee) {
        require(token == address(token1) || token == address(token2), "Unsupported token");
        fee = _flashFee(amount);
    }

    /**
     * @dev The fee to be charged for a given loan. Internal function with no checks.
     * @param amount The amount of tokens lent.
     * @return fee The amount of `token` to be charged for the loan, on top of the returned principal.
     */
    function _flashFee(uint256 amount) internal view returns (uint256 fee) {
        fee = (amount * feeRate.intoUint256()) / 10000;
    }

    /**
     * @dev The amount of currency available to be lended.
     * @param token The loan currency.
     * @return max The amount of `token` that can be borrowed.
     */
    function maxFlashLoan(address token) external view override returns (uint256 max) {
        if (token == address(token1)) {
            max = token1Balance.intoUint256();
        } else if (token == address(token2)) {
            max = token2Balance.intoUint256();
        } else {
            max = 0;
        }
    }
}
