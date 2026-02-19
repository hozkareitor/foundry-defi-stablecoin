// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { MockV3Aggregator } from "../test/mocks/MockV3Aggregator.sol";
import { ERC20Mock } from "../test/mocks/ERC20Mock.sol";

/**
 * @title HelperConfig
 * @author Patrick Collins
 * @notice Configuration helper that provides network-specific addresses
 * @dev Automatically detects network and returns appropriate contract addresses
 *      Deploys mocks when on local Anvil chain
 */
contract HelperConfig is Script {
    ///////////////////
    //     Errors    //
    ///////////////////

    error HelperConfig__InvalidChainId();
    error HelperConfig__InvalidPriceFeedAddress();
    error HelperConfig__InvalidTokenAddress();
    error HelperConfig__EnvironmentVariableNotSet(string variable);

    /////////////////////////
    //   Type Declarations //
    /////////////////////////

    /**
     * @notice Network configuration struct containing all necessary addresses
     * @param wethUsdPriceFeed Address of Chainlink ETH/USD price feed
     * @param wbtcUsdPriceFeed Address of Chainlink BTC/USD price feed  
     * @param weth Address of WETH token
     * @param wbtc Address of WBTC token
     * @param deployerKey Private key for deployment (0 for local)
     */
    struct NetworkConfig {
        address wethUsdPriceFeed;
        address wbtcUsdPriceFeed;
        address weth;
        address wbtc;
        uint256 deployerKey;
    }

    /////////////////////////
    //   State Variables   //
    /////////////////////////

    /// @dev Active network configuration based on current chain
    NetworkConfig public activeNetworkConfig;

    /// @dev Chain IDs
    uint256 public constant SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant MAINNET_CHAIN_ID = 1;
    uint256 public constant ANVIL_CHAIN_ID = 31337;

    /// @dev Mock price feed configuration
    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8; // $2000 with 8 decimals
    int256 public constant BTC_USD_PRICE = 60000e8; // $60,000 with 8 decimals

    /// @dev Default Anvil private key (first account)
    uint256 public constant DEFAULT_ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    ///////////////////
    //   Functions   //
    ///////////////////

    /**
     * @notice Constructor that sets the active network config based on chain ID
     */
    constructor() {
        if (block.chainid == SEPOLIA_CHAIN_ID) {
            activeNetworkConfig = _getSepoliaConfig();
        } else if (block.chainid == MAINNET_CHAIN_ID) {
            activeNetworkConfig = _getMainnetConfig();
        } else if (block.chainid == ANVIL_CHAIN_ID) {
            activeNetworkConfig = _getOrCreateAnvilConfig();
        } else {
            revert HelperConfig__InvalidChainId();
        }
        
        console.log("HelperConfig initialized for chain ID:", block.chainid);
    }

    ///////////////////////////
    //   Internal Functions  //
    ///////////////////////////

    /**
     * @dev Returns Sepolia testnet configuration
     * @return sepoliaConfig NetworkConfig for Sepolia
     */
    function _getSepoliaConfig() internal view returns (NetworkConfig memory sepoliaConfig) {
        uint256 privateKey;
        
        // Try to get PRIVATE_KEY from environment, use default for testing if not found
        try vm.envUint("PRIVATE_KEY") returns (uint256 key) {
            privateKey = key;
        } catch {
            console.log("Warning: PRIVATE_KEY not found in .env, using default Anvil key for Sepolia (tests only)");
            privateKey = DEFAULT_ANVIL_PRIVATE_KEY;
        }

        sepoliaConfig = NetworkConfig({
            wethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306, // ETH/USD Sepolia
            wbtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43, // BTC/USD Sepolia
            weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81, // WETH Sepolia
            wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063, // WBTC Sepolia
            deployerKey: privateKey
        });

        // Validate addresses
        _validateConfig(sepoliaConfig);
    }

    /**
     * @dev Returns Mainnet configuration
     * @return mainnetConfig NetworkConfig for Mainnet
     */
    function _getMainnetConfig() internal view returns (NetworkConfig memory mainnetConfig) {
        uint256 privateKey;
        
        // Try to get MAINNET_PRIVATE_KEY from environment
        try vm.envUint("MAINNET_PRIVATE_KEY") returns (uint256 key) {
            privateKey = key;
        } catch {
            revert HelperConfig__EnvironmentVariableNotSet("MAINNET_PRIVATE_KEY");
        }

        mainnetConfig = NetworkConfig({
            wethUsdPriceFeed: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419, // ETH/USD Mainnet
            wbtcUsdPriceFeed: 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c, // BTC/USD Mainnet
            weth: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, // WETH Mainnet
            wbtc: 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599, // WBTC Mainnet
            deployerKey: privateKey
        });

        _validateConfig(mainnetConfig);
    }

    /**
     * @dev Creates or returns Anvil local configuration with mocks
     * @return anvilConfig NetworkConfig for Anvil
     */
    function _getOrCreateAnvilConfig() internal returns (NetworkConfig memory anvilConfig) {
        // Check if we already have a config (for tests that call this multiple times)
        if (activeNetworkConfig.wethUsdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }

        console.log("Deploying mocks to Anvil...");

        vm.startBroadcast();

        // Deploy ETH price feed mock and WETH mock
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        ERC20Mock wethMock = new ERC20Mock("WETH", "WETH", msg.sender, 1000 ether);

        // Deploy BTC price feed mock and WBTC mock
        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(DECIMALS, BTC_USD_PRICE);
        ERC20Mock wbtcMock = new ERC20Mock("WBTC", "WBTC", msg.sender, 1000 ether);

        vm.stopBroadcast();

        console.log("Mocks deployed:");
        console.log("- ETH/USD Price Feed:", address(ethUsdPriceFeed));
        console.log("- WETH Token:", address(wethMock));
        console.log("- BTC/USD Price Feed:", address(btcUsdPriceFeed));
        console.log("- WBTC Token:", address(wbtcMock));

        anvilConfig = NetworkConfig({
            wethUsdPriceFeed: address(ethUsdPriceFeed),
            wbtcUsdPriceFeed: address(btcUsdPriceFeed),
            weth: address(wethMock),
            wbtc: address(wbtcMock),
            deployerKey: DEFAULT_ANVIL_PRIVATE_KEY
        });

        _validateConfig(anvilConfig);
        return anvilConfig;
    }

    /**
     * @dev Validates that all addresses in config are non-zero
     * @param config The NetworkConfig to validate
     */
    function _validateConfig(NetworkConfig memory config) internal pure {
        if (config.wethUsdPriceFeed == address(0)) revert HelperConfig__InvalidPriceFeedAddress();
        if (config.wbtcUsdPriceFeed == address(0)) revert HelperConfig__InvalidPriceFeedAddress();
        if (config.weth == address(0)) revert HelperConfig__InvalidTokenAddress();
        if (config.wbtc == address(0)) revert HelperConfig__InvalidTokenAddress();
    }

    /**
    * @dev Explicit getter for active network config
    * @return The current network configuration
    */
    function getActiveNetworkConfig() external view returns (NetworkConfig memory) {
        return activeNetworkConfig;
    }
}