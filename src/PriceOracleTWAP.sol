// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IPriceOracle} from "./IPriceOracle.sol";
import {SimpleAMM} from "./SimpleAMM.sol";

// Oracolo MITIGATO: restituisce il prezzo medio pesato sul tempo (TWAP)
// dall'ultimo snapshot a oggi, invece del prezzo spot istantaneo.
contract PriceOracleTWAP is IPriceOracle {
    SimpleAMM public immutable amm;
    uint256 public snapCumulative; // valore dell'accumulatore allo snapshot
    uint256 public snapTimestamp;  // momento dello snapshot

    constructor(SimpleAMM _amm) {
        amm = _amm;
        (snapCumulative, snapTimestamp) = _amm.currentCumulativeSusd();
    }

    // Nuovo snapshot: da qui in poi la media parte da adesso
    function update() external {
        (snapCumulative, snapTimestamp) = amm.currentCumulativeSusd();
    }

    function getPrice(address token) external view override returns (uint256) {
        require(token == address(amm.tokenSUSD()), "solo sUSD");

        (uint256 cumNow, uint256 tsNow) = amm.currentCumulativeSusd();
        uint256 elapsed = tsNow - snapTimestamp;
        require(elapsed > 0, "finestra TWAP vuota");

        return (cumNow - snapCumulative) / elapsed;
    }
}


