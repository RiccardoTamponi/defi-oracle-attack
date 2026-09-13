// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IPriceOracle} from "./IPriceOracle.sol";
import {SimpleAMM} from "./SimpleAMM.sol";

// Oracolo vulnerabile: legge il prezzo SPOT direttamente dall'AMM, in tempo reale.
// Chiunque muova le riserve del pool (un pump) sposta all'istante questo prezzo.
contract PriceOracleSpot is IPriceOracle {
    SimpleAMM public immutable amm;

    constructor(SimpleAMM _amm) {
        amm = _amm;
    }

    function getPrice(address token) external view override returns (uint256) {
        return amm.getSpotPrice(token);
    }
}
