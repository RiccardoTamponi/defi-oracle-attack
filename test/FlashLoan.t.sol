// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockToken} from "../src/MockToken.sol";
import {FlashLender} from "../src/FlashLender.sol";
import {IFlashBorrower} from "../src/IFlashBorrower.sol";

// Borrower onesto, ripaga subito quello che ha ricevuto
contract HonestBorrower is IFlashBorrower {
    FlashLender public lender;
    IERC20 public token;

    constructor(FlashLender _lender, IERC20 _token) {
        lender = _lender;
        token = _token;
    }

    // Innesca il flash loan (msg.sender verso il lender sarà questo contratto)
    function borrow(uint256 amount) external {
        lender.flashLoan(amount);
    }

    // Callback invocato dal lender mentre abbiamo i fondi in mano
    function executeOperation(uint256 amount) external override {
        token.transfer(address(lender), amount); // ripaga
    }
}

// Borrower disonesto, tiene i fondi e non ripaga
contract DishonestBorrower is IFlashBorrower {
    FlashLender public lender;

    constructor(FlashLender _lender) {
        lender = _lender;
    }

    function borrow(uint256 amount) external {
        lender.flashLoan(amount);
    }

    function executeOperation(uint256 amount) external override {
        // Non ripaga nulla
    }
}

contract FlashLoanTest is Test {
    MockToken eth;
    FlashLender lender;
    uint256 constant LIQUIDITY = 5000e18;

    function setUp() public {
        eth = new MockToken("Ether Mock", "ETH");
        lender = new FlashLender(eth);

        // Rifornisco il lender di liquidità da prestare
        eth.mint(address(this), LIQUIDITY);
        eth.approve(address(lender), LIQUIDITY);
        lender.fund(LIQUIDITY);
    }

    // Caso felice, il borrower ripaga -> il loan va a buon fine, lender integro
    function test_HonestBorrower_Repays() public {
        HonestBorrower borrower = new HonestBorrower(lender, eth);
        borrower.borrow(1000e18);
        assertEq(eth.balanceOf(address(lender)), LIQUIDITY, "Il lender deve tornare integro");
    }
    
    // Proprietà di sicurezza, se non ripaga, tutto reverte
    function test_DishonestBorrower_Reverts() public {
        DishonestBorrower borrower = new DishonestBorrower(lender);
        vm.expectRevert("prestito non ripagato");
        borrower.borrow(1000e18);
    }
}
