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
     */
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    
    /**
     * @dev Emitted when a user mints DSC
     */
    event DscMinted(address indexed user, uint256 indexed amount);

    /**
     * @dev Emitted when a user redeems collateral
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
     * @notice Allows a user to deposit collateral
     * @param tokenCollateralAddress The address of the collateral token (WETH or WBTC)
     * @param amountCollateral The amount of collateral to deposit
     * @dev Follows Checks-Effects-Interactions pattern for security
     * @dev Uses try/catch to handle any token transfer errors and convert them to DSCEngine__TransferFailed
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
     * @notice Mints DSC tokens to the caller
     * @param amountDscToMint The amount of DSC to mint
     * @dev The caller must have sufficient collateral to maintain health factor > MIN_HEALTH_FACTOR
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
     * @notice This function will deposit your collateral and mint DSC in one transaction
     * @param tokenCollateralAddress: the address of the token to deposit as collateral
     * @param amountCollateral: The amount of collateral to deposit
     * @param amountDscToMint: The amount of DecentralizedStableCoin to mint
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
 
     /*
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're redeeming
     * @param amountCollateral: The amount of collateral you're redeeming
     * @notice This function will redeem your collateral.
     * @notice If you have DSC minted, you will not be able to redeem until you burn your DSC
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


    /*
     * @notice careful! You'll burn your DSC here! Make sure you want to do this...
     * @dev you might want to use this if you're nervous you might get liquidated and want to just burn
     * your DSC but keep your collateral in.
     */
    function burnDsc(
        uint256 amount
    )
        external moreThanZero(amount) 
    {

        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); // I don't think this would ever hit...
    }

    /*
     * @param tokenCollateralAddress: the collateral address to redeem
     * @param amountCollateral: amount of collateral to redeem
     * @param amountDscToBurn: amount of DSC to burn
     * This function burns DSC and redeems underlying collateral in one transaction
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

    /*
     * @param collateral: The ERC20 token address of the collateral you're using to make the protocol solvent again.
     * This is collateral that you're going to take from the user who is insolvent.
     * In return, you have to burn your DSC to pay off their debt, but you don't pay off your own.
     * @param user: The user who is insolvent. They have to have a _healthFactor below MIN_HEALTH_FACTOR
     * @param debtToCover: The amount of DSC you want to burn to cover the user's debt.
     *
     * @notice: You can partially liquidate a user.
     * @notice: You will get a 10% LIQUIDATION_BONUS for taking the users funds.
    * @notice: This function working assumes that the protocol will be roughly 150% overcollateralized in order for this
    to work.
    * @notice: A known bug would be if the protocol was only 100% collateralized, we wouldn't be able to liquidate
    anyone.
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     */
    function liquidate(address collateral,
        address user, uint256 debtToCover
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

    function _burnDsc(
        uint256 amountDscToBurn,
        address onBehalfOf,
        address dscFrom
    )
        private 
        {
        sDscMinted[onBehalfOf] -= amountDscToBurn;
        bool success = I_DSC.transferFrom(dscFrom, address(this), amountDscToBurn);
        // This conditional is hypothetically unreachable
        if(!success){
            revert DSCEngine__TransferFailed();
        }
        I_DSC.burn(amountDscToBurn);
    }


    //////////////////////////////////////////////////
    //   Internal & Private View & Pure Functions   //
    //////////////////////////////////////////////////

    /**
     * @dev Internal function to validate amount is greater than zero
     * @param amount The amount to check
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
     * @dev Internal function to validate token is allowed as collateral
     * @param token The token address to check
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
     * @dev Internal function to validate address is not zero
     * @param addr The address to check
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
    * @dev Retrieves and validates the current price from Chainlink for a given token
    * @notice Fetches the latest price from the Chainlink oracle and performs safety checks
    * @dev Uses OracleLib's staleCheckLatestRoundData to ensure price data is fresh
    * @param token The address of the collateral token to get the price for
    * @return uintPrice The validated price as a uint256 (with Chainlink's original decimals, typically 8)
    * @custom:throws DSCEngine__InvalidPrice if the price is zero or negative
    * @custom:note This function assumes that after validation, casting int256 to uint256 is safe
    * @custom:security The staleCheck from OracleLib protects against stale price data
    * 
    * Requirements:
    * - The token must have an associated price feed (enforced by isAllowedToken modifier in calling functions)
    * - The price must be positive (>0)
    * - The price data must not be stale (handled by OracleLib)
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
     * @dev Returns how close to liquidation a user is
     * @param user The address of the user
     * @return healthFactor The health factor (1e18 = 100% = healthy, <1e18 = liquidatable)
     */
    function _healthFactor(address user) private view returns(uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        
        if (totalDscMinted == 0) return type(uint256).max;
        
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

// Removed misplaced health factor check block that caused undeclared identifier error.

    /**
     * @dev Gets account information for a user
     * @param user The address of the user
     * @return totalDscMinted Total DSC minted by the user
     * @return collateralValueInUsd Total collateral value in USD
     */
    function _getAccountInformation(
        address user
    ) 
        private 
        view 
        returns(uint256 totalDscMinted, uint256 collateralValueInUsd) 
    {
        totalDscMinted = sDscMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /**
     * @dev Reverts if the user's health factor is broken
     * @param user The address of the user
     */
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(0);
        }
    }

    

    //////////////////////////////////////////
    //   Public & External View Functions   //
    //////////////////////////////////////////

    /**
     * @notice Returns the total collateral value in USD for a user
     * @param user The address of the user
     * @return totalCollateralValueInUsd Total collateral value in USD (18 decimals)
     */
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        uint256 length = sCollateralTokens.length;
        for(uint256 i = 0; i < length; i++) {
            address token = sCollateralTokens[i];
            uint256 amount = sCollateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    /**
     * @notice Returns the token amount for a given USD amount
     * @param token The address of the token
     * @param usdAmountInWei The USD amount in wei (18 decimals)
     * @return The token amount (18 decimals)
     */
    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        uint256 uintPrice = _getValidatedPrice(token);
        return ((usdAmountInWei * PRECISION) / (uintPrice * ADDITIONAL_FEED_PRECISION));
    }

    /**
     * @notice Returns the USD value of a given amount of tokens
     * @param token The address of the token
     * @param amount The amount of tokens (18 decimals)
     * @return The USD value (18 decimals)
     * @dev Uses Chainlink price feeds with 8 decimals and adjusts to 18 decimals
     */
    function getUsdValue(address token, uint256 amount) public view returns(uint256) {
        uint256 uintPrice = _getValidatedPrice(token);
        return (uintPrice * ADDITIONAL_FEED_PRECISION * amount) / PRECISION;
    }

    /**
     * @notice Returns the amount of collateral deposited by a user for a specific token
     * @param user The address of the user
     * @param token The address of the collateral token
     * @return The amount of collateral deposited
     */
    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return sCollateralDeposited[user][token];
    }

    /**
     * @notice Returns the amount of DSC minted by a user
     * @param user The address of the user
     * @return The amount of DSC minted
     */
    function getDscMinted(address user) external view returns (uint256) {
        return sDscMinted[user];
    }

    /**
     * @notice Returns the price feed address for a given token
     * @param token The address of the token
     * @return The address of the Chainlink price feed
     */
    function getPriceFeed(address token) external view returns (address) {
        return sPriceFeeds[token];
    }

    /**
     * @notice Returns the DSC token contract address
     * @return The address of the DSC token
     */
    function getDsc() external view returns (address) {
        return address(I_DSC);
    }

    /**
     * @notice Returns the array of allowed collateral tokens
     * @return Array of token addresses
     */
    function getCollateralTokens() external view returns (address[] memory) {
        return sCollateralTokens;
    }

    /**
     * @notice Returns the health factor of a user
     * @param user The address of the user
     * @return The health factor (1e18 = 100%)
     */
    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }
}