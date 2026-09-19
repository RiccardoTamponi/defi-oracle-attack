// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MockToken} from "../src/MockToken.sol";
import {SimpleAMM} from "../src/SimpleAMM.sol";
import {PriceOracleTWAP} from "../src/PriceOracleTWAP.sol";
import {VulnerableLending} from "../src/VulnerableLending.sol";
import {FlashLender} from "../src/FlashLender.sol";
import {Attacker} from "../src/Attacker.sol";

contract AttackTWAPTest is Test {
    MockToken eth;
    MockToken susd;
    SimpleAMM amm;
    PriceOracleTWAP oracle;
    VulnerableLending lending;
    FlashLender flashLender;
    Attacker attacker;

    uint256 constant INIT_ETH  = 1000e18;
    uint256 constant INIT_SUSD = 300_000e18;
    uint256 constant CF        = 667e15;
    uint256 constant FLASH_LIQ = 1000e18;
    uint256 constant LEND_LIQ  = 2000e18;
    uint256 constant FLASH_AMT = 900e18;

    uint256 priceTrue;

    function setUp() public {
        eth  = new MockToken("Ether Mock", "ETH");
        susd = new MockToken("sUSD Mock", "sUSD");
        amm  = new SimpleAMM(eth, susd);

        // Liquidita' del pool (prima dell'oracolo, cosi' lo snapshot parte da un pool vero)
        eth.mint(address(this), INIT_ETH);
        susd.mint(address(this), INIT_SUSD);
        eth.approve(address(amm), INIT_ETH);
        susd.approve(address(amm), INIT_SUSD);
        amm.addLiquidity(INIT_ETH, INIT_SUSD);

        oracle      = new PriceOracleTWAP(amm);
        lending     = new VulnerableLending(susd, eth, oracle, CF);
        flashLender = new FlashLender(eth);
        attacker    = new Attacker(flashLender, amm, lending, eth, susd);

        eth.mint(address(this), FLASH_LIQ);
        eth.approve(address(flashLender), FLASH_LIQ);
        flashLender.fund(FLASH_LIQ);

        eth.mint(address(this), LEND_LIQ);
        eth.approve(address(lending), LEND_LIQ);
        lending.fund(LEND_LIQ);

        priceTrue = amm.getSpotPrice(address(susd));

        // Storia del pool: passa 1 ora a prezzo onesto, un keeper aggiorna l'oracolo,
        // poi passa un blocco (12 s) prima che arrivi l'attaccante
        vm.warp(block.timestamp + 1 hours);
        oracle.update();
        vm.warp(block.timestamp + 12);

    }

    function test_TWAP_IgnoresInstantaneousPump() public {
        // Pump da 900 ETH, fatto direttamente da noi (nessun lending coinvolto)
        eth.mint(address(this), FLASH_AMT);
        eth.approve(address(amm), FLASH_AMT);
        amm.swap(address(eth), FLASH_AMT);

        uint256 spot = amm.getSpotPrice(address(susd));
        uint256 twap = oracle.getPrice(address(susd));

        console.log("Prezzo vero (ETH per 1000 sUSD):", fmtEth(priceTrue * 1000));
        console.log("Prezzo spot (ETH per 1000 sUSD):", fmtEth(spot * 1000));
        console.log("Prezzo TWAP (ETH per 1000 sUSD):", fmtEth(twap * 1000));

        assertGt(spot, priceTrue, "il pump deve alzare il prezzo spot");
        assertEq(twap, priceTrue, "il TWAP deve restare al prezzo vero");
    }

    function test_Attack_Fails_WithTWAP() public {
        // L'attaccante non riesce a ripagare il flash loan: il suo transfer finale va in errore
        vm.expectPartialRevert(IERC20Errors.ERC20InsufficientBalance.selector);
        attacker.attack(FLASH_AMT);

        // Il revert annulla tutto: nessuno ha perso nulla
        assertEq(eth.balanceOf(address(lending)), LEND_LIQ, "lending intatto");
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


