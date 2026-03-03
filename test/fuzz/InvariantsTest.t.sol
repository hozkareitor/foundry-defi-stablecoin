// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { Test } from "forge-std/Test.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { HelperConfig } from "../../script/HelperConfig.s.sol";
import { DeployDSC } from "../../script/DeployDSC.s.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { Handler } from "./Handler.t.sol";  // ← Cambiado de DSCEngineHandler a Handler
import { console } from "forge-std/console.sol";

contract InvariantsTest is StdInvariant, Test {
    DSCEngine public dsce;
    DecentralizedStableCoin public dsc;
    HelperConfig public helperConfig;
    Handler public handler;  // ← Cambiado de DSCEngineHandler a Handler

    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public weth;
    address public wbtc;

    function setUp() external {
        DeployDSC deployer = new DeployDSC();
        (dsc, dsce, helperConfig) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = helperConfig.activeNetworkConfig();
        
        handler = new Handler(dsce, dsc, false);
        targetContract(address(handler));
    }

    /////////////////////////////
    // Invariant Tests         //
    /////////////////////////////

    function invariant_protocolMustBeOvercollateralized() public view {
        uint256 totalSupply = dsc.totalSupply();
        if (totalSupply == 0) return;
        
        uint256 totalCollateralValue = _getTotalCollateralValue();
        
        console.log("Total Collateral Value: $", totalCollateralValue / 1e18);
        console.log("Total DSC Supply: $", totalSupply / 1e18);
        console.log("Collateralization Ratio: %", (totalCollateralValue * 100) / totalSupply);
        
        assertGe(totalCollateralValue, totalSupply);
    }

    function invariant_gettersDontRevert() public view {
        dsce.getAdditionalFeedPrecision();
        dsce.getCollateralTokens();
        dsce.getLiquidationBonus();
        dsce.getLiquidationThreshold();
        dsce.getMinHealthFactor();
        dsce.getPrecision();
        dsce.getDsc();
        dsce.getCollateralTokenPriceFeed(weth);
        dsce.getCollateralTokenPriceFeed(wbtc);
    }

    function invariant_oraclePricesArePositive() public view {
        assertGt(dsce.getUsdValue(weth, 1e18), 0);
        assertGt(dsce.getUsdValue(wbtc, 1e18), 0);
    }

    /////////////////////////////
    // Helper Functions        //
    /////////////////////////////

    function _getTotalCollateralValue() internal view returns (uint256) {
        uint256 wethBalance = ERC20Mock(weth).balanceOf(address(dsce));
        uint256 wbtcBalance = ERC20Mock(wbtc).balanceOf(address(dsce));
        
        uint256 wethValue = dsce.getUsdValue(weth, wethBalance);
        uint256 wbtcValue = dsce.getUsdValue(wbtc, wbtcBalance);
        
        return wethValue + wbtcValue;
    }
}