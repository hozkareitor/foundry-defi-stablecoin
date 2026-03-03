// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { Test } from "forge-std/Test.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { MockV3Aggregator } from "../mocks/MockV3Aggregator.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { StdUtils } from "forge-std/StdUtils.sol";
import { console } from "forge-std/console.sol";

contract Handler is StdUtils, Test {
    using EnumerableSet for EnumerableSet.AddressSet;

    DSCEngine public dscEngine;
    DecentralizedStableCoin public dsc;
    ERC20Mock public weth;
    ERC20Mock public wbtc;
    MockV3Aggregator public ethUsdPriceFeed;
    MockV3Aggregator public btcUsdPriceFeed;

    uint256 public ghostTotalCollateralDeposited;
    uint256 public ghostTotalDscMinted;
    uint256 public ghostLiquidations;
    
    EnumerableSet.AddressSet private actors;
    uint256 public constant MAX_ACTORS = 5;
    uint256 public constant MAX_DEPOSIT_SIZE = 1_000_000e18;

    bool public continueOnRevert;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc, bool _continueOnRevert) {
        dscEngine = _dscEngine;
        dsc = _dsc;
        continueOnRevert = _continueOnRevert;

        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(weth)));
        btcUsdPriceFeed = MockV3Aggregator(dscEngine.getCollateralTokenPriceFeed(address(wbtc)));
        
        for (uint256 i = 0; i < MAX_ACTORS; i++) {
            actors.add(makeAddr(string(abi.encodePacked("actor", i))));
        }
    }

    /////////////////////////////
    // Actor Management        //
    /////////////////////////////

    function _getRandomActor(uint256 seed) internal view returns (address) {
        uint256 index = bound(seed, 0, actors.length() - 1);
        return actors.at(index);
    }

    modifier useRandomActor(uint256 actorSeed) {
        address actor = _getRandomActor(actorSeed);
        vm.startPrank(actor);
        _;
        vm.stopPrank();
    }

    /////////////////////////////
    // DSCEngine Functions     //
    /////////////////////////////

    function depositCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral,
        uint256 actorSeed
    )   public useRandomActor(actorSeed) 
    {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        
        _ensureCollateralBalance(collateral, amountCollateral);
        
        bool approveSuccess = collateral.approve(address(dscEngine), amountCollateral);
        assertTrue(approveSuccess);
        
        if (continueOnRevert) {
            try dscEngine.depositCollateral(address(collateral), amountCollateral) {
                ghostTotalCollateralDeposited += amountCollateral;
            } catch {
                // Ignore revert
            }
        } else {
            if (_canDeposit(collateral, amountCollateral)) {
                dscEngine.depositCollateral(address(collateral), amountCollateral);
                ghostTotalCollateralDeposited += amountCollateral;
            }
        }
    }

    function mintDsc(
        uint256 amountDsc,
        uint256 actorSeed
    )   public useRandomActor(actorSeed)
    {
        amountDsc = bound(amountDsc, 1, MAX_DEPOSIT_SIZE);
        
        if (continueOnRevert) {
            try dscEngine.mintDsc(amountDsc) {
                ghostTotalDscMinted += amountDsc;
            } catch {
                // Ignore revert
            }
        } else {
            uint256 healthFactor = dscEngine.getHealthFactor(msg.sender);
            if (healthFactor > dscEngine.getMinHealthFactor()) {
                uint256 maxSafeMint = _calculateMaxSafeMint(msg.sender);
                if (amountDsc <= maxSafeMint) {
                    dscEngine.mintDsc(amountDsc);
                    ghostTotalDscMinted += amountDsc;
                }
            }
        }
    }

    function depositAndMint(
        uint256 collateralSeed,
        uint256 amountCollateral,
        uint256 amountDsc,
        uint256 actorSeed
    )   public useRandomActor(actorSeed) 
    {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        amountDsc = bound(amountDsc, 1, MAX_DEPOSIT_SIZE);
        
        _ensureCollateralBalance(collateral, amountCollateral);
        
        bool approveSuccess = collateral.approve(address(dscEngine), amountCollateral);
        assertTrue(approveSuccess);
        
        if (continueOnRevert) {
            try dscEngine.depositCollateralAndMintDsc(
                address(collateral), 
                amountCollateral, 
                amountDsc
            ) {
                ghostTotalCollateralDeposited += amountCollateral;
                ghostTotalDscMinted += amountDsc;
            } catch {
                // Ignore revert
            }
        } else {
            uint256 collateralValue = dscEngine.getUsdValue(address(collateral), amountCollateral);
            uint256 maxSafeMint = (collateralValue * 50) / 100;
            
            if (amountDsc <= maxSafeMint) {
                dscEngine.depositCollateralAndMintDsc(address(collateral), amountCollateral, amountDsc);
                ghostTotalCollateralDeposited += amountCollateral;
                ghostTotalDscMinted += amountDsc;
            }
        }
    }

    function redeemCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral,
        uint256 actorSeed
    )   public useRandomActor(actorSeed) 
    {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 userBalance = dscEngine.getCollateralBalanceOfUser(msg.sender, address(collateral));
        amountCollateral = bound(amountCollateral, 1, userBalance);
        
        if (amountCollateral == 0) return;
        
        if (continueOnRevert) {
            try dscEngine.redeemCollateral(address(collateral), amountCollateral) {
                ghostTotalCollateralDeposited -= amountCollateral;
            } catch {
                // Ignore revert
            }
        } else {
            uint256 dscMinted = dscEngine.getDscMinted(msg.sender);
            if (dscMinted == 0) {
                dscEngine.redeemCollateral(address(collateral), amountCollateral);
                ghostTotalCollateralDeposited -= amountCollateral;
            } else {
                uint256 healthBefore = dscEngine.getHealthFactor(msg.sender);
                if (healthBefore > dscEngine.getMinHealthFactor() * 2) {
                    dscEngine.redeemCollateral(address(collateral), amountCollateral);
                    ghostTotalCollateralDeposited -= amountCollateral;
                }
            }
        }
    }

    function burnDsc(
        uint256 amountDsc,
        uint256 actorSeed
    )   public useRandomActor(actorSeed)
    {
        uint256 userBalance = dsc.balanceOf(msg.sender);
        amountDsc = bound(amountDsc, 1, userBalance);
        
        if (amountDsc == 0) return;
        
        vm.startPrank(msg.sender);
        bool approveSuccess = dsc.approve(address(dscEngine), amountDsc);
        assertTrue(approveSuccess);
        
        if (continueOnRevert) {
            try dscEngine.burnDsc(amountDsc) {
                ghostTotalDscMinted -= amountDsc;
            } catch {
                // Ignore revert
            }
        } else {
            dscEngine.burnDsc(amountDsc);
            ghostTotalDscMinted -= amountDsc;
        }
        vm.stopPrank();
    }

    function liquidate(
        uint256 collateralSeed,
        uint256 userSeed,
        uint256 debtToCover,
        uint256 actorSeed
    )  public useRandomActor(actorSeed) 
    {
        address userToLiquidate = _getRandomActor(userSeed);
        debtToCover = bound(debtToCover, 1, MAX_DEPOSIT_SIZE);
        
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        
        uint256 healthFactor = dscEngine.getHealthFactor(userToLiquidate);
        if (healthFactor >= dscEngine.getMinHealthFactor()) {
            return;
        }
        
        _ensureDscBalance(debtToCover);
        
        bool approveSuccess = dsc.approve(address(dscEngine), debtToCover);
        assertTrue(approveSuccess);
        
        if (continueOnRevert) {
            try dscEngine.liquidate(address(collateral), userToLiquidate, debtToCover) {
                ghostLiquidations++;
            } catch {
                // Ignore revert
            }
        } else {
            dscEngine.liquidate(address(collateral), userToLiquidate, debtToCover);
            ghostLiquidations++;
        }
    }

    /////////////////////////////
    // Price Feed Functions    //
    /////////////////////////////

    function updatePrice(
        uint96 newPrice,
        uint256 collateralSeed
    )   public 
    {
        // For invariants, we avoid prices that break the protocol
        if (!continueOnRevert && newPrice == 0)
        {
        return; // Simply ignore zero updates in invariant mode
        }

        int256 intNewPrice = int256(uint256(newPrice));
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        MockV3Aggregator priceFeed = _getPriceFeed(collateral);
        priceFeed.updatePrice(intNewPrice);
    }

    /////////////////////////////
    // Helper Functions        //
    /////////////////////////////

    function _getCollateralFromSeed(uint256 seed) private view returns (ERC20Mock) {
        return seed % 2 == 0 ? weth : wbtc;
    }

    function _getPriceFeed(ERC20Mock collateral) private view returns (MockV3Aggregator) {
        return address(collateral) == address(weth) ? ethUsdPriceFeed : btcUsdPriceFeed;
    }

    function _ensureCollateralBalance(ERC20Mock token, uint256 amount) private {
        uint256 balance = token.balanceOf(msg.sender);
        if (balance < amount) {
            token.mint(msg.sender, amount - balance);
        }
    }

    function _ensureDscBalance(uint256 amount) private {
        uint256 balance = dsc.balanceOf(msg.sender);
        if (balance < amount) {
            address owner = dsc.owner();
            vm.prank(owner);
            bool mintSuccess = dsc.mint(msg.sender, amount - balance);
            assertTrue(mintSuccess);
        }
    }

    function _canDeposit(ERC20Mock token, uint256 amount) private view returns (bool) {
        return token.balanceOf(msg.sender) >= amount;
    }

    function _calculateMaxSafeMint(address user) private view returns (uint256) {
        uint256 collateralValue = dscEngine.getAccountCollateralValue(user);
        return (collateralValue * 40) / 100;
    }

    /////////////////////////////
    // Call Summary            //
    /////////////////////////////

    function callSummary() external view {
        console.log("=== Handler Summary ===");
        console.log("Total Collateral Deposited:", ghostTotalCollateralDeposited / 1e18);
        console.log("Total DSC Minted:", ghostTotalDscMinted / 1e18);
        console.log("Total Liquidations:", ghostLiquidations);
        console.log("Active Actors:", actors.length());
    }
}