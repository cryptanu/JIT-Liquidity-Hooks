// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Demo launch token with explicitly controlled minting.
/// @dev This token is for local/testing/demo use only.
contract MockNewAssetToken is ERC20, Ownable {
    mapping(address => bool) public minters;

    error UnauthorizedMinter(address caller);

    event MinterUpdated(address indexed minter, bool allowed);

    constructor(string memory name_, string memory symbol_, address initialOwner)
        ERC20(name_, symbol_)
        Ownable(initialOwner)
    {}

    function setMinter(address minter, bool allowed) external onlyOwner {
        minters[minter] = allowed;
        emit MinterUpdated(minter, allowed);
    }

    function mint(address to, uint256 amount) external {
        if (!minters[msg.sender]) revert UnauthorizedMinter(msg.sender);
        _mint(to, amount);
    }
}
