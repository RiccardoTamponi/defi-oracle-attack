// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPriceOracle} from "./IPriceOracle.sol";

contract VulnerableLending {
    IERC20 public immutable collateralToken; // sUSD (collaterale)
    IERC20 public immutable borrowToken; // sETH (prestito)
    IPriceOracle public immutable oracle; // sorgente di prezzo iniettata
    uint256 public immutable collateralFactor; // WAD: 667e15 = 0.667

    uint256 constant WAD = 1e18;

    mapping(address => uint256) public collateralOf; // sUSD depositato per utente
    mapping(address => uint256) public debtOf;        // ETH preso in prestito per utente

    constructor(
        IERC20 _collateralToken,
        IERC20 _borrowToken,
        IPriceOracle _oracle,
        uint256 _collateralFactor
    ) {
        collateralToken = _collateralToken;
        borrowToken = _borrowToken;
        oracle = _oracle;
        collateralFactor = _collateralFactor;
    }

    // Rifornisce la riserva di ETH prestabile
    function fund(uint256 amount) external {
        borrowToken.transferFrom(msg.sender, address(this), amount);
    }

    // Deposita sUSD come collaterale
    function deposit(uint256 amountCollateral) external {
        collateralToken.transferFrom(msg.sender, address(this), amountCollateral);
        collateralOf[msg.sender] += amountCollateral;
    }

    // Valore del collaterale dell'utente, espresso in ETH, SECONDO L'ORACOLO
    function collateralValueInEth(address user) public view returns (uint256) {
        uint256 price = oracle.getPrice(address(collateralToken)); // ETH per 1 sUSD, WAD
        return (collateralOf[user] * price) / WAD;
    }

    // Massimo ETH prestabile = valore collaterale * collateral factor
    function maxBorrow(address user) public view returns (uint256) {
        return (collateralValueInEth(user) * collateralFactor) / WAD;
    }

    function borrow(uint256 amountToBorrow) external {
        require(
            debtOf[msg.sender] + amountToBorrow <= maxBorrow(msg.sender),
            "oltre il limite di prestito"
        );
        debtOf[msg.sender] += amountToBorrow; // effect prima...
        borrowToken.transfer(msg.sender, amountToBorrow); // ...poi interaction
    }
}