// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title ERC20Mock
 * @notice Mock ERC20 token for testing
 * @dev Used in local Anvil environment to simulate WETH and WBTC
 */
contract ERC20Mock is ERC20 {
    constructor(
        string memory name,
        string memory symbol,
        address initialAccount,
        uint256 initialBalance
    ) ERC20(name, symbol) {
        _mint(initialAccount, initialBalance);
    }
    
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    
    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}