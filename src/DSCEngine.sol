// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
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
// internal & private view & pure functions
// external & public view & pure functions

pragma solidity ^0.8.34;

import { OracleLib, AggregatorV3Interface } from "./libraries/OracleLib.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { DecentralizedStableCoin } from "./DecentralizedStableCoin.sol";

/**
 * @title DSCEngine
 * @author Patrick Collins
 * @notice Core engine for the Decentralized Stablecoin protocol
 * @dev Manages collateral deposits, DSC minting/burning, and liquidations
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of
 * all collateral < the $ backed value of all the DSC.
 */
contract DSCEngine is ReentrancyGuard {
    ///////////////////
    //     Errors    //
    ///////////////////

    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenNotAllowed(address token);
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__ZeroAddressNotAllowed();
    error DSCEngine__InvalidPrice();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();
    
    ///////////
    // Types //
    ///////////

    using OracleLib for AggregatorV3Interface;

    /////////////////////////
    //   State Variables   //
    /////////////////////////

    /// @dev Mapping from token address to its corresponding Chainlink price feed address
    mapping(address token => address priceFeed) private sPriceFeeds;
    
    /// @dev The DSC token contract (immutable for gas savings and security)
    DecentralizedStableCoin private immutable I_DSC;
    
    /// @dev Mapping from user address to token address to deposited amount
    mapping(address user => mapping(address token => uint256 amount)) private sCollateralDeposited;
    
    /// @dev Mapping from user address to amount of DSC minted
    mapping(address user => uint256 amountDscMinted) private sDscMinted;
    
    /// @dev Array of allowed collateral token addresses (for iteration)
    address[] private sCollateralTokens;

    /// @dev Precision constants
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // This means you need to be 200% over-collateralized
    uint256 private constant LIQUIDATION_BONUS = 10; // This means you get assets at a 10% discount when liquidating
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18; // CHANGED: private -> public for test access

    ////////////////
    //   Events   //
    ////////////////

    /**
     * @dev Emitted when a user deposits collateral
     * @param user The address of the user depositing collateral
     * @param token The address of the collateral token
     * @param amount The amount of collateral deposited
     */
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    
    /**
     * @dev Emitted when a user mints DSC
     * @param user The address of the user minting DSC
     * @param amount The amount of DSC minted
     */
    event DscMinted(address indexed user, uint256 indexed amount);

    /**
     * @dev Emitted when a user redeems collateral
     * @param redeemedFrom The address whose collateral is being redeemed
     * @param redeemedTo The address receiving the collateral
     * @param token The address of the collateral token
     * @param amount The amount of collateral redeemed
     * @notice If redeemedFrom != redeemedTo, then it was a liquidation
     */
    event CollateralRedeemed(address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount);

    ///////////////////
    //   Modifiers   //
    ///////////////////

    /**
     * @dev Reverts if the amount is zero
     * @param amount The amount to check
     */
    modifier moreThanZero(uint256 amount) {
        _moreThanZero(amount);
        _;
    }

    /**
     * @dev Reverts if the token is not allowed as collateral
     * @param token The token address to check
     */
    modifier isAllowedToken(address token) {
        _isAllowedToken(token);
        _;
    }

    /**
     * @dev Reverts if the address is zero
     * @param addr The address to check
     */
    modifier nonZeroAddress(address addr) {
        _nonZeroAddress(addr);
        _;
    }

    ///////////////////
    //   Functions   //
    ///////////////////

    /**
     * @notice Constructor to initialize the DSCEngine
     * @param tokenAddresses Array of allowed collateral token addresses
     * @param priceFeedAddresses Array of corresponding Chainlink price feed addresses
     * @param dscAddress Address of the DecentralizedStableCoin contract
     * @dev tokenAddresses and priceFeedAddresses must have the same length
     * @dev dscAddress must not be zero address
     * @custom:throws DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength if arrays length mismatch
     * @custom:throws DSCEngine__ZeroAddressNotAllowed if any address is zero
     */
    constructor(
        address[] memory tokenAddresses, 
        address[] memory priceFeedAddresses, 
        address dscAddress
    ) 
        nonZeroAddress(dscAddress)
    {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }

        uint256 length = tokenAddresses.length;
        for (uint256 i = 0; i < length; i++) {
            _nonZeroAddress(tokenAddresses[i]);
            _nonZeroAddress(priceFeedAddresses[i]);
            
            sPriceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            sCollateralTokens.push(tokenAddresses[i]);
        }
        
        I_DSC = DecentralizedStableCoin(dscAddress);
    }

    ///////////////////////////
    //   External Functions  //
    ///////////////////////////

    /**
     * @notice Allows a user to deposit collateral to back their DSC minting
     * @dev Follows Checks-Effects-Interactions pattern for security:
     *      1. Checks: validations via modifiers
     *      2. Effects: update sCollateralDeposited mapping
     *      3. Interactions: transfer tokens via try/catch
     * @param tokenCollateralAddress The address of the collateral token (must be in sCollateralTokens)
     * @param amountCollateral The amount of collateral to deposit (must be > 0)
     * @custom:requires User must have approved this contract to spend amountCollateral
     * @custom:emits CollateralDeposited with user address, token, and amount
     * @custom:throws DSCEngine__TransferFailed if token transfer fails (insufficient balance/allowance)
     * @custom:throws DSCEngine__TokenNotAllowed if token is not in allowed list
     * @custom:throws DSCEngine__NeedsMoreThanZero if amountCollateral is 0
     * @custom:security CEI pattern prevents reentrancy attacks
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        public
        nonReentrant
        moreThanZero(amountCollateral)
        nonZeroAddress(tokenCollateralAddress)
        isAllowedToken(tokenCollateralAddress)
    {
        sCollateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        
        // CHANGED: Added try/catch to handle any token transfer errors
        try IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral) returns (bool success) {
            if (!success) {
                revert DSCEngine__TransferFailed();
            }
        } catch {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @notice Mints DSC tokens to the caller, increasing their debt position
     * @dev The caller must have sufficient collateral to maintain health factor > MIN_HEALTH_FACTOR
     *      Health factor is checked AFTER updating sDscMinted (Checks-Effects-Interactions)
     * @param amountDscToMint The amount of DSC to mint (must be > 0)
     * @custom:requires User must have deposited collateral first
     * @custom:requires Post-mint health factor must be >= MIN_HEALTH_FACTOR
     * @custom:emits DscMinted with user address and amount
     * @custom:throws DSCEngine__NeedsMoreThanZero if amountDscToMint is 0
     * @custom:throws DSCEngine__BreaksHealthFactor(0) if minting would make position unsafe
     * @custom:throws DSCEngine__MintFailed if DSC contract mint fails (should not happen)
     * @custom:note This function updates sDscMinted BEFORE checking health factor (intentional)
     *         to prevent race conditions and follow CEI pattern
     */
    function mintDsc(
        uint256 amountDscToMint
    ) 
        public 
        nonReentrant
        moreThanZero(amountDscToMint) 
    {
        sDscMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        
        bool minted = I_DSC.mint(msg.sender, amountDscToMint);
        
        if (!minted) {
            sDscMinted[msg.sender] -= amountDscToMint;
            revert DSCEngine__MintFailed();
        }
        
        emit DscMinted(msg.sender, amountDscToMint);
    }

    /**
     * @notice Deposits collateral and mints DSC in a single transaction
     * @dev Combines depositCollateral and mintDsc for convenience and gas savings
     * @param tokenCollateralAddress The address of the collateral token to deposit
     * @param amountCollateral The amount of collateral to deposit
     * @param amountDscToMint The amount of DSC to mint
     * @custom:requires Both deposit and mint operations must succeed
     * @custom:emits CollateralDeposited and DscMinted events
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress, 
        uint256 amountCollateral, 
        uint256 amountDscToMint
    )
        external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }
 
    /**
     * @notice Redeems collateral back to the user
     * @dev Checks health factor after redemption to ensure position remains safe
     * @param tokenCollateralAddress The ERC20 token address of the collateral being redeemed
     * @param amountCollateral The amount of collateral to redeem
     * @custom:requires User must have sufficient collateral deposited
     * @custom:requires Post-redemption health factor must remain >= MIN_HEALTH_FACTOR
     * @custom:emits CollateralRedeemed with from=to=msg.sender
     * @custom:throws DSCEngine__NeedsMoreThanZero if amountCollateral is 0
     * @custom:throws DSCEngine__BreaksHealthFactor if redemption would make position unsafe
     */
    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) 
        public 
        moreThanZero(amountCollateral) 
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Burns DSC tokens to reduce debt position
     * @dev User must have approved this contract to spend their DSC
     * @param amount The amount of DSC to burn
     * @custom:requires User must have sufficient DSC balance and approval
     * @custom:emits Transfer and Burn events from DSC contract
     * @custom:throws DSCEngine__NeedsMoreThanZero if amount is 0
     * @custom:note Health factor improves after burning, so no need to check
     */
    function burnDsc(
        uint256 amount
    )
        external moreThanZero(amount) 
    {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); // I don't think this would ever hit...
    }

    /**
     * @notice Burns DSC and redeems collateral in one transaction
     * @dev Useful for users who want to exit their position completely
     * @param tokenCollateralAddress The collateral address to redeem
     * @param amountCollateral The amount of collateral to redeem
     * @param amountDscToBurn The amount of DSC to burn
     * @custom:requires User must have sufficient DSC and collateral
     * @custom:emits CollateralRedeemed, Transfer, and Burn events
     */
    function redeemCollateralForDsc(
        address tokenCollateralAddress, 
        uint256 amountCollateral, 
        uint256 amountDscToBurn
    )  
        external 
    {
        _burnDsc(amountDscToBurn, msg.sender, msg.sender);
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Liquidates an underwater position by allowing a liquidator to cover debt in exchange for discounted collateral
     * @dev Liquidator must have DSC to burn and will receive collateral with a 10% bonus
     * @param collateral The ERC20 token address of the collateral backing the underwater position
     * @param user The address of the underwater user being liquidated
     * @param debtToCover The amount of DSC debt to cover (can be partial)
     * 
     * @custom:mechanism 
     *   1. Calculate collateral equivalent of debtToCover using current oracle prices
     *   2. Add 10% liquidation bonus to collateral amount
     *   3. Redeem collateral from underwater user and send to liquidator
     *   4. Burn DSC from liquidator to cover user's debt
     *   5. Verify liquidator's health factor remains safe
     * 
     * @custom:requires User's health factor must be < MIN_HEALTH_FACTOR
     * @custom:requires Liquidator must have approved DSCEngine to spend debtToCover DSC
     * @custom:requires debtToCover must be > 0
     * 
     * @custom:emits CollateralRedeemed (from user to liquidator)
     * @custom:emits Transfer and Burn events from DSC contract
     * 
     * @custom:throws DSCEngine__HealthFactorOk if user's health factor is healthy
     * @custom:throws DSCEngine__NeedsMoreThanZero if debtToCover is 0
     * @custom:throws DSCEngine__TransferFailed if any token transfer fails
     * 
     * @custom:note Partial liquidations are supported - liquidator can cover only part of the debt
     * @custom:note The 10% bonus incentivizes liquidators to keep the protocol healthy
     * @custom:warning If protocol becomes undercollateralized (<100%), liquidations may fail
     * @custom:security Follows CEI pattern: checks first, then effects, then interactions
     */
    function liquidate(
        address collateral,
        address user, 
        uint256 debtToCover
    ) 
        external
        moreThanZero(debtToCover)
        nonReentrant 
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if(startingUserHealthFactor > MIN_HEALTH_FACTOR){
            revert DSCEngine__HealthFactorOk();
        }

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);

        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        uint256 totalCollateralRedeemed = tokenAmountFromDebtCovered + bonusCollateral;

        _redeemCollateral(collateral, totalCollateralRedeemed, user, msg.sender);

        _burnDsc(debtToCover, user, msg.sender);

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    ///////////////////////////////////////////
    //          Private Functions            //
    ///////////////////////////////////////////

    /**
     * @notice Internal function to redeem collateral and transfer it to a recipient
     * @dev Updates storage first (Checks-Effects) then performs token transfer (Interactions)
     * @param tokenCollateralAddress The address of the collateral token
     * @param amountCollateral The amount of collateral to redeem
     * @param from The user whose collateral is being redeemed
     * @param to The recipient of the collateral tokens
     * @custom:emits CollateralRedeemed with from, to, token, and amount
     * @custom:reverts DSCEngine__TransferFailed if token transfer fails
     * @custom:note This function does NOT check health factor - caller must do that
     */
    function _redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        address from,
        address to
    ) 
        private 
    {
        sCollateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if(!success){
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @notice Internal function to burn DSC tokens and update debt tracking
     * @dev Burns tokens on behalf of a user, transferring them from dscFrom to this contract first
     * @param amountDscToBurn The amount of DSC to burn
     * @param onBehalfOf The user whose debt is being reduced
     * @param dscFrom The address providing the DSC tokens to burn
     * @custom:reverts DSCEngine__TransferFailed if token transfer from dscFrom fails
     * @custom:note This function assumes dscFrom has approved this contract to spend their DSC
     * @custom:note This function does NOT check health factor - caller must do that
     */
    function _burnDsc(
        uint256 amountDscToBurn,
        address onBehalfOf,
        address dscFrom
    )
        private 
    {
        sDscMinted[onBehalfOf] -= amountDscToBurn;
        
        bool success = I_DSC.transferFrom(dscFrom, address(this), amountDscToBurn);
        if(!success){
            revert DSCEngine__TransferFailed();
        }
        
        I_DSC.burn(amountDscToBurn);
    }

    //////////////////////////////////////////////////
    //   Internal & Private View & Pure Functions   //
    //////////////////////////////////////////////////

    /**
     * @notice Internal function to validate that an amount is greater than zero
     * @dev Reverts with DSCEngine__NeedsMoreThanZero if amount is zero
     * @param amount The amount to validate
     */
    function _moreThanZero(
        uint256 amount
    )
        internal
        pure 
    {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
    }

    /**
     * @notice Internal function to validate that a token is allowed as collateral
     * @dev Checks if the token has an associated price feed
     * @param token The token address to validate
     * @custom:reverts DSCEngine__TokenNotAllowed if token has no price feed
     */
    function _isAllowedToken(
        address token
    ) 
        internal 
        view
    {
        if (sPriceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed(token);
        }
    }

    /**
     * @notice Internal function to validate that an address is not zero
     * @dev Reverts with DSCEngine__ZeroAddressNotAllowed if address is zero
     * @param addr The address to validate
     */
    function _nonZeroAddress(
        address addr
    ) 
        internal 
        pure {
        if (addr == address(0)) {
            revert DSCEngine__ZeroAddressNotAllowed();
        }
    }

    /**
     * @notice Fetches and validates the current price from Chainlink oracle for a given token
     * @dev Uses OracleLib to check for stale data; price must be positive
     * @param token The address of the collateral token to query
     * @return uintPrice The validated price as uint256 (Chainlink's 8 decimals)
     * @custom:throws DSCEngine__InvalidPrice if price <= 0
     * @custom:throws OracleLib__StalePrice if price data is stale
     * @custom:security Critical function - any failure here prevents dangerous liquidations/mints
     */
    function _getValidatedPrice(
        address token
    ) 
        private
        view 
        returns (uint256 uintPrice)
    {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(sPriceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
    
        if (price <= 0) {
            revert DSCEngine__InvalidPrice();
        }
    
        // Safe cast: price > 0 and Chainlink's 8-decimal price always fits in uint256
        // forge-lint: disable-next-line(unsafe-typecast)
        uintPrice = uint256(price);
    }

    /**
     * @notice Calculates the health factor for a given amount of DSC minted and collateral value
     * @dev Pure function for deterministic health factor calculation
     *      Formula: (collateralValueInUsd * LIQUIDATION_THRESHOLD / LIQUIDATION_PRECISION * PRECISION) / totalDscMinted
     * @param totalDscMinted The total amount of DSC minted
     * @param collateralValueInUsd The total collateral value in USD (18 decimals)
     * @return The calculated health factor (1e18 = 100%, <1e18 = liquidatable)
     * @custom:returns type(uint256).max if totalDscMinted is zero (no debt)
     */
    function _calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    )
        internal
        pure
        returns (uint256)
    {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    /**
     * @notice Calculates the current health factor for a user
     * @dev Calls _getAccountInformation and _calculateHealthFactor
     * @param user The address of the user
     * @return healthFactor The user's current health factor
     */
    function _healthFactor
    (
        address user
    )   private 
        view returns(uint256) 
    {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);

        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    /**
     * @notice Reverts if the user's health factor is below the minimum threshold
     * @dev Used as a safety check after state-changing operations
     * @param user The address of the user to check
     * @custom:reverts DSCEngine__BreaksHealthFactor with 0 if health factor is too low
     */
    function _revertIfHealthFactorIsBroken
    (
        address user
    )   internal 
        view 
    {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
                revert DSCEngine__BreaksHealthFactor(0);
        }
    }

    /**
     * @notice Gets comprehensive account information for a user
     * @dev Combines DSC minted and collateral value in one call
     * @param user The address of the user
     * @return totalDscMinted Total DSC minted by the user
     * @return collateralValueInUsd Total collateral value in USD (18 decimals)
     */
    function _getAccountInformation
    (
        address user
    ) 
        private 
        view 
        returns(uint256 totalDscMinted, uint256 collateralValueInUsd) 
    {
        totalDscMinted = sDscMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    //////////////////////////////////////////
    //   Public & External View Functions   //
    //////////////////////////////////////////

    /**
     * @notice Returns the total collateral value in USD for a user
     * @dev Iterates through all collateral tokens and sums their USD values
     * @param user The address of the user
     * @return totalCollateralValueInUsd Total collateral value in USD (18 decimals)
     */
    function getAccountCollateralValue
    (
        address user
    )   public 
        view 
        returns (uint256 totalCollateralValueInUsd) 
    {
        uint256 length = sCollateralTokens.length;
        for(uint256 i = 0; i < length; i++) {
            address token = sCollateralTokens[i];
            uint256 amount = sCollateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    /**
     * @notice Returns the token amount for a given USD amount at current prices
     * @dev Useful for calculating how much collateral corresponds to a debt amount
     *      Formula: (usdAmountInWei * PRECISION) / (price * ADDITIONAL_FEED_PRECISION)
     * @param token The address of the collateral token
     * @param usdAmountInWei The USD amount in wei (18 decimals)
     * @return The equivalent token amount (18 decimals)
     */
    function getTokenAmountFromUsd
    (
        address token, 
        uint256 usdAmountInWei
    )   public
        view 
        returns (uint256) 
    {
        uint256 uintPrice = _getValidatedPrice(token);
        return ((usdAmountInWei * PRECISION) / (uintPrice * ADDITIONAL_FEED_PRECISION));
    }

    /**
     * @notice Returns the USD value of a given amount of tokens at current prices
     * @dev Formula: (price * ADDITIONAL_FEED_PRECISION * amount) / PRECISION
     * @param token The address of the collateral token
     * @param amount The amount of tokens (18 decimals)
     * @return The USD value (18 decimals)
     */
    function getUsdValue
    (
        address token,
        uint256 amount
    ) 
        public 
        view
        returns(uint256)
    {
        uint256 uintPrice = _getValidatedPrice(token);
        return (uintPrice * ADDITIONAL_FEED_PRECISION * amount) / PRECISION;
    }

    /**
     * @notice Returns the amount of collateral deposited by a user for a specific token
     * @param user The address of the user
     * @param token The address of the collateral token
     * @return The amount of collateral deposited
     */
    function getCollateralBalanceOfUser
    (
        address user,
        address token
    ) 
        external
        view 
        returns (uint256)
    {
        return sCollateralDeposited[user][token];
    }

    /**
     * @notice Returns the amount of DSC minted by a user
     * @param user The address of the user
     * @return The amount of DSC minted
     */
    function getDscMinted
    (
        address user
    )   external 
        view 
        returns (uint256)
    {
        return sDscMinted[user];
    }

    /**
     * @notice Returns the price feed address for a given token
     * @param token The address of the token
     * @return The address of the Chainlink price feed
     */
    function getPriceFeed
    (   
        address token
    )   
        external
        view 
        returns (address)
    {
        return sPriceFeeds[token];
    }

    /**
     * @notice Returns the price feed address for a specific collateral token
     * @param token The address of the collateral token
     * @return The address of the Chainlink price feed
     */
    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return sPriceFeeds[token];
    }

    /**
     * @notice Returns the precision constant used for calculations
     * @return The precision value (1e18)
     */
    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    /**
     * @notice Returns the additional feed precision for Chainlink price adjustments
     * @return The additional feed precision value (1e10)
     */
    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    /**
     * @notice Returns the liquidation threshold percentage
     * @return The liquidation threshold (50 = 50%)
     */
    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    /**
     * @notice Returns the liquidation bonus percentage for liquidators
     * @return The liquidation bonus (10 = 10%)
     */
    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    /**
     * @notice Returns the liquidation precision constant
     * @return The liquidation precision (100)
     */
    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    /**
     * @notice Returns the minimum health factor required for solvent positions
     * @return The minimum health factor (1e18 = 100%)
     */
    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    /**
     * @notice Returns the array of allowed collateral tokens
     * @return Array of token addresses
     */
    function getCollateralTokens() 
        external 
        view 
        returns (address[] memory) 
    {
        return sCollateralTokens;
    }

    /**
     * @notice Returns the DSC token contract address
     * @return The address of the DSC token
     */
    function getDsc() external view returns (address) {
        return address(I_DSC);
    }

    /**
     * @notice Returns the health factor of a user
     * @param user The address of the user
     * @return The health factor (1e18 = 100%, <1e18 = liquidatable)
     */
    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }
}