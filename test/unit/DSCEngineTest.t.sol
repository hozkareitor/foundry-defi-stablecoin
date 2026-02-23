// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { DeployDSC } from "../../script/DeployDSC.s.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { HelperConfig } from "../../script/HelperConfig.s.sol";
import { ERC20Mock } from "../../test/mocks/ERC20Mock.sol";
import { Test} from "forge-std/Test.sol";

contract DSCEngineTest is Test {
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
        address[] memory priceFeedAddresses = new address[](2);
        
        tokenAddresses[0] = weth;
        priceFeedAddresses[0] = ethUsdPriceFeed;
        priceFeedAddresses[1] = btcUsdPriceFeed;
        
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    function test_RevertWhen_ZeroAddressInConstructor() public {
        address[] memory tokenAddresses = new address[](1);
        address[] memory priceFeedAddresses = new address[](1);
        
        tokenAddresses[0] = address(0);
        priceFeedAddresses[0] = ethUsdPriceFeed;
        
        vm.expectRevert(DSCEngine.DSCEngine__ZeroAddressNotAllowed.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
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

    function testGetUsdValueWbtc() public view{
        uint256 btcAmount = 1e18;
        uint256 expectedUsd = 60000e18; // 1 * 60000 * 1e18
        uint256 actualUsd = dsce.getUsdValue(wbtc, btcAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function test_RevertWhen_PriceFeedReturnsInvalidPrice() public {
        // This would require mocking a price feed that returns 0 or negative
        // For now, we'll test the revert condition in a fork test
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
    
    // ESCENARIO 1: Sin approval (probado arriba)
    // El token revierte con InsufficientAllowance
    
    // ESCENARIO 2: Con approval pero sin fondos
    // Primero dar approval
    ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
    
    // Quemar todos los tokens del usuario
    uint256 userBalance = ERC20Mock(weth).balanceOf(user);
    ERC20Mock(weth).burn(user, userBalance);
    
    // Ahora sí debería fallar con nuestro error
    vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
    dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
    
    vm.stopPrank();
}

    //function test_RevertWhen_TransferFails() public {
        // User doesn't have enough tokens
        //vm.startPrank(user);
        //ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        
        // Burn user's tokens so transfer will fail
        //ERC20Mock(weth).burn(user, ERC20Mock(weth).balanceOf(user));
        
        //vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        //dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        //vm.stopPrank();
    //}

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