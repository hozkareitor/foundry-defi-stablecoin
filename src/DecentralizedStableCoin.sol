// SPDX-License-Identifier: MIT
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
 * 
 * @custom:security Only the owner (DSCEngine) can mint and burn tokens
 * @custom:peg Maintains 1:1 peg with USD through over-collateralization
 */
contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    /////////////
    // Errors  //
    /////////////
    
    /**
     * @notice Thrown when someone tries to mint or burn zero tokens
     */
    error DecentralizedStableCoin__AmountMustBeGreaterThanZero();
    
    /**
     * @notice Thrown when someone tries to burn more tokens than they have
     */
    error DecentralizedStableCoin__BurnAmountExceedsBalance();
    
    /**
     * @notice Thrown when a zero address is provided where not allowed
     */
    error DecentralizedStableCoin__ZeroAddressNotAllowed();

    ////////////
    // Events //
    ////////////
    
    /**
     * @notice Emitted when new DSC tokens are minted
     * @param to The address receiving the minted tokens
     * @param amount The amount of tokens minted
     */
    event Mint(address indexed to, uint256 amount);
    
    /**
     * @notice Emitted when DSC tokens are burned
     * @param from The address burning their tokens
     * @param amount The amount of tokens burned
     */
    event Burn(address indexed from, uint256 amount);

    /////////////////
    // Constructor //
    /////////////////
    
    /**
     * @notice Initializes the token with name "DecentralizedStableCoin" and symbol "DSC"
     * @dev Sets the initial owner (should be DSCEngine) and validates it's not zero address
     * @param initialOwner The address that will have initial ownership (should be DSCEngine)
     * @custom:throws DecentralizedStableCoin__ZeroAddressNotAllowed if initialOwner is zero address
     */
    constructor(address initialOwner) 
        ERC20("DecentralizedStableCoin", "DSC") 
        Ownable(initialOwner) 
    {
        if (initialOwner == address(0)) {
            revert DecentralizedStableCoin__ZeroAddressNotAllowed();
        }
    }

    //////////////////////
    // Public Functions //
    //////////////////////

    /**
     * @notice Burns DSC tokens from the caller's balance
     * @dev Overrides ERC20Burnable.burn to add validation and events
     * @param _amount The amount of tokens to burn
     * @custom:throws DecentralizedStableCoin__AmountMustBeGreaterThanZero if amount is zero
     * @custom:throws DecentralizedStableCoin__BurnAmountExceedsBalance if caller has insufficient balance
     * @custom:emits Burn event with caller address and amount
     * @custom:access Only the owner (DSCEngine) can call this function
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

    ////////////////////////
    // External Functions //
    ////////////////////////

    /**
     * @notice Mints new DSC tokens to a specified address
     * @dev Only callable by the owner (DSCEngine) to maintain protocol stability
     * @param _to The address to receive the minted tokens
     * @param _amount The amount of tokens to mint
     * @return bool True if minting was successful
     * @custom:throws DecentralizedStableCoin__ZeroAddressNotAllowed if _to is zero address
     * @custom:throws DecentralizedStableCoin__AmountMustBeGreaterThanZero if _amount is zero
     * @custom:emits Mint event with recipient address and amount
     * @custom:access Only the owner (DSCEngine) can call this function
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