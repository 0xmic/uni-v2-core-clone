// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";

contract FlashBorrower is IERC3156FlashBorrower {
    using SafeERC20 for IERC20;

    IERC3156FlashLender public lender;
    address public owner;

    constructor(IERC3156FlashLender _lender) {
        lender = _lender;
        owner = msg.sender;
    }

    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32) {
        // Ensure that the flash loan is coming from the expected lender
        require(msg.sender == address(lender), "Untrusted lender");

        // TODO: Additional here, e.g. arbitrage, collateral swap, etc.

        // Repay the flash loan
        uint256 repaymentAmount = amount + fee;
        IERC20(token).safeTransfer(address(lender), repaymentAmount);

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    function executeFlashLoan(address token, uint256 amount, bytes calldata data) public {
        require(msg.sender == owner, "Not owner");
        lender.flashLoan(this, token, amount, data);
    }
}
