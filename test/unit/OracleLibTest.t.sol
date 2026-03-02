// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { MockV3Aggregator } from "../mocks/MockV3Aggregator.sol";
import { Test } from "forge-std/Test.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { OracleLib, AggregatorV3Interface } from "../../src/libraries/OracleLib.sol";

contract OracleLibTest is StdCheats, Test {
    using OracleLib for AggregatorV3Interface;

    MockV3Aggregator public aggregator;
    uint8 public constant DECIMALS = 8;
    int256 public constant INITIAL_PRICE = 2000e8;
    uint256 public constant TIMEOUT = 3 hours;

    function setUp() public {
        aggregator = new MockV3Aggregator(DECIMALS, INITIAL_PRICE);
    }

    ///////////////////
    // Timeout Tests //
    ///////////////////

    function test_GetTimeout() public view {
        assertEq(OracleLib.getTimeout(AggregatorV3Interface(address(aggregator))), TIMEOUT);
    }

    ///////////////////////
    // Stale Price Tests //
    ///////////////////////   
    
    function test_RevertWhen_PriceIsStale() public {
        vm.warp(block.timestamp + TIMEOUT + 1 seconds);
        vm.roll(block.number + 1);

        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        AggregatorV3Interface(address(aggregator)).staleCheckLatestRoundData();
    }

    function test_SuccessWhen_PriceIsAtExactTimeout() public view {
        (uint80 roundId, int256 price, , , ) = AggregatorV3Interface(address(aggregator)).staleCheckLatestRoundData();
        
        assertEq(roundId, 1);
        assertEq(price, INITIAL_PRICE);
    }

    ////////////////////////////
    // Answered InRound Tests //
    ////////////////////////////   

    function test_RevertWhen_AnsweredInRoundIsZero() public {
        uint80 roundId = 1;
        int256 answer = INITIAL_PRICE;
        uint256 timestamp = block.timestamp;
        uint256 startedAt = block.timestamp;
        uint80 answeredInRound = 0;
        
        aggregator.updateRoundData(roundId, answer, timestamp, startedAt, answeredInRound);

        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        AggregatorV3Interface(address(aggregator)).staleCheckLatestRoundData();
    }

    function test_RevertWhen_AnsweredInRoundMismatch() public {
        uint80 roundId = 2;
        int256 answer = INITIAL_PRICE;
        uint256 timestamp = block.timestamp;
        uint256 startedAt = block.timestamp;
        uint80 answeredInRound = 1;
        
        aggregator.updateRoundData(roundId, answer, timestamp, startedAt, answeredInRound);

        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        AggregatorV3Interface(address(aggregator)).staleCheckLatestRoundData();
    }

    //////////////////////////
    // Success Cases  Tests //
    //////////////////////////  

    function test_GetValidPrice() public view {
        (uint80 roundId, int256 price, , , ) = AggregatorV3Interface(address(aggregator)).staleCheckLatestRoundData();
        
        assertEq(roundId, 1);
        assertEq(price, INITIAL_PRICE);
    }

    function test_GetValidPriceAfterUpdate() public {
        int256 newPrice = 2500e8;
        aggregator.updatePrice(newPrice);

        (uint80 roundId, int256 price, , , ) = 
            AggregatorV3Interface(address(aggregator)).staleCheckLatestRoundData();
        
        assertEq(roundId, 2);
        assertEq(price, newPrice);
    }

    function test_GetValidPriceMultipleUpdates() public {
        int256[] memory prices = new int256[](3);
        prices[0] = 2100e8;
        prices[1] = 2200e8;
        prices[2] = 2300e8;

        for (uint256 i = 0; i < prices.length; i++) {
            aggregator.updatePrice(prices[i]);
            
            (uint80 roundId, int256 price, , , ) = 
                AggregatorV3Interface(address(aggregator)).staleCheckLatestRoundData();
            
            assertEq(roundId, i + 2);
            assertEq(price, prices[i]);
        }
    }


    ////////////////////
    // MockS Behavior //
    ////////////////////  
       
    function test_MockAggregatorBehavior() public view {
        (uint80 roundId, int256 price, , , ) = aggregator.latestRoundData();
        assertEq(roundId, 1);
        assertEq(price, INITIAL_PRICE);
    }
}