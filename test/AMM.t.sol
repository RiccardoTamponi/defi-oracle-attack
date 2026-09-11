// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {MockToken} from "../src/MockToken.sol";
import {SimpleAMM} from "../src/SimpleAMM.sol";

contract AMMTest is Test {
    MockToken eth;
    MockToken susd;
    SimpleAMM amm;

    uint256 constant INIT_ETH = 1000e18; // riserva ETH iniziale
    uint256 constant INIT_SUSD = 300_000e18; // riserva sUSD iniziale

    function setUp() public {
        eth = new MockToken("Ether Mock", "ETH");
        susd = new MockToken("sUSD Mock", "sUSD");
        amm = new SimpleAMM(eth, susd);

        // Il contratto di test conia per sè la liquidità iniziale
        eth.mint(address(this), INIT_ETH);
        susd.mint(address(this), INIT_SUSD);

        // autorizza l'AMM a prelevarla e la deposita nel pool
        eth.approve(address(amm), INIT_ETH);
        susd.approve(address(amm), INIT_SUSD);
        amm.addLiquidity(INIT_ETH, INIT_SUSD);
    }

    function test_SwapEthIn_RaisesSusdPrice() public {
        // Fotografia PRIMA
        uint256 priceSusdBefore = amm.getSpotPrice(address(susd)); // ETH per 1 sUSD
        uint256 priceEthBefore = amm.getSpotPrice(address(eth)); // sUSD per 1 ETH
        uint256 kBefore = amm.reserveETH() * amm.reserveSUSD();

        // L'attaccante immette 100 ETH nel pool (il "pump")
        uint256 amountIn = 100e18;
        eth.mint(address(this), amountIn);
        eth.approve(address(amm), amountIn);
        uint256 out = amm.swap(address(eth), amountIn);

        // Fotografia DOPO
        uint256 priceSusdAfter = amm.getSpotPrice(address(susd));
        uint256 priceEthAfter = amm.getSpotPrice(address(eth));
        uint256 kAfter = amm.reserveETH() * amm.reserveSUSD();

        // 1) Ho ricevuto sUSD in cambio
        assertGt(out, 0, "Lo swap deve restituire sUSD");
        // 2) Il collaterale sUSD si è APPREZZATO (cuore del pump)
        assertGt(priceSusdAfter, priceSusdBefore, "Il prezzo sUSD deve salire");
        // 3) Specularmente, ETH vale meno sUSD
        assertLt(priceEthAfter, priceEthBefore, "Il prezzo ETH deve scendere");
        // 4) Invariante x*y=k: senza fee il prodotto non cala mai (troncamento a nostro favore)
        assertGe(kAfter, kBefore, "il prodotto delle riserve non deve diminuire");
    }
}