// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockToken} from "../src/MockToken.sol";
import {SimpleAMM} from "../src/SimpleAMM.sol";
import {PriceOracleSpot} from "../src/PriceOracleSpot.sol";
import {VulnerableLending} from "../src/VulnerableLending.sol";
import {FlashLender} from "../src/FlashLender.sol";
import {Attacker} from "../src/Attacker.sol";

contract AttackTest is Test {
    MockToken eth;
    MockToken susd;
    SimpleAMM amm;
    PriceOracleSpot oracle;
    VulnerableLending lending;
    FlashLender flashLender;
    Attacker attacker;

    uint256 constant INIT_ETH   = 1000e18;      // riserva ETH del pool (X)
    uint256 constant INIT_SUSD  = 300_000e18;   // riserva sUSD del pool
    uint256 constant CF         = 667e15;       // collateral factor 0.667 (WAD)
    uint256 constant FLASH_LIQ  = 1000e18;      // capitale del flash lender
    uint256 constant LEND_LIQ   = 2000e18;      // ETH prestabile dal lending
    uint256 constant FLASH_AMT  = 900e18;       // dx: pump col 90% del pool

    uint256 priceTrue; // prezzo "vero" di sUSD (ETH per 1 sUSD) PRE-attacco

    function setUp() public {
        eth  = new MockToken("Ether Mock", "ETH");
        susd = new MockToken("sUSD Mock", "sUSD");

        amm     = new SimpleAMM(eth, susd);
        oracle  = new PriceOracleSpot(amm);
        lending = new VulnerableLending(susd, eth, oracle, CF);
        flashLender = new FlashLender(eth);
        attacker = new Attacker(flashLender, amm, lending, eth, susd);

        // Liquidita' del pool AMM
        eth.mint(address(this), INIT_ETH);
        susd.mint(address(this), INIT_SUSD);
        eth.approve(address(amm), INIT_ETH);
        susd.approve(address(amm), INIT_SUSD);
        amm.addLiquidity(INIT_ETH, INIT_SUSD);

        // Capitale del flash lender
        eth.mint(address(this), FLASH_LIQ);
        eth.approve(address(flashLender), FLASH_LIQ);
        flashLender.fund(FLASH_LIQ);

        // Riserva ETH del lending
        eth.mint(address(this), LEND_LIQ);
        eth.approve(address(lending), LEND_LIQ);
        lending.fund(LEND_LIQ);

        // Prezzo VERO di sUSD prima di ogni manipolazione (riferimento per la perdita)
        priceTrue = amm.getSpotPrice(address(susd));
    }

    function test_Attack_IsProfitable_WithSpotOracle() public {
        // Fotografia PRIMA
        uint256 attackerEthBefore = eth.balanceOf(address(attacker)); // 0
        uint256 lendingEthBefore  = eth.balanceOf(address(lending));  // LEND_LIQ

        // --- ATTACCO ---
        attacker.attack(FLASH_AMT);

        // Fotografia DOPO
        uint256 attackerEthAfter = eth.balanceOf(address(attacker));
        uint256 lendingEthAfter  = eth.balanceOf(address(lending));
        uint256 collateralHeld   = susd.balanceOf(address(lending)); // sUSD abbandonato dall'attaccante

        // Contabilita'
        uint256 attackerProfit = attackerEthAfter - attackerEthBefore;
        uint256 ethLentOut     = lendingEthBefore - lendingEthAfter;
        uint256 trueCollValue  = (collateralHeld * priceTrue) / 1e18; // valore VERO del collaterale
        uint256 lendingLoss    = ethLentOut - trueCollValue;

        console.log("Profitto attaccante (ETH):", fmtEth(attackerProfit));
        console.log("ETH prestato dal lending  :", fmtEth(ethLentOut));
        console.log("Valore vero collaterale   :", fmtEth(trueCollValue));
        console.log("Perdita del lending (ETH) :", fmtEth(lendingLoss));

        // 1) L'attaccante ci guadagna
        assertGt(attackerProfit, 0, "l'attacco deve essere profittevole");
        // 2) Non gli resta sUSD in mano: ha depositato tutto come collaterale
        assertEq(susd.balanceOf(address(attacker)), 0, "nessun sUSD residuo");
        // 3) Il flash lender e' tornato integro
        assertEq(eth.balanceOf(address(flashLender)), FLASH_LIQ, "flash lender integro");
        // 4) La VITTIMA (il lending) perde: ha prestato piu' ETH del valore vero del collaterale
        assertGt(lendingLoss, 0, "il lending deve subire una perdita");
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


