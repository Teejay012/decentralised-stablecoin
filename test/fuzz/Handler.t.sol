// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { Test } from "forge-std/Test.sol";
import { DSCEngine } from "src/DSCEngine.sol";
import { DecentralisedStablecoin } from "src/DecentralisedStablecoin.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import { MockV3Aggregator } from "test/mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine dsce;
    DecentralisedStablecoin dsc;
    MockV3Aggregator ethUsdPriceFeed;
    MockV3Aggregator btcUsdPriceFeed;

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max; 
    uint256 public timesCalled;
    address[] public totalUsersCollateralDeposits;
    address[] public collateralAddresses;

    constructor(DecentralisedStablecoin _dsc, DSCEngine _dsce) {
        dsc = _dsc;
        dsce = _dsce;

        address[] memory collaterals = dsce.getCollateralTokens();
        weth = ERC20Mock(collaterals[0]);
        wbtc = ERC20Mock(collaterals[1]);

        ethUsdPriceFeed = MockV3Aggregator(dsce.getPriceFeed(address(weth)));
        btcUsdPriceFeed = MockV3Aggregator(dsce.getPriceFeed(address(wbtc)));
    }

    function depositCollateral(uint256 collateralSeed, uint256 amount) external {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amount = bound(amount, 1, MAX_DEPOSIT_SIZE);
        
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amount);
        collateral.approve(address(dsce), amount);
        dsce.depositCollateral(address(collateral), amount);
        vm.stopPrank();

        totalUsersCollateralDeposits.push(msg.sender);
        collateralAddresses.push(address(collateral));
    }


    function redeemCollateral(uint256 collateralSeed, uint256 amount, uint256 addressSeed) external {
        if (totalUsersCollateralDeposits.length == 0) return;

        address sender = totalUsersCollateralDeposits[addressSeed % totalUsersCollateralDeposits.length];
        address token = collateralAddresses[collateralSeed % collateralAddresses.length];

        uint256 balance = dsce.getUserCollateralBalance(sender, token);
        if (balance == 0) return;

        amount = bound(amount, 1, balance);

        // Predict if redeeming this `amount` will break health factor
        (uint256 totalDscMinted, uint256 collateralInUsd) = dsce.getAccountInformation(sender);

        // Assume price oracle gives 1:1 for now
        uint256 redeemInUsd = dsce.getUsdValue(token, amount);

        // Calculate new collateralInUsd
        if (redeemInUsd >= collateralInUsd) return; // would be negative or 0
        uint256 newCollateralUsd = collateralInUsd - redeemInUsd;

        // Simulate health factor manually
        if (totalDscMinted == 0) return; // no debt = nothing to protect
        uint256 newHealthFactor = dsce.calculateHealthFactor(totalDscMinted, newCollateralUsd);

        if (newHealthFactor < 1e18) return; // would revert

        // All checks passed, redeem
        vm.startPrank(sender);
        dsce.redeemCollateral(token, amount);
        vm.stopPrank();

        timesCalled++;
    }


    // function redeemCollateral(uint256 collateralSeed, uint256 amount, uint256 addressSeed) external {
    //     if (totalUsersCollateralDeposits.length == 0){
    //         return;
    //     }
    //     address sender = totalUsersCollateralDeposits[addressSeed % totalUsersCollateralDeposits.length];
    //     ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
    //     uint256 maxAmountToRedeem = dsce.getUserCollateralBalance(sender, address(collateral));
    //     amount = bound(amount, 0, maxAmountToRedeem);

    //     if(amount == 0){
    //         return;
    //     }
    //     vm.startPrank(sender);
    //     dsce.redeemCollateral(address(collateral), amount);
    //     vm.stopPrank();
    // }

    function mintDsc(uint256 amount, uint256 addressSeed) external {
        if (totalUsersCollateralDeposits.length == 0){
            return;
        }
        address sender = totalUsersCollateralDeposits[addressSeed % totalUsersCollateralDeposits.length];
        (uint256 totalUsdMinted, uint256 collateralAmountInUsd) = dsce.getAccountInformation(sender);
        int256 maxAmountToMint = ((int256(collateralAmountInUsd) / 2) - (int256(totalUsdMinted)));
        maxAmountToMint = (maxAmountToMint * 99) / 100;
        if(maxAmountToMint <= 0){
            return;
        }
        amount = bound(amount, 0, uint256(maxAmountToMint));
        if(amount == 0){
            return;
        }
        vm.startPrank(sender);
        dsce.mintDsc(amount);
        vm.stopPrank();

        timesCalled++;
    }

    // function updatePriceFeed(uint96 newPrice) external {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    // }

    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }
}