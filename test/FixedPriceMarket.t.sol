// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {MockToken} from "../src/MockToken.sol";
import {FixedPriceMarket} from "../src/FixedPriceMarket.sol";

contract FixedPriceMarketTest is Test {
    MockToken eth;
    MockToken susd;
    FixedPriceMarket market;

    uint256 constant PRICE = 4e15;       // 0.004 ETH per 1 sUSD: prezzo "tondo", divisioni esatte
    uint256 constant STOCK = 10_000e18;  // scorta di sUSD in vendita

    function setUp() public {
        eth    = new MockToken("Ether Mock", "ETH");
        susd   = new MockToken("sUSD Mock", "sUSD");
        market = new FixedPriceMarket(eth, susd, PRICE);

        // Scorta del mercato: conio sUSD, li approvo e li deposito con fund
        susd.mint(address(this), STOCK);
        susd.approve(address(market), STOCK);
        market.fund(STOCK);
    }

    function test_Buy_AtFixedPrice() public {
        eth.mint(address(this), 20e18);
        eth.approve(address(market), 20e18);

        // Due acquisti uguali, uno dopo l'altro
        uint256 out1 = market.buy(10e18);
        uint256 out2 = market.buy(10e18);

        assertEq(out1, 2_500e18, "10 ETH / 0.004 = 2500 sUSD");
        assertEq(out2, out1, "il prezzo non peggiora: niente slippage");
        assertEq(susd.balanceOf(address(this)), 5_000e18, "sUSD ricevuti");
        assertEq(eth.balanceOf(address(market)), 20e18, "ETH incassati dal mercato");
    }

    function test_Buy_RevertsIfOutOfStock() public {
        // 50 ETH comprerebbero 12.500 sUSD, ma la scorta e' di soli 10.000
        eth.mint(address(this), 50e18);
        eth.approve(address(market), 50e18);

        vm.expectRevert(bytes("scorte insufficienti"));
        market.buy(50e18);
    }
}

