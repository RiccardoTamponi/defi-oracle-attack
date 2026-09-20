// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {MockToken} from "../src/MockToken.sol";
import {SimpleAMM} from "../src/SimpleAMM.sol";
import {PriceOracleSpot} from "../src/PriceOracleSpot.sol";
import {VulnerableLending} from "../src/VulnerableLending.sol";

contract SweepTest is Test {
    string constant CSV = "analysis/sweep_results.csv";
    uint256 constant X = 1000e18;    // riserva ETH del pool (fissa)
    uint256 constant Y = 300_000e18; // riserva sUSD (prezzo iniziale costante)

    function test_Sweep() public {
        uint256[5] memory cfs = [uint256(500e15), 600e15, 667e15, 750e15, 900e15];
        uint256[8] memory ratios = [uint256(100), 250, 500, 667, 750, 1000, 1500, 2000]; // dx/X in permille

        vm.writeFile(CSV, "cf_wad,ratio_permille,dx_wei,borrowable_wei\n");

        for (uint256 i = 0; i < cfs.length; i++) {
            for (uint256 j = 0; j < ratios.length; j++) {
                (uint256 dx, uint256 borrowable) = _simulate(cfs[i], ratios[j]);
                vm.writeLine(CSV, string.concat(
                    vm.toString(cfs[i]), ",",
                    vm.toString(ratios[j]), ",",
                    vm.toString(dx), ",",
                    vm.toString(borrowable)
                ));
            }
        }
        console.log("Sweep completato ->", CSV);
    }

    function _simulate(uint256 cf, uint256 ratioPerMille)
        internal
        returns (uint256 dx, uint256 borrowable)
    {
        MockToken eth  = new MockToken("ETH", "ETH");
        MockToken susd = new MockToken("sUSD", "sUSD");
        SimpleAMM amm  = new SimpleAMM(eth, susd);
        PriceOracleSpot oracle = new PriceOracleSpot(amm);
        VulnerableLending lending = new VulnerableLending(susd, eth, oracle, cf);

        // pool iniziale
        eth.mint(address(this), X);
        susd.mint(address(this), Y);
        eth.approve(address(amm), X);
        susd.approve(address(amm), Y);
        amm.addLiquidity(X, Y);

        // pump
        dx = (X * ratioPerMille) / 1000;
        eth.mint(address(this), dx);
        eth.approve(address(amm), dx);
        uint256 susdOut = amm.swap(address(eth), dx);

        // deposito e lettura del massimo prestito
        susd.approve(address(lending), susdOut);
        lending.deposit(susdOut);
        borrowable = lending.maxBorrow(address(this));
    }
}

