// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { HelperConfig } from "./HelperConfig.s.sol";
import { DecentralizedStableCoin } from "../src/DecentralizedStableCoin.sol";
import { DSCEngine } from "../src/DSCEngine.sol";

contract DeployDSC is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    error DeployDSC__OwnershipTransferFailed();
    error DeployDSC__InvalidConfiguration();
    error DeployDSC__DeploymentFailed();

    function run() external returns (DecentralizedStableCoin dsc, DSCEngine dscEngine, HelperConfig helperConfig) {
        helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getActiveNetworkConfig();

        // Obtener la dirección del deployer desde la private key
        address deployer = vm.addr(config.deployerKey);
        
        tokenAddresses = [config.weth, config.wbtc];
        priceFeedAddresses = [config.wethUsdPriceFeed, config.wbtcUsdPriceFeed];

        console.log("");
        console.log("=== Decentralized Stablecoin Deployment ===");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer address:", deployer);
        console.log("");
        console.log("Collateral Tokens:");
        console.log("- WETH:", config.weth);
        console.log("- WBTC:", config.wbtc);
        console.log("");
        console.log("Price Feeds:");
        console.log("- ETH/USD:", config.wethUsdPriceFeed);
        console.log("- BTC/USD:", config.wbtcUsdPriceFeed);
        console.log("");

        _validateConfig(config);

        // Un SOLO broadcast para todo
        vm.startBroadcast(config.deployerKey);

        // Desplegar DSC con el deployer como owner
        dsc = new DecentralizedStableCoin(deployer);  // Usar deployer EXPLÍCITAMENTE
        console.log("DSC deployed at:", address(dsc));
        console.log("   Temporary owner (deployer):", deployer);

        // Desplegar DSCEngine
        dscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
        console.log("DSCEngine deployed at:", address(dscEngine));

        // Transferir ownership (ahora deployer es el owner)
        dsc.transferOwnership(address(dscEngine));
        console.log("Transferred DSC ownership to DSCEngine");
        console.log("   New DSC owner:", address(dscEngine));

        vm.stopBroadcast();

        _verifyDeployment(dsc, dscEngine, config);

        console.log("");
        console.log("=== Deployment Summary ===");
        console.log("DSC Address:", address(dsc));
        console.log("DSCEngine Address:", address(dscEngine));
        console.log("DSC Owner (final):", dsc.owner());
        console.log("==========================");
        console.log("");

        return (dsc, dscEngine, helperConfig);
    }

    function _validateConfig(HelperConfig.NetworkConfig memory config) internal pure {
        if (config.weth == address(0) || config.wbtc == address(0)) revert DeployDSC__InvalidConfiguration();
        if (config.wethUsdPriceFeed == address(0) || config.wbtcUsdPriceFeed == address(0)) revert DeployDSC__InvalidConfiguration();
        if (config.deployerKey == 0) revert DeployDSC__InvalidConfiguration();
    }

    function _verifyDeployment(
        DecentralizedStableCoin dsc, 
        DSCEngine dscEngine,
        HelperConfig.NetworkConfig memory config
    ) internal view {
        if (dsc.owner() != address(dscEngine)) revert DeployDSC__OwnershipTransferFailed();
        if (address(dscEngine.getDsc()) != address(dsc)) revert DeployDSC__DeploymentFailed();
        if (dscEngine.getPriceFeed(config.weth) != config.wethUsdPriceFeed) revert DeployDSC__DeploymentFailed();
        if (dscEngine.getPriceFeed(config.wbtc) != config.wbtcUsdPriceFeed) revert DeployDSC__DeploymentFailed();
        
        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        if (collateralTokens.length != 2) revert DeployDSC__DeploymentFailed();
        if (collateralTokens[0] != config.weth || collateralTokens[1] != config.wbtc) revert DeployDSC__DeploymentFailed();

        console.log("Deployment verified successfully");
    }
}