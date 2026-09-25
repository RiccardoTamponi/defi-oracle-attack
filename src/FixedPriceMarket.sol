// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Mercato a prezzo FISSO (il "Synthetix" dell'attacco del 18 febbraio):
// vende sUSD in cambio di ETH al prezzo giusto. L'oracolo NON lo legge,
// quindi il pump sull'AMM non ne sposta il prezzo.
contract FixedPriceMarket {
    IERC20 public immutable tokenETH;
    IERC20 public immutable tokenSUSD;
    uint256 public immutable priceSusd; // ETH per 1 sUSD, WAD (stessa unita' di getPrice)

    constructor(IERC20 _tokenETH, IERC20 _tokenSUSD, uint256 _priceSusd) {
        require(_priceSusd > 0, "prezzo nullo");
        tokenETH = _tokenETH;
        tokenSUSD = _tokenSUSD;
        priceSusd = _priceSusd;
    }

    // Rifornisce il mercato di sUSD da vendere (scorta finita, come maxY nel paper)
    function fund(uint256 amountSusd) external {
        tokenSUSD.transferFrom(msg.sender, address(this), amountSusd);
    }

    // Compra sUSD pagando in ETH al prezzo FISSO: quanti sUSD = ETH / prezzo
    function buy(uint256 ethIn) external returns (uint256 susdOut) {
        require(ethIn > 0, "importo nullo");
        susdOut = (ethIn * 1e18) / priceSusd;
        require(susdOut <= tokenSUSD.balanceOf(address(this)), "scorte insufficienti");

        tokenETH.transferFrom(msg.sender, address(this), ethIn);
        tokenSUSD.transfer(msg.sender, susdOut);
    }
}
