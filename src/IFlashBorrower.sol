// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// Contratto che riceve un flash loan: deve implementare la logica da eseguire
// mentre ha i fondi in mano, e ripagare entro la fine della chiamata.
interface IFlashBorrower {
    function executeOperation(uint256 amount) external;
}