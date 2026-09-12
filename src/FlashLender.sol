// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IFlashBorrower} from "./IFlashBorrower.sol";

contract FlashLender {
    IERC20 public immutable token; // ETH mock: il token che presta

    constructor (IERC20 _token) {
        token = _token;
    }

    // Chiunque può rifornire il lender di liquidità da prestare
    function fund(uint256 amount) external {
        token.transferFrom(msg.sender, address(this), amount);
    }

    function flashLoan(uint256 amount) external {
        uint256 balanceBefore = token.balanceOf(address(this));
        require(amount <= balanceBefore, "liquidita' insufficiente");

        // 1. Presta: manda i fondi al borrower (chi ha chiamato)
        token.transfer(msg.sender, amount);

        // 2. Il borrower esegue la sua logica (pump -> borrow -> repay)
        IFlashBorrower(msg.sender).executeOperation(amount);

        // 3. Check before/after: se non è stato ripagato, REVERTE tutto
        uint256 balanceAfter = token.balanceOf(address(this));
        require(balanceAfter >= balanceBefore, "prestito non ripagato");
    }
}