// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { Test } from "forge-std/Test.sol";
import { DeployDSC } from "script/DeployDSC.s.sol";
import { DecentralisedStablecoin } from "src/DecentralisedStablecoin.sol";
import { DSCEngine } from "src/DSCEngine.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { HelperConfig } from "script/HelperConfig.s.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import { MockV3Aggregator } from "test/mocks/MockV3Aggregator.sol";
import { console } from "forge-std/console.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralisedStablecoin dsc;
    DSCEngine dsce;
    HelperConfig config;

    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;

    address USER = makeAddr("user");
    address LIQUIDATOR = makeAddr("liquidator");

    uint256 private constant AMOUNT_COLLATERAL = 10 ether;
    uint256 private constant STARTING_BALANCE = 10 ether;
    uint256 private constant LIQUIDATOR_BALANCE = 1000 ether;
    uint256 private constant MINT_AMOUNT = 5 ether;
    uint256 private constant HEALTH_SCORE = 1e18;
    uint256 private constant DSC_MINT = 100e18;


    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, , ) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_BALANCE);
        ERC20Mock(weth).mint(LIQUIDATOR, LIQUIDATOR_BALANCE);
        
        address actualOwner = dsc.owner(); // Assuming dsc inherits Ownable

        vm.startPrank(actualOwner);
        dsc.mint(LIQUIDATOR, DSC_MINT);
        vm.stopPrank();

        console.log("weth address: ", weth);
    }

    

    modifier depositCollateralAndMintDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        uint256 dscAmount = dsce.getUsdValue(weth, MINT_AMOUNT);
        dsce.mintDsc(dscAmount);
        vm.stopPrank();
        _;
    }

    function testGetUsdValue() public {
        uint256 amount = 15e18;
        uint256 expectedValue = 30000e18;
        uint256 actualValue = dsce.getUsdValue(weth, amount);
        assertEq(actualValue, expectedValue, "The USD value is not correct");
    }

    function testGetTokenAmountFromUsd() public {
        uint256 amount = 100 ether;

        uint256 expectedValue = 0.05 ether;
        uint256 actualValue = dsce.getTokenAmountFromUsd(weth, amount);
        assertEq(actualValue, expectedValue, "The token amount is not correct");
    }

    function testRevertIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__AmountShouldBeGreaterThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertIfTokenLengthDoesNotMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenCollateralAddressesMustBeEqualTOTokePriceFeedAddresses.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    function testRevertIfTokenCollateralNotCorrect() public {
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert();
        dsce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testDepositCollateralAndGetAccountInformation() public depositCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        uint256 expectedTotalDscMinted = 0;

        uint256 expectedCollateralValueInUsd = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);
        assertEq(totalDscMinted, expectedTotalDscMinted, "The total DSC minted is not correct");
        assertEq(
            collateralValueInUsd,
            expectedCollateralValueInUsd,
            "The collateral value in USD is not correct"
        );
    }

    function testIfDepositeRevertsCollateralIfAmountIsMoreThanZero() public {
        vm.startPrank(USER);

        vm.expectRevert(DSCEngine.DSCEngine__AmountShouldBeGreaterThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testDepositRevertsIfTransferFails() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.mockCall(
            address(weth),
            abi.encodeWithSelector(IERC20(weth).transferFrom.selector, USER, address(dsce), AMOUNT_COLLATERAL),
            abi.encode(false)
        );
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
    }

    function testDepositCollateralAndMintDsc() public depositCollateral {
        uint256 dscAmount = dsce.getTokenAmountFromUsd(weth, 1000 ether);
        vm.startPrank(USER);
        dsce.mintDsc(dscAmount);
        vm.stopPrank();

        uint256 expectedBalance = dsc.balanceOf(USER);
        assertEq(expectedBalance, dscAmount, "The DSC balance is not correct");
    }

    // Mint ==============

    function testMintDsc() public depositCollateral {
        vm.startPrank(USER);
        uint256 dscAmount = dsce.getUsdValue(weth, MINT_AMOUNT);
        dsce.mintDsc(dscAmount);
        vm.stopPrank();
    }

    function testRevertIfMintDscAmountIsZero() public depositCollateral {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__AmountShouldBeGreaterThanZero.selector);
        dsce.mintDsc(0);
        vm.stopPrank();
    }

    function testRevertIfMintDscAmountIsMoreThanCollateral() public depositCollateral {
        vm.startPrank(USER);
        uint256 dscAmount = dsce.getUsdValue(weth, 1000 ether);
        uint256 collateralValue = dsce.getCollateralValue(USER);
        uint256 calculateHealthFactor = dsce.calculateHealthFactor(dscAmount, collateralValue);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BrokenHealthFactor.selector, calculateHealthFactor));
        dsce.mintDsc(dscAmount);
        vm.stopPrank();
    }

    function testRevertIfMintDscTransferFails() public depositCollateral {
        vm.startPrank(USER);

        uint256 mintAmout = dsce.getUsdValue(weth, MINT_AMOUNT);

        vm.mockCall(
            address(dsc),
            abi.encodeWithSelector(ERC20Mock(address(dsc)).mint.selector, USER, mintAmout),
            abi.encode(false)
        );

        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        dsce.mintDsc(mintAmout);
        vm.stopPrank();
    }


    // Burn ==============

    function testBurnDscReducesMintedAmount() public depositCollateral {
        vm.startPrank(USER);

        // Mint 100 DSC
        dsce.mintDsc(100e18);

        // Approve DSC burn
        dsc.approve(address(dsce), 50e18);

        // Burn 50 DSC
        dsce.burnDsc(50e18);

        vm.stopPrank();

        // Check that only 50 DSC remains
        (uint256 totalMinted, ) = dsce.getAccountInformation(USER);
        assertEq(totalMinted, 50e18);

        // Check user balance also reflects this
        assertEq(dsc.balanceOf(USER), 50e18);
    }

    function testRevertIfBurnDscAmountIsMoreThanBalance() public depositCollateral {
        uint256 mintAmount = 100e18;
        uint256 burnAmount = 200e18;
        vm.startPrank(USER);
        dsce.mintDsc(mintAmount);
        dsc.approve(address(dsce), burnAmount);
        vm.expectRevert();
        dsce.burnDsc(burnAmount);
        vm.stopPrank();
    }

    function testRevertIfBurnDscAmountIsZero() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__AmountShouldBeGreaterThanZero.selector);
        dsce.burnDsc(0);
        vm.stopPrank();
    }

    function testRevertIfBurnDscTransferFails() public depositCollateral {
        uint256 mintAmount = 100e18;
        uint256 burnAmount = 100e18;

        vm.startPrank(USER);

        dsce.mintDsc(mintAmount);

        // Must match exact selector + arguments
        vm.mockCall(
            address(dsc),
            abi.encodeWithSelector(IERC20(dsc).transferFrom.selector, USER, address(dsce), burnAmount),
            abi.encode(false)
        );

        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        dsce.burnDsc(burnAmount);

        vm.stopPrank();
    }

    function testUserCollateralBalance() public depositCollateral {
        vm.startPrank(USER);
        uint256 expectedBalance = AMOUNT_COLLATERAL;
        uint256 actualBalance = dsce.getUserCollateralBalance(USER, weth);
        assertEq(expectedBalance, actualBalance);
        vm.stopPrank();
    }

    function testRevertsIfMintedDscBreaksHealthFactor() public depositCollateral {
        vm.startPrank(USER);
        uint256 dscAmountToMint = dsce.getUsdValue(weth, 6 ether);
        dsce.updateUserCollateralPrice(weth, USER, 8 ether);
        dsce.updateMintedValue(USER, dscAmountToMint);
        uint256 calculatedUserHealthFactor = dsce.getHealthFactor(USER);

        // if (calculatedUserHealthFactor >= HEALTH_SCORE) {
        //     console.log("Health factor is okay");
        // } else {
            console.log("Health factor is less than 1");
            console.log("calculatedUserHealthFactor: ", calculatedUserHealthFactor);
            dsce.updateMintedValue(USER, 0);
            vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BrokenHealthFactor.selector, calculatedUserHealthFactor));
            dsce.mintDsc(dscAmountToMint);
            vm.stopPrank();
        // }

    }

    function testLiquidate() public depositCollateralAndMintDsc {
        // uint256 updatedPrice = 1e7;
        // MockV3Aggregator(ethUsdPriceFeed).updateAnswer(int256(updatedPrice));
        dsce.updateUserCollateralPrice(weth, USER, 8 ether);
        uint256 dscAmount = dsce.getUsdValue(weth, 7 ether);
        dsce.updateMintedValue(USER, dscAmount);
        uint256 collateralValue = dsce.getCollateralValue(USER);
        uint256 mintValue = dsce.getMintedDsc(USER);
        uint256 calculateHealthFactor = dsce.calculateHealthFactor(mintValue, collateralValue);

        console.log(calculateHealthFactor);

        if(calculateHealthFactor >= HEALTH_SCORE) {
            console.log("Health factor is okay");
        } else {
            console.log("Health factor is less than 1");
            vm.startPrank(LIQUIDATOR);
            ERC20Mock(weth).approve(address(dsce), LIQUIDATOR_BALANCE);
            dsce.depositCollateral(weth, LIQUIDATOR_BALANCE);

            // uint256 dscAmount = dsce.getUsdValue(weth, MINT_AMOUNT);
            dsce.mintDsc(dscAmount);

            uint256 liquidatorCollateralValue = dsce.getCollateralValue(LIQUIDATOR);
            uint256 liquidatorMintValue = dsce.getUsdValue(weth, MINT_AMOUNT);
            uint256 liquidatorCalculateHealthFactor = dsce.calculateHealthFactor(liquidatorMintValue, liquidatorCollateralValue);

            if (liquidatorCalculateHealthFactor > HEALTH_SCORE) {
                console.log("Liquidator Health factor is greater than 1");
                console.log(calculateHealthFactor);
                dsc.approve(address(dsce), dscAmount);
                dsce.liquidate(weth, USER, dscAmount);
            } else {
                console.log("Liquidator Health factor is less than 1");
            }
            console.log("Liquidator Health Sccore: ", liquidatorCalculateHealthFactor);
            vm.stopPrank();
            
        }

        // 0x90193C961A926261B756D1E5bb255e67ff9498A1
        // 0x6CA6d1e2D5347Bfab1d91e883F1915560e09129D
        


        // vm.startPrank(LIQUIDATOR);
        
        // uint256 dscAmount = dsce.getTokenAmountFromUsd(weth, MINT_AMOUNT);
        // ERC20Mock(weth).approve(address(dsce), LIQUIDATOR_BALANCE);
        // dsce.depositCollateral(weth, LIQUIDATOR_BALANCE);
        // dsc.approve(address(dsce), dscAmount);
        // dsce.mintDsc(dscAmount);
        // dsce.liquidate(USER, weth, updatedPrice);
        // vm.stopPrank();
    }

    function testLiquidateRevertsIfHealthFactorIsOkay() public depositCollateralAndMintDsc {
        vm.startPrank(LIQUIDATOR);
        uint256 dscAmount = dsce.getUsdValue(weth, 6 ether);
        dsce.updateUserCollateralPrice(weth, USER, 8 ether);
        dsce.updateMintedValue(USER, dscAmount);
        uint256 collateralValue = dsce.getCollateralValue(USER);
        uint256 mintValue = dsce.getMintedDsc(USER);
        uint256 calculateHealthFactor = dsce.calculateHealthFactor(mintValue, collateralValue);

        if (calculateHealthFactor >= HEALTH_SCORE) {
            console.log("Health factor is okay");
            vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorOkay.selector, calculateHealthFactor));
            dsce.liquidate(USER, weth, dscAmount);
            vm.stopPrank();
        }
    }

    // function testLiquidateRevertsIfHealthFactorIsNotOkay() public depositCollateralAndMintDsc {
    //     vm.startPrank(LIQUIDATOR);
    //     uint256 dscAmount = dsce.getUsdValue(weth, 7 ether);
    //     dsce.updateUserCollateralPrice(weth, USER, 8 ether);
    //     dsce.updateMintedValue(USER, dscAmount);
    //     uint256 collateralValue = dsce.getCollateralValue(USER);
    //     uint256 mintValue = dsce.getMintedDsc(USER);
    //     uint256 calculateHealthFactorBefore = dsce.calculateHealthFactor(mintValue, collateralValue);

    //     uint256 newDscAmount = dsce.getUsdValue(weth, 7.5 ether);
    //     dsce.updateUserCollateralPrice(weth, USER, 8 ether);
    //     dsce.updateMintedValue(USER, newDscAmount);
    //     uint256 collateralValueAfter = dsce.getCollateralValue(USER);
    //     uint256 mintValueAfter = dsce.getMintedDsc(USER);
    //     uint256 calculateHealthFactorAfter = dsce.calculateHealthFactor(mintValueAfter, collateralValueAfter);

    //     // if(calculateHealthFactorAfter < calculateHealthFactorBefore) {
    //     //     console.log("Health factor is less than before");
    //         vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotOkay.selector);
    //         dsc.approve(address(dsce), dscAmount);
    //         dsce.liquidate(weth, USER, dscAmount);
    //     // } else {
    //     //     console.log("Health factor is greater than after");
    //     // }

    //     vm.stopPrank();

    //     // if (calculateHealthFactor >= HEALTH_SCORE) {
    //     //     console.log("Health factor is okay");
    //     //     vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorOkay.selector, calculateHealthFactor));
    //     //     dsce.liquidate(USER, weth, dscAmount);
    //     //     vm.stopPrank();
    //     // }
    // }

    function testGetCollateralValue() public depositCollateral {
        vm.startPrank(USER);
        uint256 actualValue = dsce.getCollateralValue(USER);
        uint256 expectedValue = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);
        assertEq(actualValue, expectedValue, "The collateral value is not correct");
        vm.stopPrank();
    }

    function testCalculateHealthFactor() public depositCollateral {
        vm.startPrank(USER);
        uint256 dscAmount = dsce.getUsdValue(weth, MINT_AMOUNT);
        dsc.approve(address(dsce), dscAmount);
        dsce.mintDsc(dscAmount);
        uint256 minTestValue = dsce.getMintedDsc(USER);
        uint256 collateralValueInUsd = dsce.getCollateralValue(USER);
        uint256 calculatedHealthFactor = dsce.calculateHealthFactor(minTestValue, collateralValueInUsd);
        assertEq(calculatedHealthFactor, HEALTH_SCORE, "The health factor is not correct");
        vm.stopPrank();
    }

    // function testCanBurnDsc() public depositCollateralAndMintDsc {
    //     vm.startPrank(LIQUIDATOR);
    //     uint256 userMintedDsc = dsce.getMintedDsc(LIQUIDATOR);
    //     dsc.approve(address(dsce), userMintedDsc);
    //     dsce.burnDsc(userMintedDsc);
    //     uint256 actualBalance = dsce.getMintedDsc(USER);
    //     assertEq(actualBalance, 0, "The minted DSC balance is not correct");
    //     vm.stopPrank();
    // }

    function testRedeemCollateral() public depositCollateral {
        vm.startPrank(USER);
        uint256 initialBalance = ERC20Mock(weth).balanceOf(USER);
        uint256 collateral = dsce.getUserCollateralBalance(USER, weth);
        dsce.redeemCollateral(weth, collateral);
        uint256 finalBalance = ERC20Mock(weth).balanceOf(USER);
        assertEq(finalBalance, initialBalance + collateral, "The collateral balance is not correct");
        vm.stopPrank();
    }

    function testRevertIfRedeemCollateralAmountIsMoreThanBalance() public depositCollateral {
        vm.startPrank(USER);
        uint256 collateralBalance = dsce.getUserCollateralBalance(USER, weth);
        vm.expectRevert(DSCEngine.DSCEngine__AmountShouldBeLessThanTheCollateralBalance.selector);
        dsce.redeemCollateral(weth, collateralBalance + 1);
        vm.stopPrank();
    }

    function testRevertIfRedeemCollateralAmountIsZero() public depositCollateral {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__AmountShouldBeGreaterThanZero.selector);
        dsce.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertIfRedeemCollateralTransferFails() public depositCollateral {
        vm.startPrank(USER);
        uint256 collateralBalance = dsce.getUserCollateralBalance(USER, weth);
        vm.mockCall(
            address(weth),
            abi.encodeWithSelector(IERC20(weth).transfer.selector, USER, collateralBalance),
            abi.encode(false)
        );
        
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        dsce.redeemCollateral(weth, collateralBalance);
        vm.stopPrank();
    }

}