// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {
    Ownable,
    Ownable2Step
} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Wrapper} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Wrapper.sol";
import {IComp} from "./vendor/@compound-finance/compound-governance/contracts/interfaces/IComp.sol";

/// @title dCOMP
/// @author API3 DAO
/// @notice 1:1 wrapper token for COMP built on OpenZeppelin ERC20Wrapper
contract DComp is ERC20Wrapper, Ownable2Step {
    address internal constant COMP_ADDRESS =
        0xc00e94Cb662C3520282E6f5717214004A7f26888;
    IComp internal immutable comp = IComp(COMP_ADDRESS);

    /// @notice Tracks which addresses are allowed to deposit COMP.
    /// @dev Withdrawals are never restricted by this whitelist, including when dCOMP is transferred,
    /// when a depositor is later removed from the whitelist, or when COMP is deposited for another address via `depositFor`.
    mapping(address => bool) public isDepositorWhitelisted;

    /// @notice Emitted when an address whitelist status changes
    /// @param account Address whose whitelist status changed
    /// @param isWhitelisted New whitelist status
    event DepositorWhitelistStatusUpdated(
        address indexed account,
        bool isWhitelisted
    );

    modifier onlyWhitelisted() {
        require(
            isDepositorWhitelisted[msg.sender],
            "Caller is not whitelisted"
        );
        _;
    }

    /// @notice Constructs the dCOMP wrapper
    /// @param initialOwner Address of the initial owner
    /// @param initialDelegatee Address of the initial delegatee for COMP voting power
    /// @param whitelistedDepositors Initial addresses allowed to deposit COMP
    constructor(
        address initialOwner,
        address initialDelegatee,
        address[] memory whitelistedDepositors
    )
        ERC20("dCOMP", "dCOMP")
        ERC20Wrapper(IERC20(COMP_ADDRESS))
        Ownable(initialOwner)
    {
        _setDelegatee(initialDelegatee);

        for (uint256 i = 0; i < whitelistedDepositors.length; ++i) {
            _setDepositorWhitelistStatus(whitelistedDepositors[i], true);
        }
    }

    /// @notice Returns the current COMP delegatee for voting power held by this wrapper
    /// @return delegateeAddress Current delegatee address
    function delegatee() external view returns (address) {
        return comp.delegates(address(this));
    }

    /// @notice Wraps COMP tokens into dCOMP for a specific recipient at a 1:1 ratio
    /// @param account Recipient of newly minted dCOMP
    /// @param value Amount of COMP to deposit
    /// @return success Whether wrapping succeeded
    function depositFor(
        address account,
        uint256 value
    ) public override onlyWhitelisted returns (bool) {
        return super.depositFor(account, value);
    }

    /// @notice Wraps COMP tokens for the caller at a 1:1 ratio
    /// @param value Amount of COMP to deposit
    /// @return success Whether wrapping succeeded
    function deposit(uint256 value) external onlyWhitelisted returns (bool) {
        return depositFor(msg.sender, value);
    }

    /// @notice Unwraps dCOMP tokens for the caller at a 1:1 ratio
    /// @param value Amount of dCOMP to burn and withdraw as COMP
    /// @return success Whether unwrapping succeeded
    function withdraw(uint256 value) external returns (bool) {
        return withdrawTo(msg.sender, value);
    }

    /// @notice Updates depositor whitelist
    /// @param addresses Addresses whose whitelist status will be updated
    /// @param isAddressWhitelisted New whitelist status for each corresponding address
    function updateWhitelistedDepositors(
        address[] calldata addresses,
        bool[] calldata isAddressWhitelisted
    ) external onlyOwner {
        require(
            addresses.length == isAddressWhitelisted.length,
            "Mismatched array lengths"
        );

        for (uint256 i = 0; i < addresses.length; ++i) {
            _setDepositorWhitelistStatus(addresses[i], isAddressWhitelisted[i]);
        }
    }

    /// @notice Allows the owner to change who receives the aggregated voting power
    /// @param newDelegatee The new address to receive the COMP voting power
    function setDelegatee(address newDelegatee) external onlyOwner {
        _setDelegatee(newDelegatee);
    }

    /// @notice Updates whitelist status for a depositor
    /// @param account Address whose whitelist status is being updated
    /// @param isWhitelisted New whitelist status for the address
    function _setDepositorWhitelistStatus(
        address account,
        bool isWhitelisted
    ) internal {
        require(
            isDepositorWhitelisted[account] != isWhitelisted,
            "No change in whitelist status"
        );

        isDepositorWhitelisted[account] = isWhitelisted;
        emit DepositorWhitelistStatusUpdated(account, isWhitelisted);
    }

    /// @notice Updates delegated voting power recipient for COMP held by this wrapper
    /// @param newDelegatee New delegatee address
    function _setDelegatee(address newDelegatee) internal {
        comp.delegate(newDelegatee);
    }
}