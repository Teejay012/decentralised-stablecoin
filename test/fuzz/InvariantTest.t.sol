// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { Test } from "forge-std/Test.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { DecentralisedStablecoin } from "src/DecentralisedStablecoin.sol";
import { DSCEngine } from "src/DSCEngine.sol";
import { HelperConfig } from "script/HelperConfig.s.sol";
import { DeployDSC } from "script/DeployDSC.s.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { Handler } from "test/fuzz/Handler.t.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import { console } from "forge-std/console.sol";

contract InvariantTest is StdInvariant, Test {
    DeployDSC deployer;
    DecentralisedStablecoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    Handler handler;

    address weth;
    address wbtc;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        // Set the address of the contract to be tested
        (,, weth, wbtc,) = config.activeNetworkConfig();
        handler = new Handler(dsc, dsce);
        targetContract(address(handler));
        // targetContract(address(dsce));
    }

    function invariant_testProtocolHasMoreValueThanTheTotalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();
        
        uint256 wethDeposited = ERC20Mock(weth).balanceOf(address(dsce));
        uint256 wbtcDeposited = ERC20Mock(wbtc).balanceOf(address(dsce));

        uint256 wethValueUsd = dsce.getUsdValue(weth, wethDeposited);
        uint256 wbtcValueUsd = dsce.getUsdValue(wbtc, wbtcDeposited);

        uint256 totalValue = wethValueUsd + wbtcValueUsd;
        // console.log("Times Count: ", handler.timesCalled);

        assert(totalValue >= totalSupply);
    } 

    // function invariant_gettersShouldNotRevert() public view {
    //     dsce.getCollateralTokens();
    // }
}
