// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { DeployDSC } from "../../script/DeployDSC.s.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { HelperConfig } from "../../script/HelperConfig.s.sol";
import { ERC20Mock } from "../../test/mocks/ERC20Mock.sol";
import { Test, Vm } from "forge-std/Test.sol";
import { MockV3Aggregator } from "../mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event DscMinted(address indexed user, uint256 amount);

    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address weth;
    address wbtc;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;

    address public user = makeAddr("user");
    address public liquidator = makeAddr("liquidator");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant AMOUNT_TO_MINT = 100 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 100 ether;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, ) = config.activeNetworkConfig();

        // Mint tokens to users for testing
        ERC20Mock(weth).mint(user, STARTING_ERC20_BALANCE);
        ERC20Mock(wbtc).mint(user, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).mint(liquidator, STARTING_ERC20_BALANCE);
        ERC20Mock(wbtc).mint(liquidator, STARTING_ERC20_BALANCE);
    }

    /////////////////////////////
    // Constructor Tests       //
    /////////////////////////////

    function test_RevertWhen_TokenArraysLengthMismatch() public {
        address[] memory tokenAddresses = new address[](1);
        address[] memory feedAddresses = new address[](2);
        
        tokenAddresses[0] = weth;
        feedAddresses[0] = ethUsdPriceFeed;
        feedAddresses[1] = btcUsdPriceFeed;

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, feedAddresses, address(dsc));
    }

    function test_RevertWhen_ZeroAddressInConstructor() public {
        address[] memory tokenAddresses = new address[](1);
        address[] memory feedAddresses = new address[](1);
        
        tokenAddresses[0] = weth;
        feedAddresses[0] = ethUsdPriceFeed;
        
        // Test zero address for dsc
        vm.expectRevert(DSCEngine.DSCEngine__ZeroAddressNotAllowed.selector);
        new DSCEngine(tokenAddresses, feedAddresses, address(0));
    }

    function test_RevertWhen_TokenAddressIsZero() public {
        address[] memory tokenAddresses = new address[](1);
        address[] memory feedAddresses = new address[](1);
        
        tokenAddresses[0] = address(0);
        feedAddresses[0] = ethUsdPriceFeed;
        
        vm.expectRevert(DSCEngine.DSCEngine__ZeroAddressNotAllowed.selector);
        new DSCEngine(tokenAddresses, feedAddresses, address(dsc));
    }

    function test_RevertWhen_PriceFeedAddressIsZero() public {
        address[] memory tokenAddresses = new address[](1);
        address[] memory feedAddresses = new address[](1);
        
        tokenAddresses[0] = weth;
        feedAddresses[0] = address(0);
        
        vm.expectRevert(DSCEngine.DSCEngine__ZeroAddressNotAllowed.selector);
        new DSCEngine(tokenAddresses, feedAddresses, address(dsc));
    }

    function test_ConstructorSetsCorrectMappings() public view {

        // Verify that the price feeds are configured correctly
        assertEq(dsce.getPriceFeed(weth), ethUsdPriceFeed);
        assertEq(dsce.getPriceFeed(wbtc), btcUsdPriceFeed);

        // Verify that the tokens were added to the array
        address[] memory collateralTokens = dsce.getCollateralTokens();
        assertEq(collateralTokens.length, 2);
        assertEq(collateralTokens[0], weth);
        assertEq(collateralTokens[1], wbtc);
    }

    /////////////////////////////
    // Price Feed Tests        //
    /////////////////////////////

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18; // 15 * 2000 * 1e18
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetUsdValueWbtc() public view {
        uint256 btcAmount = 1e18;
        uint256 expectedUsd = 60000e18; // 1 * 60000 * 1e18
        uint256 actualUsd = dsce.getUsdValue(wbtc, btcAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function test_GetTokenAmountFromUsd() public view {
        // $100 de WETH @ $2000/WETH = 0.05 WETH
        uint256 expectedWeth = 0.05 ether;
        uint256 amountWeth = dsce.getTokenAmountFromUsd(weth, 100 ether);
        assertEq(amountWeth, expectedWeth);
        
        // $100 de WBTC @ $60,000/WBTC = 0.001666... WBTC
        uint256 expectedWbtc = 0.001666666666666666 ether;
        uint256 amountWbtc = dsce.getTokenAmountFromUsd(wbtc, 100 ether);
        assertEq(amountWbtc, expectedWbtc);
    }

    function test_GetPrecision() public view {
        assertEq(dsce.getPrecision(), 1e18);
    }

    function test_GetAdditionalFeedPrecision() public view {
        assertEq(dsce.getAdditionalFeedPrecision(), 1e10);
    }

    function test_GetLiquidationThreshold() public view {
        assertEq(dsce.getLiquidationThreshold(), 50);
    }

    function test_GetLiquidationBonus() public view {
        assertEq(dsce.getLiquidationBonus(), 10);
    }

    function test_GetLiquidationPrecision() public view {
        assertEq(dsce.getLiquidationPrecision(), 100);
    }

    function test_GetMinHealthFactor() public view {
        assertEq(dsce.getMinHealthFactor(), MIN_HEALTH_FACTOR);
    }

    function test_GetCollateralTokenPriceFeed() public view {
        assertEq(dsce.getCollateralTokenPriceFeed(weth), ethUsdPriceFeed);
        assertEq(dsce.getCollateralTokenPriceFeed(wbtc), btcUsdPriceFeed);
    }

    /////////////////////////////
    // depositCollateral Tests //
    /////////////////////////////

    function test_RevertWhen_CollateralAmountIsZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function test_RevertWhen_TokenNotAllowed() public {
        address notAllowedToken = makeAddr("fakeToken");
        
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__TokenNotAllowed.selector, notAllowedToken));
        dsce.depositCollateral(notAllowedToken, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function test_RevertWhen_TransferFails() public {
        vm.startPrank(user);
        
        // Do the approval (this emits Approval event)
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        
        // Burn all user tokens
        uint256 userBalance = ERC20Mock(weth).balanceOf(user);
        ERC20Mock(weth).burn(user, userBalance);
        
        // Now it should fail with our mistake
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        
        vm.stopPrank();
    }

    function test_SuccessWhen_DepositingCollateral() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        
        uint256 initialBalance = ERC20Mock(weth).balanceOf(user);
        uint256 initialContractBalance = ERC20Mock(weth).balanceOf(address(dsce));
        
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        
        uint256 finalBalance = ERC20Mock(weth).balanceOf(user);
        uint256 finalContractBalance = ERC20Mock(weth).balanceOf(address(dsce));
        
        assertEq(finalBalance, initialBalance - AMOUNT_COLLATERAL);
        assertEq(finalContractBalance, initialContractBalance + AMOUNT_COLLATERAL);
        assertEq(dsce.getCollateralBalanceOfUser(user, weth), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function test_SuccessWhen_DepositingMultipleTokens() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        ERC20Mock(wbtc).approve(address(dsce), AMOUNT_COLLATERAL);
        
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        dsce.depositCollateral(wbtc, AMOUNT_COLLATERAL);
        
        assertEq(dsce.getCollateralBalanceOfUser(user, weth), AMOUNT_COLLATERAL);
        assertEq(dsce.getCollateralBalanceOfUser(user, wbtc), AMOUNT_COLLATERAL);
        
        uint256 totalCollateralValue = dsce.getAccountCollateralValue(user);
        uint256 expectedValue = dsce.getUsdValue(weth, AMOUNT_COLLATERAL) + 
                               dsce.getUsdValue(wbtc, AMOUNT_COLLATERAL);
        assertEq(totalCollateralValue, expectedValue);
        vm.stopPrank();
    }

    function test_RevertWhen_DepositWithNoApprove() public {
        vm.startPrank(user);
        // We do not approve any tokens, so the transfer should fail
        
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function test_RevertWhen_DepositMoreThanBalance() public {
        vm.startPrank(user);
        uint256 userBalance = ERC20Mock(weth).balanceOf(user);
        uint256 excessAmount = userBalance + 1 ether;
        
        ERC20Mock(weth).approve(address(dsce), excessAmount);
        
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        dsce.depositCollateral(weth, excessAmount);
        vm.stopPrank();
    }

    function test_RevertWhen_DepositWithWrongToken() public {
        // Create a token that is not on the whitelist
        ERC20Mock fakeToken = new ERC20Mock("FAKE", "FAKE", user, 1000 ether);
        
        vm.startPrank(user);
        fakeToken.approve(address(dsce), AMOUNT_COLLATERAL);
        
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__TokenNotAllowed.selector, address(fakeToken)));
        dsce.depositCollateral(address(fakeToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function test_DepositCollateralEmitsEvent() public {
        vm.startPrank(user);
        
        // Do the approval (this emits Approval event)
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        
        // Set the event expectation for the deposit
        vm.expectEmit(true, true, true, true, address(dsce));
        emit CollateralDeposited(user, weth, AMOUNT_COLLATERAL);
        
        // This will emit the actual CollateralDeposited event
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function test_DepositCollateralUpdatesUserBalance() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        
        uint256 balanceBefore = dsce.getCollateralBalanceOfUser(user, weth);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        uint256 balanceAfter = dsce.getCollateralBalanceOfUser(user, weth);
        
        assertEq(balanceAfter, balanceBefore + AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function test_DepositCollateralUpdatesContractBalance() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        
        uint256 contractBalanceBefore = ERC20Mock(weth).balanceOf(address(dsce));
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        uint256 contractBalanceAfter = ERC20Mock(weth).balanceOf(address(dsce));
        
        assertEq(contractBalanceAfter, contractBalanceBefore + AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function test_DepositCollateralWithMaxUint256() public {
        vm.startPrank(user);
        uint256 maxAmount = type(uint256).max;
        
        // Approve maximum
        ERC20Mock(weth).approve(address(dsce), maxAmount);
        
        // Deposit a reasonable amount (we cannot deposit the maximum amount because we do not have the funds)
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        dsce.depositCollateral(weth, maxAmount);
        vm.stopPrank();
    }

    function test_MultipleDepositsSameToken() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL * 3);
        
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        
        uint256 totalDeposited = dsce.getCollateralBalanceOfUser(user, weth);
        assertEq(totalDeposited, AMOUNT_COLLATERAL * 3);
        vm.stopPrank();
    }

    function test_DepositCollateralDoesntAffectOtherUsers() public {
        // User 1 deposits
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        
        // User 2 (liquidator) deposits
        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        
        // Verify that the balance sheets are independent
        assertEq(dsce.getCollateralBalanceOfUser(user, weth), AMOUNT_COLLATERAL);
        assertEq(dsce.getCollateralBalanceOfUser(liquidator, weth), AMOUNT_COLLATERAL);
    }

    /////////////////////////////
    // mintDsc Tests           //
    /////////////////////////////

    function test_RevertWhen_MintingZeroDsc() public {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.mintDsc(0);
        vm.stopPrank();
    }

    function test_RevertWhen_MintingBreaksHealthFactor() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        
        // Try to mint more DSC than collateral allows
        uint256 collateralValue = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);
        uint256 maxSafeMint = (collateralValue * LIQUIDATION_THRESHOLD) / 100; // 50% of collateral value
        
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, 0));
        dsce.mintDsc(maxSafeMint + 1 ether);
        vm.stopPrank();
    }

    function test_SuccessWhen_MintingDsc() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        
        uint256 collateralValue = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);
        uint256 mintAmount = (collateralValue * LIQUIDATION_THRESHOLD) / 200; // 25% of collateral value (safe)
        
        uint256 initialDscBalance = dsc.balanceOf(user);
        
        dsce.mintDsc(mintAmount);
        
        assertEq(dsc.balanceOf(user), initialDscBalance + mintAmount);
        assertEq(dsce.getDscMinted(user), mintAmount);
        
        uint256 healthFactor = dsce.getHealthFactor(user);
        assertGe(healthFactor, MIN_HEALTH_FACTOR);
        vm.stopPrank();
    }

    /////////////////////////////
    // Deposit and Mint Tests //
    /////////////////////////////

    function test_RevertWhen_MintedDscBreaksHealthFactor() public {
        // Calculate unsafe mint amount (more than 50% of collateral value)
        uint256 collateralValue = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);
        uint256 unsafeMintAmount = (collateralValue * LIQUIDATION_THRESHOLD) / 100 + 1 ether; // >50%
        
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, 0));
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, unsafeMintAmount);
        vm.stopPrank();
    }

    function test_CanDepositAndMint() public {
        uint256 mintAmount = 50 ether; // Safe amount
        
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        
        uint256 initialDscBalance = dsc.balanceOf(user);
        uint256 initialCollateral = dsce.getCollateralBalanceOfUser(user, weth);
        
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, mintAmount);
        
        uint256 finalDscBalance = dsc.balanceOf(user);
        uint256 finalCollateral = dsce.getCollateralBalanceOfUser(user, weth);
        
        assertEq(finalDscBalance, initialDscBalance + mintAmount, "DSC mint amount incorrect");
        assertEq(finalCollateral, initialCollateral + AMOUNT_COLLATERAL, "Collateral deposit amount incorrect");
        
        uint256 healthFactor = dsce.getHealthFactor(user);
        assertGe(healthFactor, MIN_HEALTH_FACTOR, "Health factor should be safe");
        vm.stopPrank();
    }

    function test_RevertWhen_DepositAmountIsZero() public {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateralAndMintDsc(weth, 0, 50 ether);
        vm.stopPrank();
    }

    function test_RevertWhen_MintAmountIsZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, 0);
        vm.stopPrank();
    }

    /////////////////////////////
    // Health Factor Tests     //
    /////////////////////////////

    function test_GetHealthFactor() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        
        uint256 collateralValue = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);
        uint256 mintAmount = (collateralValue * LIQUIDATION_THRESHOLD) / 200; // 25%
        dsce.mintDsc(mintAmount);
        
        uint256 healthFactor = dsce.getHealthFactor(user);
        // Health factor should be > 1e18 (100%)
        assertGe(healthFactor, MIN_HEALTH_FACTOR);
        
        // Calculate expected health factor
        uint256 collateralAdjusted = (collateralValue * LIQUIDATION_THRESHOLD) / 100;
        uint256 expectedHealthFactor = (collateralAdjusted * 1e18) / mintAmount;
        assertEq(healthFactor, expectedHealthFactor);
        vm.stopPrank();
    }

    function test_HealthFactorMaxWhenNoDscMinted() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        
        uint256 healthFactor = dsce.getHealthFactor(user);
        assertEq(healthFactor, type(uint256).max);
        vm.stopPrank();
    }

    function test_HealthFactorWithMultipleCollateral() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        ERC20Mock(wbtc).approve(address(dsce), AMOUNT_COLLATERAL / 2);
        
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        dsce.depositCollateral(wbtc, AMOUNT_COLLATERAL / 2);
        
        uint256 totalValue = dsce.getAccountCollateralValue(user);
        uint256 mintAmount = totalValue / 4; // 25% del colateral
        dsce.mintDsc(mintAmount);
        
        uint256 healthFactor = dsce.getHealthFactor(user);
        uint256 expectedHealthFactor = (totalValue * 50 / 100) * 1e18 / mintAmount;
        assertEq(healthFactor, expectedHealthFactor);
        
        vm.stopPrank();
    }

    ////////////////////////////
    // Price Feed Error Tests //
    ////////////////////////////
  
    function test_RevertWhen_PriceIsZero() public {
        MockV3Aggregator(ethUsdPriceFeed).updatePrice(0);
        
        vm.expectRevert(DSCEngine.DSCEngine__InvalidPrice.selector);
        dsce.getUsdValue(weth, 1 ether);
    }

    function test_RevertWhen_PriceIsNegative() public {
        MockV3Aggregator(ethUsdPriceFeed).updatePrice(-100e8);
        
        vm.expectRevert(DSCEngine.DSCEngine__InvalidPrice.selector);
        dsce.getUsdValue(weth, 1 ether);
    }

    /////////////////////////////
    // Redeem Collateral Tests //
    /////////////////////////////

    function test_RevertWhen_RedeemMoreThanDeposited() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        
        //Trying to redeem more than deposited
        vm.expectRevert(); // Wait underflow/error 
        dsce.redeemCollateral(weth, AMOUNT_COLLATERAL + 1 ether);
        vm.stopPrank();
    }

    function test_RevertWhen_RedeemWithDebt() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        
        // Attempting to redeem while in debt
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, 0));
        dsce.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    ////////////////////
    // Burn DSC Tests //
    ////////////////////
    
    function test_BurnDscSuccess() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        
        uint256 minted = dsce.getDscMinted(user);
        dsc.approve(address(dsce), minted);
        
        dsce.burnDsc(minted);
        
        assertEq(dsce.getDscMinted(user), 0);
        assertEq(dsc.balanceOf(user), 0);
        vm.stopPrank();
    }

    //////////////////////////
    // Redeem For DSC Tests //
    //////////////////////////
    
    function test_RedeemCollateralForDscSuccess() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        
        uint256 minted = dsce.getDscMinted(user);
        dsc.approve(address(dsce), minted);
        
        uint256 collateralBefore = dsce.getCollateralBalanceOfUser(user, weth);
        dsce.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL, minted);
        
        assertEq(dsce.getCollateralBalanceOfUser(user, weth), 0);
        assertEq(dsce.getDscMinted(user), 0);
        vm.stopPrank();
    }

    ////////////////////////////
    // Liquidation Edge Cases //
    ////////////////////////////
    
    function test_RevertWhen_LiquidateWithNoDebt() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL); // Sin mintear DSC
        vm.stopPrank();
        
        vm.prank(liquidator);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dsce.liquidate(weth, user, AMOUNT_TO_MINT);
    }

    function test_RevertWhen_LiquidateWithZeroDebt() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();
        
        // Lower the price to make it liquidable
        MockV3Aggregator(ethUsdPriceFeed).updatePrice(18e8);
        
        vm.prank(liquidator);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.liquidate(weth, user, 0);
    }

    //////////////////////////////
    // View Function Edge Cases //
    //////////////////////////////
    
    function test_GetAccountInformationWithNoDeposits() public view {
    uint256 minted = dsce.getDscMinted(user);
    uint256 collateralValue = dsce.getAccountCollateralValue(user);
    
    assertEq(minted, 0);
    assertEq(collateralValue, 0);
    }

    function test_GetTokenAmountFromUsdWithZero() public view {
        uint256 amount = dsce.getTokenAmountFromUsd(weth, 0);
        assertEq(amount, 0);
    }

    ////////////////////////////////
    // Multiple Tokens Operations //
    ////////////////////////////////
    
    function test_DepositMultipleTokensAndMint() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        ERC20Mock(wbtc).approve(address(dsce), AMOUNT_COLLATERAL / 2);
        
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        dsce.depositCollateral(wbtc, AMOUNT_COLLATERAL / 2);
        
        // Calculate total value in USD
        uint256 wethValue = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);
        uint256 wbtcValue = dsce.getUsdValue(wbtc, AMOUNT_COLLATERAL / 2);
        uint256 totalValue = wethValue + wbtcValue;
        
        // Mint 25% of the total value in DSC
        uint256 mintAmount = totalValue / 4;
        dsce.mintDsc(mintAmount);
        
        assertEq(dsce.getCollateralBalanceOfUser(user, weth), AMOUNT_COLLATERAL);
        assertEq(dsce.getCollateralBalanceOfUser(user, wbtc), AMOUNT_COLLATERAL / 2);
        assertEq(dsce.getDscMinted(user), mintAmount);
        
        vm.stopPrank();
    }

    /////////////////////////////
    // Getter Functions Tests  //
    /////////////////////////////

    function test_GetCollateralTokens() public view {
        address[] memory tokens = dsce.getCollateralTokens();
        assertEq(tokens.length, 2);
        assertEq(tokens[0], weth);
        assertEq(tokens[1], wbtc);
    }

    function test_GetPriceFeed() public view {
        assertEq(dsce.getPriceFeed(weth), ethUsdPriceFeed);
        assertEq(dsce.getPriceFeed(wbtc), btcUsdPriceFeed);
    }

    function test_GetDsc() public view {
        assertEq(dsce.getDsc(), address(dsc));
    }

    function test_GetCollateralBalanceOfUser() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        
        assertEq(dsce.getCollateralBalanceOfUser(user, weth), AMOUNT_COLLATERAL);
        assertEq(dsce.getCollateralBalanceOfUser(user, wbtc), 0);
        vm.stopPrank();
    }

    function test_GetAccountCollateralValue() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        ERC20Mock(wbtc).approve(address(dsce), AMOUNT_COLLATERAL / 2); // Deposit half amount of WBTC
        
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        dsce.depositCollateral(wbtc, AMOUNT_COLLATERAL / 2);
        
        uint256 wethValue = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);
        uint256 wbtcValue = dsce.getUsdValue(wbtc, AMOUNT_COLLATERAL / 2);
        uint256 expectedTotal = wethValue + wbtcValue;
        
        assertEq(dsce.getAccountCollateralValue(user), expectedTotal);
        vm.stopPrank();
    }
}