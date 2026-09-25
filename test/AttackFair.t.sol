// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MockToken} from "../src/MockToken.sol";
import {SimpleAMM} from "../src/SimpleAMM.sol";
import {PriceOracleSpot} from "../src/PriceOracleSpot.sol";
import {PriceOracleTWAP} from "../src/PriceOracleTWAP.sol";
import {VulnerableLending} from "../src/VulnerableLending.sol";
import {FlashLender} from "../src/FlashLender.sol";
import {FixedPriceMarket} from "../src/FixedPriceMarket.sol";
import {Attacker} from "../src/Attacker.sol";
import {AttackerFair} from "../src/AttackerFair.sol";

contract AttackFairTest is Test {
    MockToken eth;
    MockToken susd;
    SimpleAMM amm;
    PriceOracleSpot oracle;
    VulnerableLending lending;
    FlashLender flashLender;
    FixedPriceMarket market;
    Attacker attacker;
    AttackerFair attackerFair;

    uint256 constant INIT_ETH     = 1000e18;      // riserva ETH del pool (X)
    uint256 constant INIT_SUSD    = 300_000e18;   // riserva sUSD del pool
    uint256 constant CF           = 667e15;       // collateral factor 0.667
    uint256 constant FLASH_LIQ    = 2000e18;      // basta per 900 + 1000
    uint256 constant LEND_LIQ     = 5000e18;      // il prestito arriva a ~3550 ETH
    uint256 constant MARKET_STOCK = 1_000_000e18; // sUSD in vendita a prezzo giusto

    uint256 constant PUMP     = 900e18;  // dx/X = 0.9
    uint256 constant PUMP_LOW = 300e18;  // dx/X = 0.3, sotto la soglia 0.499 del §6
    uint256 constant FAIR     = 1000e18; // ETH spesi a prezzo giusto

    uint256 priceTrue; // prezzo vero di sUSD (ETH per 1 sUSD) prima dell'attacco

    function setUp() public {
        eth  = new MockToken("Ether Mock", "ETH");
        susd = new MockToken("sUSD Mock", "sUSD");
        amm  = new SimpleAMM(eth, susd);

        // Liquidita' del pool
        eth.mint(address(this), INIT_ETH);
        susd.mint(address(this), INIT_SUSD);
        eth.approve(address(amm), INIT_ETH);
        susd.approve(address(amm), INIT_SUSD);
        amm.addLiquidity(INIT_ETH, INIT_SUSD);

        // Il mercato fisso vende al prezzo vero del pool PRIMA dell'attacco
        priceTrue = amm.getSpotPrice(address(susd));
        market = new FixedPriceMarket(eth, susd, priceTrue);
        susd.mint(address(this), MARKET_STOCK);
        susd.approve(address(market), MARKET_STOCK);
        market.fund(MARKET_STOCK);

        oracle       = new PriceOracleSpot(amm);
        lending      = new VulnerableLending(susd, eth, oracle, CF);
        flashLender  = new FlashLender(eth);
        attacker     = new Attacker(flashLender, amm, lending, eth, susd);
        attackerFair = new AttackerFair(flashLender, amm, market, lending, eth, susd);

        eth.mint(address(this), FLASH_LIQ);
        eth.approve(address(flashLender), FLASH_LIQ);
        flashLender.fund(FLASH_LIQ);

        eth.mint(address(this), LEND_LIQ);
        eth.approve(address(lending), LEND_LIQ);
        lending.fund(LEND_LIQ);
    }

        function test_FairLeg_MultipliesProfit() public {
        // Fotografo lo stato, eseguo l'attacco di SOLO pump, poi torno alla fotografia
        uint256 snap = vm.snapshotState();
        attacker.attack(PUMP);
        uint256 profitPumpOnly = eth.balanceOf(address(attacker));
        vm.revertToState(snap);

        // Stesso pump, piu' 1000 ETH spesi a prezzo giusto
        attackerFair.attack(PUMP, FAIR);
        uint256 profitFair = eth.balanceOf(address(attackerFair));

        console.log("Profitto solo pump 900        (ETH):", fmtEth(profitPumpOnly));
        console.log("Profitto pump 900 + giusto 1000 (ETH):", fmtEth(profitFair));

        assertGt(profitFair, profitPumpOnly, "il prezzo giusto deve moltiplicare il profitto");
        assertEq(eth.balanceOf(address(flashLender)), FLASH_LIQ, "flash lender integro");
    }

    function test_FairLeg_ProfitableBelowThreshold() public {
        // Col solo pump da 300 (dx/X = 0.3) l'attacco non rende: il rimborso fallisce
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientBalance.selector);
        attacker.attack(PUMP_LOW);

        // Lo stesso pump, con 1000 ETH a prezzo giusto, diventa profittevole
        attackerFair.attack(PUMP_LOW, FAIR);
        uint256 profit = eth.balanceOf(address(attackerFair));

        console.log("Profitto pump 300 + giusto 1000 (ETH):", fmtEth(profit));
        assertGt(profit, 0, "sotto la soglia del 6, col prezzo giusto l'attacco rende");
    }

        function test_FairLeg_BlockedByTWAP() public {
        // Un secondo lending, identico ma con l'oracolo TWAP
        PriceOracleTWAP twap = new PriceOracleTWAP(amm);
        VulnerableLending lendingTwap = new VulnerableLending(susd, eth, twap, CF);
        AttackerFair attackerTwap = new AttackerFair(flashLender, amm, market, lendingTwap, eth, susd);

        eth.mint(address(this), LEND_LIQ);
        eth.approve(address(lendingTwap), LEND_LIQ);
        lendingTwap.fund(LEND_LIQ);

        // Stessa storia di AttackTWAP.t.sol: 1 ora onesta, aggiornamento, poi un blocco
        vm.warp(block.timestamp + 1 hours);
        twap.update();
        vm.warp(block.timestamp + 12);

        // Il TWAP valuta TUTTO il collaterale al prezzo vero: il prestito non basta a ripagare
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientBalance.selector);
        attackerTwap.attack(PUMP, FAIR);

        assertEq(eth.balanceOf(address(lendingTwap)), LEND_LIQ, "lending intatto");
        assertEq(eth.balanceOf(address(flashLender)), FLASH_LIQ, "flash lender intatto");
    }

    function fmtEth(uint256 weiAmount) internal pure returns (string memory) {
        uint256 whole = weiAmount / 1e18;
        uint256 frac2 = (weiAmount % 1e18) / 1e16; // primi 2 decimali
        return string.concat(
            vm.toString(whole),
            ".",
            frac2 < 10 ? "0" : "",   // padding: 240.05, non 240.5
            vm.toString(frac2)
        );
    }
}


