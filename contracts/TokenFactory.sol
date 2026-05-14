// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Pausable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract Token is ERC20, ERC20Burnable, ERC20Pausable, Ownable, ERC20Permit {
    constructor(
        string memory name_,
        string memory symbol_,
        address recipient,
        address initialOwner,
        uint256 initialSupply
    )
        ERC20(name_, symbol_)
        Ownable(initialOwner)
        ERC20Permit(name_)
    {
        _mint(recipient, initialSupply);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Pausable)
    {
        super._update(from, to, value);
    }
}

contract TokenFactory is Ownable {
    address[] public allTokens;

    event TokenCreated(
        address indexed token,
        string name,
        string symbol,
        address indexed owner,
        uint256 initialSupply
    );

    constructor(address initialOwner) Ownable(initialOwner) {}

    function createToken(
        string memory name_,
        string memory symbol_,
        address recipient,
        address tokenOwner,
        uint256 initialSupply
    ) external returns (address tokenAddress) {
        Token token = new Token(
            name_,
            symbol_,
            recipient,
            tokenOwner,
            initialSupply
        );

        tokenAddress = address(token);

        allTokens.push(tokenAddress);

        emit TokenCreated(
            tokenAddress,
            name_,
            symbol_,
            tokenOwner,
            initialSupply
        );
    }

    function getAllTokens() external view returns (address[] memory) {
        return allTokens;
    }

    function totalTokens() external view returns (uint256) {
        return allTokens.length;
    }
}