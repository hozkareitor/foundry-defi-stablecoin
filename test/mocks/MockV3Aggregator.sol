// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title MockV3Aggregator
 * @notice Mock Chainlink price feed for testing
 * @dev Used in local Anvil environment to simulate price feeds
 */
contract MockV3Aggregator is AggregatorV3Interface {
    int256 private _price;
    uint8 private _decimals;
    
    // Round data
    uint80 private _latestRoundId;
    uint256 private _startedAt;
    uint256 private _updatedAt;
    uint80 private _answeredInRound;
    
    constructor(uint8 _decimals_, int256 _initialPrice) {
        _decimals = _decimals_;
        _price = _initialPrice;
        _latestRoundId = 1;
        _startedAt = block.timestamp;
        _updatedAt = block.timestamp;
        _answeredInRound = 1;
    }
    
    function decimals() external view override returns (uint8) {
        return _decimals;
    }
    
    function description() external pure override returns (string memory) {
        return "Mock Price Feed";
    }
    
    function version() external pure override returns (uint256) {
        return 1;
    }
    
    function getRoundData(uint80 _roundId)
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (_roundId, _price, _startedAt, _updatedAt, _roundId);
    }
    
    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (_latestRoundId, _price, _startedAt, _updatedAt, _answeredInRound);
    }
    
    // Helper functions for testing
    function updatePrice(int256 _newPrice) external {
        _price = _newPrice;
        _latestRoundId++;
        _startedAt = block.timestamp;
        _updatedAt = block.timestamp;
        _answeredInRound = _latestRoundId;
    }
    
    function updateRoundData(
        uint80 _roundId,
        int256 _newPrice,
        uint256 _startedAt_,
        uint256 _updatedAt_,
        uint80 _answeredInRound_
    ) external {
        _latestRoundId = _roundId;
        _price = _newPrice;
        _startedAt = _startedAt_;
        _updatedAt = _updatedAt_;
        _answeredInRound = _answeredInRound_;
    }
}