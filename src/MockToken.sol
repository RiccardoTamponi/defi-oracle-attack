// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// ERC20 minimale usato per simulare ETH e sUSD
contract MockToken is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    // Chiunque può coniare token senza limiti
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
