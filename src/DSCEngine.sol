// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DecentralisedStablecoin} from "./DecentralisedStablecoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import { OracleLib } from "./libraries/OracleLib.sol";

/*
 * @title DSCEngine
 * @author Peace Teejay
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of
 * all collateral < the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */

contract DSCEngine is ReentrancyGuard {
    // ERRORS

    error DSCEngine__AmountShouldBeGreaterThanZero();
    error DSCEngine__TokenCollateralAddressesMustBeEqualTOTokePriceFeedAddresses();
    error DSCEngine__NotAllowedToken(address token);
    error DSCEngine__TransferFailed();
    error DSCEngine__BrokenHealthFactor(uint256 healthFactorValue);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOkay(uint256 healthFactorValue);
    error DSCEngine__HealthFactorNotOkay();
    error DSCEngine__AmountShouldBeLessThanTheCollateralBalance();

    // TYPES

    using OracleLib for AggregatorV3Interface;

    // State Variables

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;

    mapping(address token => address priceFeed) private s_tokenToPriceFeed;
    mapping(address user => mapping(address token => uint256 amount)) private s_userToTokenDeposits;
    mapping(address user => uint256 amount) private s_DSCMinted;

    address[] private s_collateralTokens;

    DecentralisedStablecoin private immutable i_dsc;

    // EVENTS

    event DepositedCollateral(address indexed user, address indexed tokenCollateralAddress, uint256 amount);
    event RedeemedCollateral(address indexed redeemFrom, address indexed redeemTo, address indexed tokenCollateralAddress, uint256 amount);

    // SPECIAL FUNCTIONS

    constructor(address[] memory tokenCollateralAddresses, address[] memory priceFeedAddresses, address DscAddress) {
        if (tokenCollateralAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenCollateralAddressesMustBeEqualTOTokePriceFeedAddresses();
        }

        for (uint256 i = 0; i < tokenCollateralAddresses.length; i++) {
            s_tokenToPriceFeed[tokenCollateralAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenCollateralAddresses[i]);
        }

        i_dsc = DecentralisedStablecoin(DscAddress);
    }

    // MODIFIERS

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__AmountShouldBeGreaterThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_tokenToPriceFeed[token] == address(0)) {
            revert DSCEngine__NotAllowedToken(token);
        }
        _;
    }

    // EXTERNAL FUNCTIONS

    function depositCollateralAndMintDsc(address collateralTokenAddress, uint256 collateralAmount, uint256 dscAmountToMint) external {
        depositCollateral(collateralTokenAddress, collateralAmount);

        mintDsc(dscAmountToMint);
    }

    function depositCollateral(address tokenCollateralAddress, uint256 amount)
        public
        moreThanZero(amount)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {

        s_userToTokenDeposits[msg.sender][tokenCollateralAddress] += amount;

        emit DepositedCollateral(msg.sender, tokenCollateralAddress, amount);
        
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amount);

        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateralForDsc(address collateralTokenAddress, uint256 collateralAmount, uint256 dscAmount) external moreThanZero(collateralAmount) isAllowedToken(collateralTokenAddress) {
        _burnDsc(dscAmount, msg.sender, msg.sender);
        redeemCollateral(collateralTokenAddress, collateralAmount);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function redeemCollateral(address collateralTokenAddress, uint256 collateralAmount) public moreThanZero(collateralAmount) isAllowedToken(collateralTokenAddress) nonReentrant {
        _redeemCollateral(collateralTokenAddress, collateralAmount, msg.sender, msg.sender);

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function mintDsc(uint256 amountToMint) public moreThanZero(amountToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountToMint;

        _revertIfHealthFactorIsBroken(msg.sender);
        bool success = i_dsc.mint(msg.sender, amountToMint);
        if (!success) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
    * @param collateral: The ERC20 token address of the collateral you're using to make the protocol solvent again.
    * This is collateral that you're going to take from the user who is insolvent.
    * In return, you have to burn your DSC to pay off their debt, but you don't pay off your own.
    * @param user: The user who is insolvent. They have to have a _healthFactor below MIN_HEALTH_FACTOR
    * @param debtToCover: The amount of DSC you want to burn to cover the user's debt.
    *
    * @notice: You can partially liquidate a user.
    * @notice: You will get a 10% LIQUIDATION_BONUS for taking the users funds.
    * @notice: This function working assumes that the protocol will be roughly 150% overcollateralized in order for this
    to work.
    * @notice: A known bug would be if the protocol was only 100% collateralized, we wouldn't be able to liquidate
    anyone.
    * For example, if the price of the collateral plummeted before anyone could be liquidated.
    */

    function liquidate(address collateralTokenAddress, address user, uint256 debtToCover) external moreThanZero(debtToCover) isAllowedToken(collateralTokenAddress) nonReentrant {
        (uint256 totalUsdMinted, uint256 collateralAmountInUsd) = getAccountInformation(user);

        uint256 startingHealthFactor = _calculateHealthFactor(totalUsdMinted, collateralAmountInUsd);
        if(startingHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOkay(startingHealthFactor);
        }

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateralTokenAddress, debtToCover);

        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;

        s_userToTokenDeposits[msg.sender][collateralTokenAddress] += totalCollateralToRedeem;

        _redeemCollateral(collateralTokenAddress, totalCollateralToRedeem, user, msg.sender);
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingHealthFactor = _healthFactor(user);
        if(endingHealthFactor <= startingHealthFactor){
            revert DSCEngine__HealthFactorNotOkay();
        }

        _revertIfHealthFactorIsBroken(msg.sender);
    }


    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    // INTERNAL FUNCTIONS

    function _redeemCollateral(address collateralTokenAddress, uint256 collateralAmount, address from, address to) internal {
        if (s_userToTokenDeposits[to][collateralTokenAddress] < collateralAmount) {
            revert DSCEngine__AmountShouldBeLessThanTheCollateralBalance();
        }
        s_userToTokenDeposits[from][collateralTokenAddress] -= collateralAmount;

        emit RedeemedCollateral(from, to, collateralTokenAddress, collateralAmount);

        bool success = IERC20(collateralTokenAddress).transfer(to, collateralAmount);

        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _accountInformation(address user)
        private
        view
        returns (uint256 totalUsdMinted, uint256 collateralAmountInUsd)
    {
        totalUsdMinted = s_DSCMinted[user];
        collateralAmountInUsd = getCollateralValue(user);
    }

    // function _healthFactor(address user) internal view returns (uint256) {
    //     (uint256 totalUsdMinted, uint256 collateralAmountInUsd) = _accountInformation(user);

    //     uint256 collateraAdjustedForThreshold = (collateralAmountInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
    //     return (collateraAdjustedForThreshold * PRECISION) / totalUsdMinted;
    // }

    function _healthFactor(address user) internal view returns (uint256) {
        (uint256 totalUsdMinted, uint256 collateralAmountInUsd) = _accountInformation(user);

        // If user has minted nothing, health factor is MAX_UINT (they're safe)
        if (totalUsdMinted == 0) {
            return type(uint256).max;
        }

        uint256 collateraAdjustedForThreshold = (collateralAmountInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        return (collateraAdjustedForThreshold * PRECISION) / totalUsdMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 healthFactor = _healthFactor(user);
        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BrokenHealthFactor(healthFactor);
        }
    }

    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;

        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        // This conditional is hypothetically unreachable
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    )
        internal
        pure
        returns (uint256)
    {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }


    // PUBLIC And External VIEW FUNCTIONS

    function calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    )
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function getTokenAmountFromUsd(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_tokenToPriceFeed[token]);
        (, int256 price, , , ) = priceFeed.staleCheckLatestRoundData();
        return (amount * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getCollateralValue(address user) public view returns (uint256 tokenCollateralUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            // address priceFeed = s_tokenToPriceFeed[token];
            uint256 tokenAmount = s_userToTokenDeposits[user][token];
            tokenCollateralUsd += getUsdValue(token, tokenAmount);
        }

        return tokenCollateralUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_tokenToPriceFeed[token]);
        (, int256 price, , , ) = priceFeed.staleCheckLatestRoundData();
        return(uint256(price) * ADDITIONAL_FEED_PRECISION * amount) / PRECISION;
    }

    function getAccountInformation(address user)
        public
        view
        returns (uint256 totalUsdMinted, uint256 collateralAmountInUsd)
    {
        (totalUsdMinted, collateralAmountInUsd) = _accountInformation(user);
    }

    function getMintedDsc(address user) external view returns (uint256) {
        return s_DSCMinted[user];
    }

    function getUserCollateralBalance(address user, address token) external view returns (uint256) {
        return s_userToTokenDeposits[user][token];
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getPriceFeed(address token) external view returns (address) {
        return s_tokenToPriceFeed[token];
    }

    function updateUserCollateralPrice(address collateral, address user, uint256 amount) public {
        s_userToTokenDeposits[user][collateral] = amount;
    }

    function updateMintedValue(address user, uint256 amount) public {
        s_DSCMinted[user] = amount;
    }
}
