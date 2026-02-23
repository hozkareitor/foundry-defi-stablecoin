// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volatility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.34;

import { ERC20Burnable, ERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title DecentralizedStableCoin
 * @author Patrick Collins
 * @notice Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized stablecoin
 * @dev This contract is meant to be owned by DSCEngine. It is an ERC20 token that can be minted
 * and burned only by the DSCEngine smart contract.
 * 
 * Collateral: Exogenous (ETH & BTC)
 * Minting (Stability Mechanism): Decentralized (Algorithmic)
 * Value (Relative Stability): Anchored (Pegged to USD)
 * Collateral Type: Crypto
 */
contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    /////////////
    // Errors  //
    /////////////
    error DecentralizedStableCoin__AmountMustBeGreaterThanZero();
    error DecentralizedStableCoin__BurnAmountExceedsBalance();
    error DecentralizedStableCoin__ZeroAddressNotAllowed();

    ////////////
    // Events //
    ////////////
    event Mint(address indexed to, uint256 amount);
    event Burn(address indexed from, uint256 amount);

    ///////////////
    // Constructor/
    ///////////////
    /**
     * @dev Initializes the token with name "DecentralizedStableCoin" and symbol "DSC"
     * @param initialOwner The address that will have initial ownership (should be DSCEngine)
     */
    constructor(address initialOwner) 
        ERC20("DecentralizedStableCoin", "DSC") 
        Ownable(initialOwner) 
    {
        // Validate initial owner is not zero address
        if (initialOwner == address(0)) {
            revert DecentralizedStableCoin__ZeroAddressNotAllowed();
        }
    }

    ////////////////////
    // Public Functions/
    ////////////////////

    /**
     * @dev Burns `_amount` tokens from the caller's balance
     * @param _amount The amount of tokens to burn
     * @notice Only the owner (DSCEngine) can call this function
     * @notice Emits a {Burn} event
     */
    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        
        if (_amount == 0) {
            revert DecentralizedStableCoin__AmountMustBeGreaterThanZero();
        }
        if (balance < _amount) {
            revert DecentralizedStableCoin__BurnAmountExceedsBalance();
        }
        
        super.burn(_amount);
        emit Burn(msg.sender, _amount);
    }

    /////////////////////
    // External Functions/
    /////////////////////

    /**
     * @dev Mints `_amount` tokens to `_to` address
     * @param _to The address to receive the minted tokens
     * @param _amount The amount of tokens to mint
     * @return bool True if minting was successful
     * @notice Only the owner (DSCEngine) can call this function
     * @notice Emits a {Mint} event
     */
    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStableCoin__ZeroAddressNotAllowed();
        }
        if (_amount == 0) {
            revert DecentralizedStableCoin__AmountMustBeGreaterThanZero();
        }
        
        _mint(_to, _amount);
        emit Mint(_to, _amount);
        return true;
    }
}