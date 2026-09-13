// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// Astrazione dell'oracolo di prezzo: il lending dipende da questa, non dall'AMM.
// Cosi' possiamo iniettare la versione vulnerabile (spot) o quella mitigata (TWAP)
// senza cambiare il lending.
interface IPriceOracle {
    // Prezzo di `token` espresso in ETH, scalato 1e18
    function getPrice(address token) external view returns (uint256);
}
