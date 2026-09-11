// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SimpleAMM {
    IERC20 public immutable tokenETH;
    IERC20 public immutable tokenSUSD;
    uint256 public reserveETH;
    uint256 public reserveSUSD;

    constructor(IERC20 _tokenETH, IERC20 _tokenSUSD) {
        tokenETH = _tokenETH;
        tokenSUSD = _tokenSUSD;
    }

    function addLiquidity(uint256 amountETH, uint256 amountSUSD) external {
        require(amountETH > 0 && amountSUSD > 0, "Invalid amounts");
        tokenETH.transferFrom(msg.sender, address(this), amountETH);
        tokenSUSD.transferFrom(msg.sender, address(this), amountSUSD);
        reserveETH += amountETH;
        reserveSUSD += amountSUSD;
    }

    function swap(address tokenIn, uint256 amountIn) external returns (uint256 amountOut) {
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
}