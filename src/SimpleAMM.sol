// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SimpleAMM {
    IERC20 public immutable tokenETH;
    IERC20 public immutable tokenSUSD;
    uint256 public reserveETH;
    uint256 public reserveSUSD;
    // --- Accumulatore per il TWAP (stile Uniswap V2) ---
    uint256 public priceCumulativeSusd; // somma di prezzo(sUSD in ETH) * Δt
    uint256 public lastCumulativeTs;    // timestamp dell'ultimo aggiornamento


    constructor(IERC20 _tokenETH, IERC20 _tokenSUSD) {
        tokenETH = _tokenETH;
        tokenSUSD = _tokenSUSD;
        lastCumulativeTs = block.timestamp;

    }

    // Accumula il prezzo in vigore finora, pesato sul tempo trascorso.
    // Va chiamata PRIMA di modificare le riserve.
    function _accrue() internal {
        uint256 timeElapsed = block.timestamp - lastCumulativeTs;
        if (timeElapsed > 0 && reserveSUSD > 0) {
            uint256 priceSusd = (reserveETH * 1e18) / reserveSUSD; // ETH per 1 sUSD
            priceCumulativeSusd += priceSusd * timeElapsed;
        }
        lastCumulativeTs = block.timestamp;
    }


    function addLiquidity(uint256 amountETH, uint256 amountSUSD) external {
        _accrue();
        require(amountETH > 0 && amountSUSD > 0, "Invalid amounts");
        tokenETH.transferFrom(msg.sender, address(this), amountETH);
        tokenSUSD.transferFrom(msg.sender, address(this), amountSUSD);
        reserveETH += amountETH;
        reserveSUSD += amountSUSD;
    }

    function swap(address tokenIn, uint256 amountIn) external returns (uint256 amountOut) {
        _accrue();
        require(amountIn > 0, "Invalid amount");
        require(tokenIn == address(tokenETH) || tokenIn == address(tokenSUSD), "Invalid token");

        bool ethIn = (tokenIn == address(tokenETH));
        (uint256 reserveIn, uint256 reserveOut) = ethIn ? (reserveETH, reserveSUSD) : (reserveSUSD, reserveETH);

        // x*y = k nessuna fee: quanto esce a fronte di amountIn che entra
        amountOut = (amountIn * reserveOut ) / (reserveIn + amountIn);

        // Aggiorna le riserve prima di trasferire (pattern checks-effects-interactions)
        if (ethIn) {
            reserveETH += amountIn;
            reserveSUSD -= amountOut;
        } else {
            reserveSUSD += amountIn;
            reserveETH -= amountOut;
        }

        // Movimenti di token
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        (ethIn ? tokenSUSD : tokenETH).transfer(msg.sender, amountOut);

    }

    function getSpotPrice(address token) external view returns (uint256) {
        if (token == address(tokenETH)) {
            return (reserveSUSD * 1e18) / reserveETH; // sUSD per 1 ETH
        } else if (token == address(tokenSUSD)) {
            return (reserveETH * 1e18) / reserveSUSD; // ETH per 1 sUSD
        }
        revert("Invalid token");
    }

        // Aggiorna l'accumulatore senza fare trade
    function sync() external {
        _accrue();
    }

    // Cumulato "portato a ora", incluso il tempo dall'ultimo _accrue (come Uniswap V2)
    function currentCumulativeSusd() public view returns (uint256 cu, uint256 ts) {
        ts = block.timestamp;
        cu = priceCumulativeSusd;
        uint256 timeElapsed = ts - lastCumulativeTs;
        if (timeElapsed > 0 && reserveSUSD > 0) {
            uint256 priceSusd = (reserveETH * 1e18) / reserveSUSD;
            cu += priceSusd * timeElapsed;
        }
    }

}