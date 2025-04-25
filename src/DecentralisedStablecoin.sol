// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Decentralised Stablecoin
 * @author Peace (Teejay)
 * Collateral: Exogenous
 * Minting (Stability Mechanism): Decentralized (Algorithmic)
 * Value (Relative Stability): Anchored (Pegged to USD)
 * Collateral Type: Crypto
 * This is the contract meant to be owned by DSCEngine. It is a ERC20 token that can be minted and burned by the
 *     DSCEngine smart contract.
 */
contract DecentralisedStablecoin is ERC20Burnable, Ownable {
    error DecentralisedStablecoin__InsufficientBalance();
    error DecentralisedStablecoin__AmountMustBeGreaterThanZero();
    error DecentralisedStablecoin__AddressNotValid();

    constructor() ERC20("DecentralisedStablecoin", "DSC") {}

    function burn(uint256 _amount) public override {
        uint256 balance = balanceOf(msg.sender);

        if (_amount <= 0) {
            revert DecentralisedStablecoin__AmountMustBeGreaterThanZero();
        }
        if (balance < _amount) {
            revert DecentralisedStablecoin__InsufficientBalance();
        }

        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) public onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralisedStablecoin__AddressNotValid();
        }

        if (_amount == 0) {
            revert DecentralisedStablecoin__AmountMustBeGreaterThanZero();
        }

        _mint(_to, _amount);

        return true;
    }
}
