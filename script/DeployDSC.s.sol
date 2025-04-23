// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { Script } from "forge-std/Script.sol";
import { DecentralisedStablecoin } from "../src/DecentralisedStablecoin.sol";
import { DSCEngine } from "../src/DSCEngine.sol";
import { HelperConfig } from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    address[] public tokenCollateralAddresses;
    address[] public tokenPriceFeedAddresses;
    
    function run() external returns (DecentralisedStablecoin, DSCEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();
        (
            address wethUsdPriceFeed,
            address wbtcUsdPriceFeed,
            address weth,
            address wbtc,
            uint256 deployerKey
            // address owner
        ) = config.activeNetworkConfig();

        tokenCollateralAddresses = [weth, wbtc];
        tokenPriceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);
        DecentralisedStablecoin decentralisedStablecoin = new DecentralisedStablecoin();
        DSCEngine engine = new DSCEngine(
            tokenCollateralAddresses,
            tokenPriceFeedAddresses,
            address(decentralisedStablecoin)
        );
        decentralisedStablecoin.transferOwnership(address(engine));
        vm.stopBroadcast();
        return (decentralisedStablecoin, engine, config);
    }
}